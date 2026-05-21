import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Auto-hide delay applied after the chrome (AppBar) becomes visible
/// or the user interacts with the image area.
const Duration kChromeAutoHideDelay = Duration(seconds: 3);

/// Cross-fade duration for the chrome (AppBar) show / hide animation.
const Duration kChromeAnimationDuration = Duration(milliseconds: 200);

/// Duration of the double-tap zoom-in / zoom-out animation.
const Duration kZoomAnimationDuration = Duration(milliseconds: 250);

/// Scale factor applied on the first leg of the double-tap zoom.
const double kDoubleTapZoomScale = 2.0;

/// Maximum scale allowed by [InteractiveViewer] (also the pinch ceiling).
const double kMaxScale = 4.0;

/// Distance (logical px) the user must drag downward before release
/// counts as drag-to-dismiss; below this the body snaps back.
const double kDragToDismissDistance = 100;

/// Vertical fling velocity (logical px / s) above which a release counts
/// as drag-to-dismiss regardless of accumulated distance.
const double kDragToDismissFlingVelocity = 800;

/// Duration of the spring-back animation when a vertical drag is
/// released without crossing the dismiss threshold.
const Duration kDragSnapBackDuration = Duration(milliseconds: 250);

/// Threshold above which the page is considered "zoomed" — anything at
/// or below this is treated as identity (pan disabled, page swipe
/// allowed).
const double _kZoomedThreshold = 1.01;

/// Snapshot of the current page's gesture state. Consumed by
/// [_ImmersivePageScrollPhysics] to decide whether the surrounding
/// [PageView] should accept a horizontal drag.
@immutable
class _PageGestureState {
  const _PageGestureState({
    this.zoomed = false,
    this.atLeftEdge = true,
    this.atRightEdge = true,
  });

  /// `true` when the current page's scale is above [_kZoomedThreshold].
  final bool zoomed;

  /// When zoomed, `true` when the image cannot pan any further to the
  /// right (i.e. the matrix's translation is at its maximum positive
  /// value — the left side of the image is flush with the viewport).
  final bool atLeftEdge;

  /// When zoomed, `true` when the image cannot pan any further to the
  /// left (i.e. the right side of the image is flush with the viewport).
  final bool atRightEdge;

  @override
  bool operator ==(Object other) {
    return other is _PageGestureState &&
        other.zoomed == zoomed &&
        other.atLeftEdge == atLeftEdge &&
        other.atRightEdge == atRightEdge;
  }

  @override
  int get hashCode => Object.hash(zoomed, atLeftEdge, atRightEdge);
}

/// [ScrollBehavior] that lets the multi-image gallery's [PageView]
/// accept drags from **every** pointer device kind — including the
/// mouse on desktop / web, where Flutter's default `MaterialScrollBehavior`
/// only enables `PointerDeviceKind.touch` + `stylus` + `invertedStylus`
/// for scrollables. Without this override the desktop user cannot
/// drag the PageView to switch pages with a mouse, which is the entire
/// point of the multi-image viewer on a desktop build.
///
/// See the project spec
/// `.trellis/spec/frontend/component-guidelines.md` →
/// "Gotcha: Flutter 桌面端 PageView / ListView 默认不响应鼠标拖动".
class _ImmersiveScrollBehavior extends MaterialScrollBehavior {
  const _ImmersiveScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

/// Custom [ScrollPhysics] used by the multi-image gallery's [PageView].
///
/// Looks at a [ValueListenable] of [_PageGestureState] every time the
/// gesture system asks whether the user offset should be accepted:
///
/// * un-zoomed → behaves like the default [PageScrollPhysics] (page
///   swipes are always accepted)
/// * zoomed + free pan room in the drag direction → reject (let
///   [InteractiveViewer] pan the image)
/// * zoomed + image clamped against the edge + drag direction "outward"
///   (continuing in the direction we're already clamped) → accept,
///   letting the leftover drag delta bleed into a page change
///
/// The physics tracks the latest drag delta sign internally so it can
/// decide "outward vs inward" without a separate stream from the page.
class _ImmersivePageScrollPhysics extends PageScrollPhysics {
  const _ImmersivePageScrollPhysics({
    required this.stateListenable,
    super.parent,
  });

  final ValueListenable<_PageGestureState> stateListenable;

  @override
  _ImmersivePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ImmersivePageScrollPhysics(
      stateListenable: stateListenable,
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    final state = stateListenable.value;
    if (!state.zoomed) {
      return super.shouldAcceptUserOffset(position);
    }
    // While zoomed we still need to *receive* drag events so that the
    // "edge bleed" logic in [applyPhysicsToUserOffset] can decide
    // per-frame whether to consume them. Accept; the per-frame logic
    // returns 0 when the image is not clamped (and so the PageView
    // stays still).
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final state = stateListenable.value;
    if (!state.zoomed) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    // offset > 0 → PageView moves toward the next page (finger drags
    // leftward, image's right edge bleeds in). That requires the image
    // to be clamped against its *right* edge (atRightEdge == true).
    if (offset > 0 && state.atRightEdge) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    if (offset < 0 && state.atLeftEdge) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    // Drag direction is "inward" (we still have pan room) → swallow,
    // InteractiveViewer's own scale recognizer will handle it.
    return 0;
  }
}

/// Immersive full-screen photo viewer opened by tapping a
/// [PreviewThumbnail].
///
/// Behaviour overview (see PRD `05-22-export-preview-fullscreen-immersive`):
///
/// * Pure black background; content extends behind the status bar /
///   navigation bar / iOS home indicator so the image fills the whole
///   physical screen
/// * Transparent overlaid [AppBar] — single tap on the image area
///   toggles chrome visibility (auto-hides after 3 s); a floating
///   close button stays visible regardless
/// * Unified gesture contract per page: `minScale = 1.0`, pan disabled
///   while un-zoomed, double-tap zooms to 2× at the tap point (with a
///   fall-back to the image centre when the tap lands in the
///   `BoxFit.contain` letter-box), pinch zoom always available
/// * Multi-image input is browsable via horizontal swipe through a
///   [PageView]; the custom [_ImmersivePageScrollPhysics] lets the
///   horizontal drag bleed naturally from "pan a zoomed image" to
///   "swipe to the next image" once the image hits its pan edge
/// * Vertical down-drag while un-zoomed dismisses the dialog
///   (drag-to-dismiss), with a 100 dp threshold / 800 dp/s fling
///
/// The widget intentionally does NOT toggle system overlays — the
/// status bar and bottom system bar remain in their default
/// translucent state so we never have to restore them on dispose.
class PreviewFullScreenDialog extends StatefulWidget {
  const PreviewFullScreenDialog({
    super.key,
    required this.bytes,
    this.initialIndex = 0,
  }) : assert(
         bytes.length > 0,
         'PreviewFullScreenDialog requires at least one image',
       );

  /// Encoded image bytes — one entry per page. Single-image callers
  /// pass `[bytes]` and the dialog renders without page navigation.
  ///
  /// Must contain at least one element; an empty list is asserted
  /// against in the constructor because the upstream
  /// [PreviewThumbnail] entry point always provides at least
  /// `[bytes]` (single-image path) or a non-empty grid list — an
  /// empty list reaching this dialog indicates a caller bug.
  final List<Uint8List> bytes;

  /// Initial page when [bytes] has more than one element. Clamped to
  /// the valid range in [initState] (negative / out-of-range values
  /// are tolerated; they snap to the nearest valid page).
  final int initialIndex;

  @override
  State<PreviewFullScreenDialog> createState() =>
      _PreviewFullScreenDialogState();
}

class _PreviewFullScreenDialogState extends State<PreviewFullScreenDialog>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late final PageController _pageController;
  late final ValueNotifier<_PageGestureState> _gestureState;
  bool _chromeVisible = true;
  Timer? _autoHideTimer;

  /// Mirror of `_gestureState.value.zoomed` that lives in plain
  /// `setState`-driven local state so the [build] method can flip
  /// the outer vertical-drag callbacks between live closures and
  /// `null` based on it.
  ///
  /// Crucially: passing `null` for `onVerticalDragStart` etc. in
  /// [GestureDetector] makes the widget **not register** its
  /// [VerticalDragGestureRecognizer] for that build cycle, which is
  /// the only way to keep that recognizer **out of the gesture
  /// arena** when the page is zoomed. Returning early inside the
  /// callback would be too late — the recognizer would have already
  /// won the arena and would still consume every subsequent pointer
  /// event, locking InteractiveViewer out of single-finger pan.
  ///
  /// `_gestureState` (the `ValueNotifier`) remains the source of
  /// truth for the custom `ScrollPhysics`, which cannot rebuild via
  /// `setState`; this field is its `setState`-friendly twin.
  bool _currentZoomed = false;

  // Drag-to-dismiss state.
  late final AnimationController _dragSnapBack;
  double _dragOffsetY = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.bytes.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _gestureState = ValueNotifier<_PageGestureState>(const _PageGestureState());
    _dragSnapBack = AnimationController(
      vsync: this,
      duration: kDragSnapBackDuration,
    )..addListener(_onSnapBackTick);
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _pageController.dispose();
    _gestureState.dispose();
    _dragSnapBack.removeListener(_onSnapBackTick);
    _dragSnapBack.dispose();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(kChromeAutoHideDelay, () {
      if (!mounted) return;
      if (_chromeVisible) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _scheduleAutoHide();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  void _onPageChanged(int newIndex) {
    setState(() {
      _currentIndex = newIndex;
      // A page change implies the new page begins at identity (its
      // [_PreviewPage] is freshly built by [PageView.builder]). Reset
      // the shared gesture state pessimistically; the new page's own
      // listener will refresh it on the next matrix tick.
      _gestureState.value = const _PageGestureState();
      _currentZoomed = false;
    });
  }

  void _onPageGestureChanged(int pageIndex, _PageGestureState s) {
    // Only the *current* page's state may drive the shared notifier.
    // Off-screen pages still fire their TransformationController
    // listeners during PageView.builder's keep-alive period but their
    // state is irrelevant to the user-visible page.
    if (pageIndex != _currentIndex) return;
    if (_gestureState.value != s) _gestureState.value = s;
    // The `_currentZoomed` mirror must drive a rebuild so the outer
    // GestureDetector's vertical-drag callbacks can be nulled out
    // (zoomed → no recognizer) or restored (un-zoomed → recognizer
    // active). See the doc on the field for why this can't live
    // inside the callback bodies.
    if (s.zoomed != _currentZoomed) {
      setState(() => _currentZoomed = s.zoomed);
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    // Build-time guard (callbacks are nulled out when `_currentZoomed`)
    // means we should never even be invoked while zoomed. Keep the
    // belt-and-suspenders check anyway — if a future refactor wires
    // the callback unconditionally we still want to no-op rather than
    // start a dismiss drag on a zoomed image.
    if (_currentZoomed) return;
    _dragSnapBack.stop();
    setState(() {
      _dragging = true;
      _dragOffsetY = 0;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() {
      _dragOffsetY = (_dragOffsetY + details.delta.dy).clamp(
        0,
        double.infinity,
      );
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final flingDown =
        details.primaryVelocity != null &&
        details.primaryVelocity! > kDragToDismissFlingVelocity;
    if (_dragOffsetY > kDragToDismissDistance || flingDown) {
      Navigator.of(context).pop();
      return;
    }
    _animateSnapBack();
  }

  void _animateSnapBack() {
    final start = _dragOffsetY;
    _dragSnapBack.value = 0;
    _snapBackStart = start;
    _dragSnapBack.forward();
  }

  double _snapBackStart = 0;

  void _onSnapBackTick() {
    final t = Curves.easeOutCubic.transform(_dragSnapBack.value);
    final next = _snapBackStart * (1 - t);
    setState(() {
      _dragOffsetY = next;
      if (_dragSnapBack.isCompleted) {
        _dragging = false;
        _dragOffsetY = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.bytes.length > 1;
    final title = isMulti
        ? '${_currentIndex + 1} / ${widget.bytes.length}'
        : '预览';

    // Background opacity reflects how far the user has dragged. 0 dp
    // → 1.0 (opaque); kDragToDismissDistance → 0.4. Clamped to
    // [0.4, 1.0] per PRD R6.
    final bgOpacity = (1.0 - (_dragOffsetY / kDragToDismissDistance) * 0.6)
        .clamp(0.4, 1.0);

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: bgOpacity),
        child: GestureDetector(
          // Vertical drag-to-dismiss. The callbacks are nulled out
          // while the current page is zoomed so the underlying
          // [VerticalDragGestureRecognizer] is **not registered** at
          // all for that build cycle — keeping it out of the gesture
          // arena entirely so InteractiveViewer's own scale recognizer
          // can claim single-finger pan. Returning early inside the
          // callback would be too late (the recognizer would have
          // already won the arena).
          onVerticalDragStart: _currentZoomed ? null : _onVerticalDragStart,
          onVerticalDragUpdate: _currentZoomed ? null : _onVerticalDragUpdate,
          onVerticalDragEnd: _currentZoomed ? null : _onVerticalDragEnd,
          behavior: HitTestBehavior.deferToChild,
          child: Transform.translate(
            offset: Offset(0, _dragOffsetY),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              extendBodyBehindAppBar: true,
              body: Stack(
                children: [
                  // PageView / single-page image surface — fills the
                  // whole viewport.
                  Positioned.fill(
                    child: ScrollConfiguration(
                      // Desktop / web default `MaterialScrollBehavior`
                      // omits `PointerDeviceKind.mouse` from
                      // `dragDevices`, which would silently disable
                      // mouse-drag page switching on macOS / Windows /
                      // Linux / web builds. The custom behavior
                      // re-enables every device kind.
                      behavior: const _ImmersiveScrollBehavior(),
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _ImmersivePageScrollPhysics(
                          stateListenable: _gestureState,
                        ),
                        itemCount: widget.bytes.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (_, i) => _PreviewPage(
                          bytes: widget.bytes[i],
                          onTap: _toggleChrome,
                          onGestureStateChanged: (s) =>
                              _onPageGestureChanged(i, s),
                        ),
                      ),
                    ),
                  ),
                  // Transparent AppBar overlay. Built as a Positioned
                  // layer (not via Scaffold.appBar) so we can keep
                  // `IgnorePointer` around it — otherwise the AppBar's
                  // Material would absorb taps in the close-button area
                  // even when visually transparent.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !_chromeVisible,
                      child: AnimatedSlide(
                        duration: kChromeAnimationDuration,
                        offset: _chromeVisible
                            ? Offset.zero
                            : const Offset(0, -1),
                        child: AnimatedOpacity(
                          duration: kChromeAnimationDuration,
                          opacity: _chromeVisible ? 1.0 : 0.0,
                          child: AppBar(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            scrolledUnderElevation: 0,
                            foregroundColor: Colors.white,
                            systemOverlayStyle: SystemUiOverlayStyle.light,
                            centerTitle: true,
                            automaticallyImplyLeading: false,
                            title: Text(title),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Always-on floating close button (never hides with
                  // chrome). Stays on top of the AppBar overlay so it
                  // remains tappable even before the auto-hide fires.
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    child: _FloatingCloseButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One page of the immersive photo viewer.
///
/// Owns:
/// * a [TransformationController] driven by [InteractiveViewer]
/// * an [AnimationController] that animates the double-tap zoom / reset
/// * intrinsic image-size resolution so the double-tap focal point can
///   be clamped to the visible `BoxFit.contain` rect (taps in the
///   letterbox fall back to the image centre — the image never jumps
///   out of view)
///
/// Gesture contract:
/// * single tap on the page area → [onTap] (chrome toggle)
/// * double tap → animate to 2× at the tap point (or to identity if
///   already zoomed)
/// * `InteractiveViewer.panEnabled` is `false` while the current
///   matrix is at identity (so single-finger horizontal drag is left
///   to the outer [PageView]); flips to `true` the moment pinch zoom
///   or the double-tap animation lifts the scale above 1
///
/// Reports its zoom + horizontal-edge state up to the dialog via
/// [onGestureStateChanged] every time the [TransformationController]
/// matrix changes. The dialog feeds the state into
/// [_ImmersivePageScrollPhysics] so the PageView can decide whether to
/// accept the next drag.
class _PreviewPage extends StatefulWidget {
  const _PreviewPage({
    required this.bytes,
    required this.onTap,
    this.onGestureStateChanged,
  });

  final Uint8List bytes;
  final VoidCallback onTap;
  final ValueChanged<_PageGestureState>? onGestureStateChanged;

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapLocal = Offset.zero;
  bool _zoomed = false;
  Size? _imageSize;
  Size? _lastViewport;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  _PageGestureState _lastReportedState = const _PageGestureState();

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onMatrixChanged);
    _zoomAnim = AnimationController(
      vsync: this,
      duration: kZoomAnimationDuration,
    )..addListener(_onZoomTick);
    _resolveImageSize();
  }

  @override
  void dispose() {
    _tc.removeListener(_onMatrixChanged);
    _tc.dispose();
    _zoomAnim.removeListener(_onZoomTick);
    _zoomAnim.dispose();
    _detachImageListener();
    super.dispose();
  }

  void _detachImageListener() {
    if (_imageListener != null && _imageStream != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageListener = null;
    _imageStream = null;
  }

  void _resolveImageSize() {
    final provider = MemoryImage(widget.bytes);
    _imageStream = provider.resolve(const ImageConfiguration());
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      if (size != _imageSize) {
        setState(() => _imageSize = size);
        _reportGestureState();
      }
    });
    _imageStream!.addListener(_imageListener!);
  }

  void _onMatrixChanged() {
    final scale = _tc.value.getMaxScaleOnAxis();
    final zoomed = scale > _kZoomedThreshold;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
    _reportGestureState();
  }

  void _onZoomTick() {
    final tween = _zoomTween;
    if (tween != null) {
      _tc.value = tween.value;
    }
  }

  void _reportGestureState() {
    final cb = widget.onGestureStateChanged;
    if (cb == null) return;
    final scale = _tc.value.getMaxScaleOnAxis();
    if (scale <= _kZoomedThreshold) {
      const state = _PageGestureState(
        zoomed: false,
        atLeftEdge: true,
        atRightEdge: true,
      );
      if (_lastReportedState != state) {
        _lastReportedState = state;
        cb(state);
      }
      return;
    }
    final viewport = _lastViewport;
    final rect = viewport == null ? null : _imageDisplayRect(viewport);
    if (rect == null || viewport == null) {
      // Zoomed but geometry not yet known (viewport from LayoutBuilder
      // or intrinsic image size from the ImageStream hasn't resolved).
      // Still report the zoom state so the dialog can disable its
      // outer vertical-drag recognizer immediately — otherwise a fast
      // double-tap-then-pan sequence on app launch can race with the
      // image-stream resolution and leave the vertical-drag recognizer
      // in the arena, blocking InteractiveViewer's single-finger pan.
      const fallback = _PageGestureState(
        zoomed: true,
        atLeftEdge: false,
        atRightEdge: false,
      );
      if (_lastReportedState != fallback) {
        _lastReportedState = fallback;
        cb(fallback);
      }
      return;
    }
    final imageRenderedWidth = rect.width * scale;
    final maxTx = (imageRenderedWidth - rect.width) / 2;
    final tx = _tc.value.row0[3];
    // Edge tolerance — accommodate floating-point drift around the
    // clamp produced by InteractiveViewer's own boundary handling.
    const tol = 0.5;
    final atLeft = tx >= maxTx - tol;
    final atRight = tx <= -maxTx + tol;
    final state = _PageGestureState(
      zoomed: true,
      atLeftEdge: atLeft,
      atRightEdge: atRight,
    );
    if (_lastReportedState != state) {
      _lastReportedState = state;
      cb(state);
    }
  }

  void _handleDoubleTapDown(TapDownDetails d) {
    _doubleTapLocal = d.localPosition;
  }

  void _handleDoubleTap(Size viewport) {
    final current = _tc.value;
    final Matrix4 target;
    if (_zoomed) {
      target = Matrix4.identity();
    } else {
      final focal = _resolveFocalPoint(_doubleTapLocal, viewport);
      target = _zoomMatrix(kDoubleTapZoomScale, focal);
    }
    _zoomTween = Matrix4Tween(
      begin: current,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim
      ..reset()
      ..forward();
  }

  /// Returns the focal point for the double-tap zoom. When the tap
  /// lands inside the BoxFit.contain image rect we use the tap
  /// position; when it lands in the letterbox we fall back to the
  /// image centre so the magnified image doesn't fly out of view.
  Offset _resolveFocalPoint(Offset localTap, Size viewport) {
    final imageRect = _imageDisplayRect(viewport);
    if (imageRect == null || imageRect.contains(localTap)) {
      return localTap;
    }
    return imageRect.center;
  }

  /// Computes the rect occupied by the image inside the viewport under
  /// `BoxFit.contain`. Returns `null` until the image stream has
  /// reported the intrinsic size.
  Rect? _imageDisplayRect(Size viewport) {
    final imgSize = _imageSize;
    if (imgSize == null || imgSize.isEmpty || viewport.isEmpty) return null;
    final imageAspect = imgSize.width / imgSize.height;
    final viewportAspect = viewport.width / viewport.height;
    double displayWidth;
    double displayHeight;
    if (imageAspect > viewportAspect) {
      displayWidth = viewport.width;
      displayHeight = viewport.width / imageAspect;
    } else {
      displayHeight = viewport.height;
      displayWidth = viewport.height * imageAspect;
    }
    final left = (viewport.width - displayWidth) / 2;
    final top = (viewport.height - displayHeight) / 2;
    return Rect.fromLTWH(left, top, displayWidth, displayHeight);
  }

  Matrix4 _zoomMatrix(double scale, Offset focal) {
    // Scale around `focal`: t = focal * (1 - scale), so the focal pixel
    // is the fixed point of the transform.
    return Matrix4.identity()
      ..translateByDouble(focal.dx * (1 - scale), focal.dy * (1 - scale), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _lastViewport = viewport;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: () => _handleDoubleTap(viewport),
          child: InteractiveViewer(
            transformationController: _tc,
            // Pan is only available once the user has zoomed in. With
            // the page at identity, single-finger horizontal drag is
            // intentionally left for the surrounding PageView to claim.
            panEnabled: _zoomed,
            scaleEnabled: true,
            minScale: 1.0,
            maxScale: kMaxScale,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Center(
              child: Image.memory(
                widget.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Always-on close button rendered as a translucent black circle with a
/// white "X" glyph. Stays interactive regardless of chrome visibility
/// or zoom state so the user always has an obvious exit affordance.
class _FloatingCloseButton extends StatelessWidget {
  const _FloatingCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        tooltip: '关闭',
        onPressed: onPressed,
      ),
    );
  }
}
