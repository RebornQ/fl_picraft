import 'dart:async';

import 'package:extended_image/extended_image.dart';
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

/// Maximum scale allowed by [GestureConfig] (the pinch ceiling).
const double kMaxScale = 4.0;

/// Distance (logical px) the user must drag downward before release
/// counts as drag-to-dismiss; below this the body snaps back. Consumed
/// by both [_PreviewFullScreenDialogState._slideEndHandler] (threshold)
/// and [_PreviewFullScreenDialogState._slidePageBackgroundHandler]
/// (opacity-ramp denominator).
const double kDragToDismissDistance = 100;

/// Vertical fling velocity (logical px / s) above which a release counts
/// as drag-to-dismiss regardless of accumulated distance.
const double kDragToDismissFlingVelocity = 800;

/// [ScrollBehavior] that lets the multi-image gallery's
/// [ExtendedImageGesturePageView] accept drags from **every** pointer
/// device kind — including the mouse on desktop / web, where Flutter's
/// default `MaterialScrollBehavior` only enables `PointerDeviceKind.touch`
/// + `stylus` + `invertedStylus` for scrollables. Without this override
/// the desktop user cannot drag the gallery to switch pages with a mouse,
/// which is the entire point of the multi-image viewer on a desktop build.
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

/// Immersive full-screen photo viewer opened by tapping a
/// [PreviewThumbnail].
///
/// Built on top of `extended_image: ^10.0.1` (see ADR-0002). The widget
/// tree is a three-piece kit:
///
/// 1. [ExtendedImageSlidePage] (outer) — owns the drag-to-dismiss state
///    machine. [_PreviewFullScreenDialogState._slideEndHandler]
///    implements "100 dp threshold OR 800 dp/s fling";
///    [_PreviewFullScreenDialogState._slidePageBackgroundHandler] ramps
///    the backdrop from `Colors.black @ alpha 1.0` to `alpha 0.4` while
///    dragging. While the current page is zoomed
///    (`gestureDetails.totalScale > 1`), `extended_image` automatically
///    routes single-finger pan to the inner [ExtendedImageGesture]
///    instead of the SlidePage (see `gesture.dart:347-389`) — no caller
///    bookkeeping required.
/// 2. [ExtendedImageGesturePageView.builder] (middle) — the multi-image
///    gallery. Native edge-bleed page switching (the package's
///    `movePage()` + `canScrollPage` combination) coordinates pinch /
///    pan in the active page with horizontal swipes to neighbouring
///    pages. Wrapped in an [_ImmersiveScrollBehavior] so desktop mouse
///    + trackpad drag can drive page changes.
/// 3. [ExtendedImage.memory] in `ExtendedImageMode.gesture` (leaf) — owns
///    the per-page pinch / pan / double-tap gesture stack. The
///    `inPageView: true` flag wires its boundary detection into the
///    surrounding gallery so reaching an image edge bleeds into a page
///    change; `enableSlideOutPage: true` subscribes to the outer
///    SlidePage. Double-tap zoom is driven by a caller-owned
///    [AnimationController] inside [_PreviewPage] that repeatedly calls
///    [ExtendedImageGestureState.handleDoubleTap] to animate the scale
///    between identity and [kDoubleTapZoomScale].
///
/// Chrome (transparent overlaid [AppBar] + always-visible floating close
/// button) lives in the outer [Stack], independent of the
/// `ExtendedImageSlidePage` widget tree. A single tap on the image area
/// toggles chrome visibility (auto-hides after 3 s).
///
/// Trade-offs vs the self-rolled implementation (see ADR-0002):
///
/// * Spring-back animation curve degrades from `easeOutCubic` to linear
///   (the package's `_backAnimationController` is a raw
///   [AnimationController] with no exposed `CurvedAnimation`).
/// * Letter-box double-tap focal point fallback is no longer needed —
///   `extended_image` clamps the focal internally.
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

class _PreviewFullScreenDialogState extends State<PreviewFullScreenDialog> {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  bool _chromeVisible = true;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.bytes.length - 1);
    _pageController = ExtendedPageController(initialPage: _currentIndex);
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _pageController.dispose();
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
    setState(() => _currentIndex = newIndex);
  }

  /// Customizes drag-to-dismiss completion logic for the outer
  /// [ExtendedImageSlidePage]. Returns:
  /// * `true` → the package pops the route (dismissed).
  /// * `false` → the package springs back to identity.
  /// * `null` → fall back to the package's default heuristic (used as a
  ///   safety net when the optional state / details aren't supplied;
  ///   matches the pattern from `extended_image`'s own example).
  bool? _slideEndHandler(
    Offset offset, {
    ExtendedImageSlidePageState? state,
    ScaleEndDetails? details,
  }) {
    if (state == null || details == null) return null;
    final dy = offset.dy.abs();
    final flingV = details.velocity.pixelsPerSecond.dy.abs();
    if (dy >= kDragToDismissDistance || flingV >= kDragToDismissFlingVelocity) {
      return true;
    }
    return false;
  }

  /// Linear background-opacity ramp from `alpha = 1.0` (no drag) to
  /// `alpha = 0.4` once the drag reaches [kDragToDismissDistance].
  /// Clamped at the 0.4 floor so the backdrop never fully fades — the
  /// user always sees the close button + AppBar text contrast against
  /// some black.
  Color _slidePageBackgroundHandler(Offset offset, Size pageSize) {
    final fraction = (offset.dy.abs() / kDragToDismissDistance).clamp(0.0, 1.0);
    final alpha = (1.0 - fraction * 0.6).clamp(0.4, 1.0);
    return Colors.black.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.bytes.length > 1;
    final title = isMulti
        ? '${_currentIndex + 1} / ${widget.bytes.length}'
        : '预览';

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: ExtendedImageSlidePage(
        slideAxis: SlideAxis.vertical,
        slideType: SlideType.onlyImage,
        slideEndHandler: _slideEndHandler,
        slidePageBackgroundHandler: _slidePageBackgroundHandler,
        // Disable the package's own child-scale animation so the inner
        // image stays at 1.0 while dragging — we only want the backdrop
        // to fade, not the image to shrink (matches the prior UX).
        slideScaleHandler: (_, {ExtendedImageSlidePageState? state}) => 1.0,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              // The multi-image gallery — fills the whole viewport.
              Positioned.fill(
                child: ScrollConfiguration(
                  behavior: const _ImmersiveScrollBehavior(),
                  child: ExtendedImageGesturePageView.builder(
                    controller: _pageController,
                    itemCount: widget.bytes.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      return _PreviewPage(
                        bytes: widget.bytes[index],
                        onTap: _toggleChrome,
                      );
                    },
                  ),
                ),
              ),
              // Transparent AppBar overlay. Built as a Positioned layer
              // (not via Scaffold.appBar) so we can keep `IgnorePointer`
              // around it — otherwise the AppBar's Material would absorb
              // taps in the close-button area even when visually
              // transparent.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedSlide(
                    duration: kChromeAnimationDuration,
                    offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
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
              // Always-on floating close button (never hides with chrome).
              // Stays on top of the AppBar overlay so it remains tappable
              // even before the auto-hide fires.
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
    );
  }
}

/// One page of the immersive photo viewer.
///
/// Owns a caller-driven [AnimationController] that animates the
/// double-tap zoom by repeatedly calling
/// [ExtendedImageGestureState.handleDoubleTap]. The package's built-in
/// double-tap (when [ExtendedImage.onDoubleTap] is `null`) only resets
/// the gesture state to `initialScale` — i.e. it can only zoom OUT, not
/// IN. To zoom IN to [kDoubleTapZoomScale] at the tap focal point we
/// drive an [AnimationController] whose listener feeds successive
/// `scale` values into
/// `state.handleDoubleTap(scale: ..., doubleTapPosition: ...)`. Pattern
/// lifted from `extended_image`'s own
/// `example/lib/common/widget/pic_swiper.dart`.
///
/// A single tap on the page area is propagated to [onTap] (the parent
/// dialog uses this for chrome toggling). The outer [GestureDetector]
/// is `HitTestBehavior.translucent` so the inner [ExtendedImage] still
/// sees pinch / double-tap pointer events — the gesture arena lets
/// each layer claim the gesture it cares about.
class _PreviewPage extends StatefulWidget {
  const _PreviewPage({required this.bytes, required this.onTap});

  final Uint8List bytes;
  final VoidCallback onTap;

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doubleTapAc;
  Animation<double>? _doubleTapAnimation;
  VoidCallback? _doubleTapListener;

  @override
  void initState() {
    super.initState();
    _doubleTapAc = AnimationController(
      vsync: this,
      duration: kZoomAnimationDuration,
    );
  }

  @override
  void dispose() {
    if (_doubleTapAnimation != null && _doubleTapListener != null) {
      _doubleTapAnimation!.removeListener(_doubleTapListener!);
    }
    _doubleTapAc.dispose();
    super.dispose();
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    final pointerDownPosition = state.pointerDownPosition;
    final begin = state.gestureDetails?.totalScale ?? 1.0;
    final end = begin == 1.0 ? kDoubleTapZoomScale : 1.0;
    _doubleTapAc.stop();
    _doubleTapAc.reset();
    if (_doubleTapAnimation != null && _doubleTapListener != null) {
      _doubleTapAnimation!.removeListener(_doubleTapListener!);
    }
    _doubleTapAnimation = _doubleTapAc.drive(
      Tween<double>(begin: begin, end: end),
    );
    _doubleTapListener = () {
      state.handleDoubleTap(
        scale: _doubleTapAnimation!.value,
        doubleTapPosition: pointerDownPosition,
      );
    };
    _doubleTapAnimation!.addListener(_doubleTapListener!);
    _doubleTapAc.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Single tap toggles chrome via [widget.onTap]. `translucent` lets
      // pointer events reach the inner ExtendedImage too — Flutter's
      // gesture arena then routes single tap to this outer
      // TapGestureRecognizer and routes double-tap / pinch to the
      // ExtendedImage's inner stack. `opaque` would block the inner
      // pinch/double-tap entirely.
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      child: ExtendedImage.memory(
        widget.bytes,
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableSlideOutPage: true,
        onDoubleTap: _handleDoubleTap,
        initGestureConfigHandler: (state) {
          return GestureConfig(
            inPageView: true,
            minScale: 1.0,
            maxScale: kMaxScale,
            animationMinScale: 0.8,
            animationMaxScale: kMaxScale + 0.5,
            initialScale: 1.0,
            initialAlignment: InitialAlignment.center,
          );
        },
      ),
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
