// TODO(ST4): remove after migration completes. This whole `lib/_poc/`
// directory exists only for the ST1 risk-gate of task
// `05-22-brainstorm-fullscreen-preview-extended-image`. Once ST2/ST3/ST4
// have migrated `preview_full_screen_dialog.dart` and
// `preview_thumbnail.dart` to extended_image, delete this file AND the
// `_PocDebugLauncher` entry from `home_screen.dart`.

import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Distance (logical px) the user must drag downward before release
/// triggers a dismiss. Mirrors `kDragToDismissDistance` from the
/// existing implementation so the PoC is testing the same UX contract.
const double _kDragToDismissDistance = 100;

/// Vertical fling velocity (logical px / s) above which a release counts
/// as drag-to-dismiss regardless of accumulated distance.
const double _kDragToDismissFlingVelocity = 800;

/// Max scale allowed by the PoC's `GestureConfig`.
const double _kMaxScale = 4.0;

/// Scale factor used on the first leg of the double-tap zoom.
const double _kDoubleTapZoomScale = 2.0;

/// Duration of the double-tap zoom-in / zoom-out animation.
const Duration _kZoomAnimationDuration = Duration(milliseconds: 250);

/// Minimal proof-of-concept widget for the
/// `extended_image: ^10.0.1` migration risk gate.
///
/// Demonstrates the **complete three-piece kit** that ST2 will
/// eventually use in production:
///
/// 1. **`ExtendedImageSlidePage`** (outer) — owns the drag-to-dismiss
///    state machine. `slideEndHandler` implements "100 dp threshold OR
///    800 dp/s fling"; `slidePageBackgroundHandler` ramps the backdrop
///    from `Colors.black @ alpha 1.0` to `alpha 0.4` while dragging.
/// 2. **`ExtendedImageGesturePageView.builder`** (middle) — the
///    multi-image gallery. Native edge-bleed page switching
///    (`movePage()` + `canScrollPage`) replaces our self-rolled
///    `_ImmersivePageScrollPhysics` from the existing
///    `preview_full_screen_dialog.dart`. Wrapped in a
///    [_PocScrollBehavior] that mirrors the existing
///    `_ImmersiveScrollBehavior` so desktop mouse + trackpad drag can
///    drive the page change (Flutter's default `MaterialScrollBehavior`
///    omits `PointerDeviceKind.mouse` — see
///    `.trellis/spec/frontend/component-guidelines.md` → "Gotcha:
///    Flutter 桌面端 PageView / ListView 默认不响应鼠标拖动").
/// 3. **`ExtendedImage.memory(..., mode: ExtendedImageMode.gesture,
///    enableSlideOutPage: true, initGestureConfigHandler: ...)`** (leaf)
///    — the per-page widget that owns the pinch / pan / double-tap
///    gesture stack. `inPageView: true` wires its boundary detection
///    into the surrounding gallery so reaching an image edge bleeds
///    into a page change; `enableSlideOutPage: true` subscribes to the
///    outer SlidePage so single-finger vertical pan (only while
///    un-zoomed — `gesture.dart:347-389` enforces this automatically)
///    drives the dismiss.
///
/// Three risk flags this PoC was built to retire (the human verifies
/// manually after running the app — see
/// `.trellis/tasks/05-22-extimage-dep-and-poc/poc-report.md`):
///
/// * **#736** drag-to-dismiss + GesturePageView fragility (Android iOS)
/// * **#761** v10.0.1 iOS `.memory + BoxFit.contain` regression
/// * Desktop mouse drag for page switching (officially untested)
class ExtendedImagePoc extends StatefulWidget {
  const ExtendedImagePoc({super.key});

  /// Opens the PoC over the current navigator using a transparent
  /// `PageRouteBuilder`. The transparency is required so the SlidePage
  /// background handler (which paints the underlying canvas) can be
  /// seen — otherwise the route would have its own opaque material
  /// underneath and the alpha ramp would have no visual effect.
  static void open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => const ExtendedImagePoc(),
      ),
    );
  }

  @override
  State<ExtendedImagePoc> createState() => _ExtendedImagePocState();
}

class _ExtendedImagePocState extends State<ExtendedImagePoc>
    with SingleTickerProviderStateMixin {
  late final List<Uint8List> _images;
  late final ExtendedPageController _pageController;
  late final AnimationController _doubleTapAc;

  /// Drives the double-tap zoom by feeding incremental scale values
  /// into the active `ExtendedImageGestureState.handleDoubleTap(...)`.
  /// See the listener registered in [_handleDoubleTap] for details.
  Animation<double>? _doubleTapAnimation;
  VoidCallback? _doubleTapListener;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _images = _genPocImages();
    _pageController = ExtendedPageController(initialPage: 0);
    _doubleTapAc = AnimationController(
      vsync: this,
      duration: _kZoomAnimationDuration,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (_doubleTapAnimation != null && _doubleTapListener != null) {
      _doubleTapAnimation!.removeListener(_doubleTapListener!);
    }
    _doubleTapAc.dispose();
    super.dispose();
  }

  /// Customizes drag-to-dismiss completion logic. Returns:
  /// * `true` → SlidePage pops the route (dismissed).
  /// * `false` → SlidePage springs back to identity.
  /// * `null` → SlidePage falls back to its default heuristic
  ///   (`pageSize/6`). Used as a safety net when the optional state /
  ///   details aren't supplied — the official extended_image example
  ///   uses the same null guard despite the typedef declaring those
  ///   args as non-nullable.
  bool? _slideEndHandler(
    Offset offset, {
    ExtendedImageSlidePageState? state,
    ScaleEndDetails? details,
  }) {
    if (state == null || details == null) return null;
    final dy = offset.dy.abs();
    final flingV = details.velocity.pixelsPerSecond.dy.abs();
    if (dy >= _kDragToDismissDistance ||
        flingV >= _kDragToDismissFlingVelocity) {
      return true;
    }
    return false;
  }

  /// Linear background-opacity ramp from `alpha = 1.0` (no drag) to
  /// `alpha = 0.4` once the drag reaches [_kDragToDismissDistance].
  /// Clamped at the 0.4 floor so the backdrop never fully fades — the
  /// user always sees the close button + AppBar text contrast against
  /// some black.
  Color _slidePageBackgroundHandler(Offset offset, Size pageSize) {
    final fraction = (offset.dy.abs() / _kDragToDismissDistance).clamp(
      0.0,
      1.0,
    );
    final alpha = (1.0 - fraction * 0.6).clamp(0.4, 1.0);
    return Colors.black.withValues(alpha: alpha);
  }

  /// Caller-owned double-tap zoom animation. `extended_image`'s
  /// built-in double-tap (when `onDoubleTap` is `null`) only resets the
  /// gesture state to `initialScale` — i.e. it can only zoom OUT, not
  /// IN. To zoom IN to 2× at the tap focal point we drive an
  /// `AnimationController` whose listener feeds successive `scale`
  /// values into `state.handleDoubleTap(scale: ..., doubleTapPosition:
  /// ...)`. Pattern lifted from `extended_image`'s own
  /// `example/lib/common/widget/pic_swiper.dart:457-490`.
  void _handleDoubleTap(ExtendedImageGestureState state) {
    final pointerDownPosition = state.pointerDownPosition;
    final begin = state.gestureDetails?.totalScale ?? 1.0;
    final end = begin == 1.0 ? _kDoubleTapZoomScale : 1.0;
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

  void _onPageChanged(int newIndex) {
    setState(() => _currentIndex = newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_currentIndex + 1} / ${_images.length}';
    return Material(
      color: Colors.transparent,
      child: ExtendedImageSlidePage(
        slideAxis: SlideAxis.vertical,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: _slidePageBackgroundHandler,
        slideEndHandler: _slideEndHandler,
        // Disable SlidePage's own child-scale animation so the inner
        // image stays at 1.0 while dragging (we only want the backdrop
        // to fade, not the image to shrink — matches the existing
        // dialog's drag-to-dismiss UX).
        slideScaleHandler: (_, {ExtendedImageSlidePageState? state}) => 1.0,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  // Desktop / web default `MaterialScrollBehavior`
                  // omits `PointerDeviceKind.mouse` — without this
                  // override the desktop user cannot drag the
                  // PageView with a mouse, which is the entire point
                  // of risk-flag (c). Mirrors the production
                  // `_ImmersiveScrollBehavior` so the PoC can faithfully
                  // verify the desktop drag path.
                  behavior: const _PocScrollBehavior(),
                  child: ExtendedImageGesturePageView.builder(
                    controller: _pageController,
                    itemCount: _images.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      return ExtendedImage.memory(
                        _images[index],
                        fit: BoxFit.contain,
                        mode: ExtendedImageMode.gesture,
                        enableSlideOutPage: true,
                        onDoubleTap: _handleDoubleTap,
                        initGestureConfigHandler: (state) {
                          return GestureConfig(
                            inPageView: true,
                            minScale: 1.0,
                            maxScale: _kMaxScale,
                            animationMinScale: 0.8,
                            animationMaxScale: _kMaxScale + 0.5,
                            initialScale: 1.0,
                            initialAlignment: InitialAlignment.center,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              // Transparent AppBar overlay — built as a Positioned
              // layer (not via Scaffold.appBar) so the floating close
              // button below stays tappable. Spec:
              // `.trellis/spec/frontend/component-guidelines.md` →
              // "Scaffold.appBar 槽位的 Material 即使透明也会吃掉下层
              // hit-test".
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  title: Text('PoC: $title'),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '关闭 PoC',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom `ScrollBehavior` that enables ALL six pointer device kinds
/// — including mouse and trackpad — to drive scroll gestures. Without
/// this, Flutter's default `MaterialScrollBehavior` would silently
/// drop mouse drag events on the `ExtendedImageGesturePageView` and
/// risk-flag (c) verification would be inconclusive (the user
/// wouldn't be able to tell whether the bug is in `extended_image`
/// itself or in the missing `dragDevices` override).
class _PocScrollBehavior extends MaterialScrollBehavior {
  const _PocScrollBehavior();

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

/// Generates three distinct PNG images with different aspect ratios so
/// the manual verifier can:
/// * Tell pages apart at a glance (distinct background colors).
/// * Observe `BoxFit.contain` letterbox bands of different shapes
///   (landscape / portrait / square).
/// * Confirm pinch zoom + double-tap zoom focal-point behavior on
///   pages that DON'T fill the viewport.
///
/// Computed once in `initState` and cached for the lifetime of the
/// PoC widget — synchronous decode/encode cost (≈ 10-30 ms total for
/// three small PNGs) is acceptable for a debug-only PoC.
List<Uint8List> _genPocImages() {
  return [
    _solidWithFrame(1200, 900, r: 230, g: 80, b: 80), // red landscape
    _solidWithFrame(900, 1600, r: 80, g: 200, b: 110), // green portrait
    _solidWithFrame(1024, 1024, r: 80, g: 130, b: 230), // blue square
  ];
}

/// Builds an `image: ^4.3.0` `Image` of the given size filled with the
/// provided RGB color and a centered white rectangle (1/3 of each
/// dimension), then encodes it to PNG bytes. The white frame gives
/// the verifier a clear visual reference for pinch / pan / zoom
/// transforms.
Uint8List _solidWithFrame(
  int width,
  int height, {
  required int r,
  required int g,
  required int b,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorUint8.rgb(r, g, b));
  final w3 = width ~/ 3;
  final h3 = height ~/ 3;
  img.fillRect(
    image,
    x1: w3,
    y1: h3,
    x2: width - w3,
    y2: height - h3,
    color: img.ColorUint8.rgb(255, 255, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}
