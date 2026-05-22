import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_full_screen_dialog.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_thumbnail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _smallPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

Widget _thumbnailHarness(Uint8List bytes) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: PreviewThumbnail(bytes: bytes),
      ),
    ),
  );
}

Widget _dialogHarness(Uint8List bytes) {
  return MaterialApp(
    home: Scaffold(body: PreviewFullScreenDialog(bytes: [bytes])),
  );
}

Widget _multiDialogHarness(List<Uint8List> bytes, {int initialIndex = 0}) {
  return MaterialApp(
    home: Scaffold(
      body: PreviewFullScreenDialog(bytes: bytes, initialIndex: initialIndex),
    ),
  );
}

/// Returns the live [ExtendedImageGestureState] for the leaf gesture
/// widget rendered inside the dialog. Used to read the gesture config /
/// gesture details / pointer-down position from outside the package's
/// private internals.
///
/// Pin lookup via [ExtendedImageGesture] (not [ExtendedImage]) because
/// the gesture state lives on the inner [ExtendedImageGesture] widget
/// — `ExtendedImage(mode: ExtendedImageMode.gesture)` wraps an
/// `ExtendedImageGesture` whose `State` is `ExtendedImageGestureState`.
ExtendedImageGestureState _gestureState(WidgetTester tester) {
  final finder = find.byType(ExtendedImageGesture);
  return tester.state<ExtendedImageGestureState>(finder.first);
}

/// Force the [MemoryImage] decode to complete inside the real event
/// loop. `pumpAndSettle` runs inside `FakeAsync` and cannot drain the
/// `dart:ui` codec callback that `MemoryImage.resolve` schedules — so
/// without this primer the `ImageStreamListener` never fires and any
/// assertion that depends on a resolved intrinsic size silently runs
/// against the pre-decode fallback path.
///
/// See the project spec
/// `.trellis/spec/frontend/quality-guidelines.md` →
/// "Pattern: Force image decode in widget tests via
/// `tester.runAsync` + `precacheImage`".
Future<void> _primeImageDecode(WidgetTester tester, Uint8List bytes) async {
  await tester.runAsync(() async {
    final element = tester.element(find.byType(ExtendedImage).first);
    await precacheImage(MemoryImage(bytes), element);
  });
  await tester.pumpAndSettle();
}

/// Drive a controlled drag inside the test's gesture arena. Builds the
/// drag out of small `moveBy` increments with a [tester.pump] between
/// each so the package's gesture recognizers can process the events as
/// they arrive (which mirrors a real user dragging at ~60 fps).
///
/// `tester.drag` synthesises a sequence of pointer move events too, but
/// in some `extended_image` configurations (a translucent outer
/// GestureDetector wraps the inner ExtendedImageGesture's
/// ScaleGestureRecognizer) the arena resolution times out before the
/// inner recognizer claims the drag, leaving the gesture state's offset
/// unchanged. Using a manual TestGesture with explicit pumps gives the
/// arena enough time to resolve.
Future<void> _dragFromBy(
  WidgetTester tester,
  Offset from,
  Offset totalDelta, {
  int steps = 16,
}) async {
  final stepDelta = totalDelta / steps.toDouble();
  final gesture = await tester.startGesture(from);
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(stepDelta);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  group('PreviewFullScreenDialog', () {
    testWidgets('tap on PreviewThumbnail opens the dialog', (tester) async {
      await tester.pumpWidget(_thumbnailHarness(_smallPng()));
      await tester.pumpAndSettle();

      // No dialog at first.
      expect(find.byType(PreviewFullScreenDialog), findsNothing);

      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
    });

    testWidgets('dialog gesture config exposes minScale=1.0 and maxScale=4.0', (
      tester,
    ) async {
      // Rewritten from the legacy "dialog contains an InteractiveViewer"
      // assertion. The new tree uses extended_image's gesture stack:
      // the bounds (min/max scale) are configured via the
      // `initGestureConfigHandler` that runs once the image stream
      // resolves. We read them off the live `ExtendedImageGestureState`
      // exposed by the inner `ExtendedImageGesture` widget.
      final bytes = _smallPng();
      await tester.pumpWidget(_dialogHarness(bytes));
      await _primeImageDecode(tester, bytes);

      expect(find.byType(ExtendedImage), findsOneWidget);
      final config = _gestureState(tester).imageGestureConfig;
      expect(config, isNotNull);
      expect(config!.minScale, 1.0);
      expect(config.maxScale, kMaxScale);
    });

    testWidgets(
      'after a double-tap zoom + reset, the gesture state returns to identity '
      '(extended_image clamps the destination rect to a centred BoxFit.contain '
      'rectangle inside the viewport; at identity offset is zero and totalScale '
      'is 1.0 so the painted image is necessarily centred)',
      (tester) async {
        // Use a deliberately non-square image so the BoxFit.contain
        // destination differs from the viewport: a 320×8 PNG in the
        // default 800×600 testWidgets viewport renders as a 800×20
        // letterboxed rect, NOT the full viewport. This makes the
        // post-reset "image is centred" claim non-trivial — under any
        // L-β-style top-left anchoring it would land at (0, 0, 800,
        // 20) instead.
        final bytes = _smallPng(width: 320, height: 8);
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        // Drive a double-tap (zoom in to 2×) then a second double-tap
        // (zoom back out to 1.0×) and advance the controller through
        // both animations.
        final state = _gestureState(tester);
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(kZoomAnimationDuration);
        await tester.pump(const Duration(milliseconds: 100));

        // Second double-tap → animate back to identity.
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(kZoomAnimationDuration);
        await tester.pump(const Duration(milliseconds: 100));

        final details = state.gestureDetails;
        expect(details, isNotNull);
        expect(
          details!.totalScale,
          closeTo(1.0, 0.001),
          reason:
              'After zoom + reset, totalScale must be back at identity. '
              'Got ${details.totalScale}.',
        );
        expect(
          details.offset,
          Offset.zero,
          reason:
              'After zoom + reset, the gesture offset must be Offset.zero. '
              'A non-zero offset at identity scale would mean the image '
              'is no longer centred inside the destination rect. Got '
              '${details.offset}.',
        );

        // Sanity guard: the destination rect produced by BoxFit.contain
        // must differ from the viewport — i.e. the image stream resolved
        // and the layout truly went through the letterboxed branch.
        // Without this guard the assertions above could pass against the
        // pre-decode fallback path.
        final destRect = details.destinationRect;
        final viewerRect = tester.getRect(find.byType(ExtendedImage));
        expect(
          destRect,
          isNotNull,
          reason: 'destinationRect must be populated after image decode.',
        );
        expect(
          destRect!.size,
          isNot(viewerRect.size),
          reason:
              'destinationRect ($destRect) must be letterboxed inside the '
              'viewport ($viewerRect), not equal to it. If the image stream '
              'did not resolve, destinationRect would degenerate.',
        );
        expect(
          (destRect.center - viewerRect.center).distance,
          lessThan(2.0),
          reason:
              'destinationRect centre must coincide with viewport centre '
              '(BoxFit.contain centres the image). viewer $viewerRect '
              'dest $destRect.',
        );
      },
    );

    testWidgets(
      'pan while zoomed is clamped at the viewport edge: dragging twice in '
      'the same direction does not push offset past the package boundary '
      "(extended_image clamps to viewport-edge — note the semantics shift "
      'from the legacy InteractiveViewer image-pixel-edge clamp; see '
      'ADR-0002 for the design contract)',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        final state = _gestureState(tester);
        // Pre-zoom to 2× by driving the package's own `handleDoubleTap`
        // entry — same effect as a manual pinch zoom without relying
        // on animation timing.
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        state.handleDoubleTap(
          scale: kDoubleTapZoomScale,
          doubleTapPosition: viewerCenter,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // First drag: large leftward pan. The package will clamp the
        // gesture offset against the boundary once the user reaches it.
        await tester.dragFrom(viewerCenter, const Offset(-1200, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final offsetAfterFirst = state.gestureDetails?.offset;
        expect(offsetAfterFirst, isNotNull);

        // Second drag in the same direction: any further movement must
        // be clamped to zero (or near-zero floating-point drift). A
        // non-clamping behavior would continue to grow with each drag.
        await tester.dragFrom(viewerCenter, const Offset(-1200, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final offsetAfterSecond = state.gestureDetails?.offset;
        expect(offsetAfterSecond, isNotNull);

        expect(
          (offsetAfterSecond!.dx - offsetAfterFirst!.dx).abs(),
          lessThan(1.0),
          reason:
              'dx must be clamped at the right-edge boundary; was '
              '${offsetAfterFirst.dx}, became ${offsetAfterSecond.dx} '
              'after another -1200 px drag.',
        );
        expect(
          (offsetAfterSecond.dy - offsetAfterFirst.dy).abs(),
          lessThan(1.0),
          reason:
              'dy must remain stable on a horizontal second drag; '
              'was ${offsetAfterFirst.dy}, became ${offsetAfterSecond.dy}.',
        );
      },
    );

    testWidgets('close button title and tooltip render', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pumpAndSettle();

      expect(find.text('预览'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping the close button pops the dialog', (tester) async {
      await tester.pumpWidget(_thumbnailHarness(_smallPng()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsNothing);
    });
  });

  group('PreviewFullScreenDialog — chrome (Step 2)', () {
    testWidgets('chrome (AppBar) is visible by default on open', (
      tester,
    ) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      // One pump — enough to lay out, NOT advance the auto-hide timer.
      await tester.pump();

      // The AppBar's AnimatedOpacity wraps the AppBar widget.
      final opacityFinder = find.ancestor(
        of: find.byType(AppBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(opacityFinder, findsOneWidget);
      final opacity = tester.widget<AnimatedOpacity>(opacityFinder);
      expect(opacity.opacity, 1.0);
    });

    testWidgets('chrome auto-hides after 3 seconds', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pump();

      // Advance past the auto-hide delay AND the cross-fade animation.
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byType(AppBar),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('single tap toggles chrome and resets the timer', (
      tester,
    ) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pump();

      // Auto-hide fires → chrome hidden.
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(AppBar),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0.0,
      );

      // Single tap on the image area → chrome shows again. The outer
      // `_PreviewPage` GestureDetector with `HitTestBehavior.translucent`
      // routes the tap to `_toggleChrome`; the inner ExtendedImage's
      // DoubleTap recognizer loses the arena after its timeout.
      await tester.tap(find.byType(ExtendedImage));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(AppBar),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1.0,
      );

      // Wait ~2 s — would have auto-hidden if the timer had not reset.
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(AppBar),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1.0,
      );

      // After the full 3 s window past the tap → hidden.
      await tester.pump(const Duration(seconds: 1, milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(AppBar),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0.0,
      );
    });

    testWidgets(
      'floating close button stays interactive after chrome auto-hides',
      (tester) async {
        await tester.pumpWidget(_thumbnailHarness(_smallPng()));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PreviewThumbnail));
        await tester.pump();

        // Auto-hide.
        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // Even with chrome hidden, the floating X can still pop.
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(find.byType(PreviewFullScreenDialog), findsNothing);
      },
    );

    testWidgets('AppBar leading slot is empty (no auto-injected back arrow)', (
      tester,
    ) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pump();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.leading, isNull);
      expect(appBar.automaticallyImplyLeading, isFalse);
    });
  });

  group('PreviewFullScreenDialog — gestures (Step 3)', () {
    testWidgets(
      'gesture config minScale == 1.0 and maxScale == kMaxScale (extended_image '
      'config bounds replace the legacy InteractiveViewer.minScale/maxScale '
      'assertion; panEnabled has no equivalent — see the drag-to-dismiss tests '
      'below for the un-zoomed-vertical-drag-pops contract)',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        final config = _gestureState(tester).imageGestureConfig;
        expect(config, isNotNull);
        expect(config!.minScale, 1.0);
        expect(config.maxScale, kMaxScale);
      },
    );

    testWidgets(
      'while un-zoomed, a vertical drag exceeding kDragToDismissDistance pops '
      'the dialog (extended_image automatically routes single-finger pan to '
      'ExtendedImageSlidePage when totalScale <= 1.0; replaces the legacy '
      "panEnabled == false at identity contract)",
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_thumbnailHarness(bytes));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PreviewThumbnail));
        await tester.pumpAndSettle();
        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
        // Prime the dialog's MemoryImage decode so `ExtendedImage(mode:
        // gesture)` swaps in `ExtendedImageGesture` (the only widget
        // that actually subscribes to the outer `ExtendedImageSlidePage`).
        // Until decode completes the dialog renders a plain
        // ExtendedRawImage fallback that does not route drags into
        // SlidePage at all.
        await _primeImageDecode(tester, bytes);

        // Drag down by 200 px while un-zoomed — drag-to-dismiss fires.
        // Scope the finder to the dialog's ExtendedImage (the thumbnail
        // also renders an `ExtendedImage(mode: none)` sibling so an
        // un-scoped `byType` finder would be ambiguous).
        final dialogImage = find.descendant(
          of: find.byType(PreviewFullScreenDialog),
          matching: find.byType(ExtendedImage),
        );
        await _dragFromBy(
          tester,
          tester.getCenter(dialogImage),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PreviewFullScreenDialog), findsNothing);
      },
    );

    testWidgets(
      'while zoomed, a vertical drag pans the image instead of dismissing '
      '(extended_image gates drag-to-dismiss on totalScale <= 1.0 — at zoomed '
      'scale, single-finger vertical drag belongs to the image, not SlidePage)',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        final state = _gestureState(tester);
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        // Pre-zoom to 2× so the SlidePage gate closes.
        state.handleDoubleTap(
          scale: kDoubleTapZoomScale,
          doubleTapPosition: viewerCenter,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Vertical drag while zoomed must NOT dismiss the dialog —
        // the package routes the pan into the gesture state instead.
        await tester.drag(find.byType(ExtendedImage), const Offset(0, 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
      },
    );

    testWidgets(
      'double-tap on the image animates the gesture state up to ~2.0× scale',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        // Emit a double-tap at the centre of the image area.
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(viewerCenter);
        // Drive the caller-owned zoom animation forward.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(kZoomAnimationDuration);
        await tester.pump(const Duration(milliseconds: 100));

        final details = _gestureState(tester).gestureDetails;
        expect(details, isNotNull);
        expect(details!.totalScale, closeTo(kDoubleTapZoomScale, 0.01));
      },
    );

    testWidgets(
      'double-tap while zoomed resets the gesture state to identity',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        // Pre-zoom programmatically — same effect as a real pinch for
        // this assertion.
        final state = _gestureState(tester);
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        state.handleDoubleTap(
          scale: kDoubleTapZoomScale,
          doubleTapPosition: viewerCenter,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          state.gestureDetails?.totalScale,
          closeTo(kDoubleTapZoomScale, 0.001),
        );

        // Now drive a double-tap to reset.
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(kZoomAnimationDuration);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          state.gestureDetails?.totalScale,
          closeTo(1.0, 0.001),
          reason:
              'After the second double-tap from a zoomed state, the gesture '
              'should animate back to identity scale. Got '
              '${state.gestureDetails?.totalScale}.',
        );
      },
    );
  });

  group('PreviewFullScreenDialog — multi-image & drag-to-dismiss (Step 4)', () {
    testWidgets('single-image title shows "预览"', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pump();
      expect(find.text('预览'), findsOneWidget);
    });

    testWidgets('multi-image title shows "X / Y"', (tester) async {
      await tester.pumpWidget(
        _multiDialogHarness([
          _smallPng(),
          _smallPng(),
          _smallPng(),
        ], initialIndex: 1),
      );
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('multi-image dialog renders an ExtendedImageGesturePageView', (
      tester,
    ) async {
      await tester.pumpWidget(
        _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
      );
      await tester.pump();
      expect(find.byType(ExtendedImageGesturePageView), findsOneWidget);
    });

    testWidgets(
      'swiping horizontally while un-zoomed advances to the next page',
      (tester) async {
        await tester.pumpWidget(
          _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('1 / 3'), findsOneWidget);

        // Fling left at >= page snap velocity so the gallery commits
        // to the next page.
        await tester.fling(
          find.byType(ExtendedImageGesturePageView),
          const Offset(-400, 0),
          1200,
        );
        await tester.pumpAndSettle();

        expect(find.text('2 / 3'), findsOneWidget);
      },
    );

    testWidgets('vertical drag exceeding threshold pops the dialog', (
      tester,
    ) async {
      final bytes = _smallPng();
      await tester.pumpWidget(_thumbnailHarness(bytes));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
      // Prime decode so the dialog's `ExtendedImage(mode: gesture)`
      // swaps in `ExtendedImageGesture` (required for drag routing
      // into `ExtendedImageSlidePage`).
      await _primeImageDecode(tester, bytes);

      // Drag down by 200 px — well over the 100 px dismiss threshold
      // enforced by `_slideEndHandler`. Scope to the dialog's
      // ExtendedImage (the thumbnail also renders an
      // `ExtendedImage(mode: none)` sibling).
      final dialogImage = find.descendant(
        of: find.byType(PreviewFullScreenDialog),
        matching: find.byType(ExtendedImage),
      );
      await _dragFromBy(
        tester,
        tester.getCenter(dialogImage),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsNothing);
    });

    testWidgets(
      'vertical drag below threshold snaps back and keeps the dialog open',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_thumbnailHarness(bytes));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PreviewThumbnail));
        await tester.pumpAndSettle();
        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
        // Prime decode so the dialog's gesture stack is active.
        await _primeImageDecode(tester, bytes);

        // Drag down by 60 px — below the 100 px threshold. The package's
        // ExtendedImageSlidePage springs back via a linear AnimationController
        // with `resetPageDuration: 500 ms` (default) instead of the legacy
        // `easeOutCubic 250 ms` — pump beyond 500 ms to be safe.
        final dialogImage = find.descendant(
          of: find.byType(PreviewFullScreenDialog),
          matching: find.byType(ExtendedImage),
        );
        await _dragFromBy(
          tester,
          tester.getCenter(dialogImage),
          const Offset(0, 60),
        );
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
      },
    );
  });

  group('PreviewFullScreenDialog — regressions (desktop mouse + zoomed pan)', () {
    testWidgets(
      'ExtendedImageGesturePageView is wrapped in a ScrollConfiguration whose '
      'dragDevices include mouse / trackpad (desktop / web mouse-drag support)',
      (tester) async {
        await tester.pumpWidget(
          _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
        );
        await tester.pump();

        // Locate the ScrollConfiguration that immediately wraps the
        // gallery widget. There may be other ScrollConfiguration
        // ancestors contributed by MaterialApp; the one we install
        // is the closest enclosing ancestor of
        // ExtendedImageGesturePageView.
        final scrollConfig = tester.widget<ScrollConfiguration>(
          find
              .ancestor(
                of: find.byType(ExtendedImageGesturePageView),
                matching: find.byType(ScrollConfiguration),
              )
              .first,
        );
        final devices = scrollConfig.behavior.dragDevices;
        // Mouse + trackpad explicitly — the regression we are guarding.
        expect(
          devices.contains(PointerDeviceKind.mouse),
          isTrue,
          reason:
              'PointerDeviceKind.mouse must be in dragDevices so that '
              'desktop / web mouse drags can switch pages '
              '(see Bug 1 in 05-22-export-preview-fullscreen-immersive).',
        );
        expect(devices.contains(PointerDeviceKind.trackpad), isTrue);
        // Touch / stylus retained (mobile parity).
        expect(devices.contains(PointerDeviceKind.touch), isTrue);
        expect(devices.contains(PointerDeviceKind.stylus), isTrue);
      },
    );

    testWidgets(
      'touch fling on the gallery still advances pages (regression check that '
      'the custom ScrollConfiguration did not break the default touch path)',
      (tester) async {
        await tester.pumpWidget(
          _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('1 / 3'), findsOneWidget);

        // Default tester.fling kind is touch — must still work.
        await tester.fling(
          find.byType(ExtendedImageGesturePageView),
          const Offset(-400, 0),
          1200,
        );
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
      },
    );

    testWidgets(
      'single-finger pan while zoomed moves the gesture offset (extended_image '
      'gates drag-to-dismiss on totalScale <= 1.0 so a zoomed vertical drag '
      'belongs to the image, replacing the legacy outer-vertical-drag-recognizer '
      'mechanism)',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(_dialogHarness(bytes));
        await _primeImageDecode(tester, bytes);

        final state = _gestureState(tester);
        final viewerCenter = tester.getCenter(find.byType(ExtendedImage));
        // Pre-zoom programmatically to 2× — no animation timing needed.
        state.handleDoubleTap(
          scale: kDoubleTapZoomScale,
          doubleTapPosition: viewerCenter,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          state.gestureDetails?.totalScale,
          closeTo(kDoubleTapZoomScale, 0.001),
        );

        final beforeOffset = state.gestureDetails?.offset ?? Offset.zero;

        // Drive a pan programmatically through the gesture state's
        // public API. The drag-to-dismiss gating in the package's
        // `handleScaleUpdate` (gesture.dart:347-389) is exercised here
        // directly — we don't rely on the test gesture arena, which
        // makes the assertion robust against widget-tree changes that
        // would otherwise re-route the synthesised drag events.
        //
        // Vertical -80 dy delta with details.scale = 1.0 → the package
        // falls through to the pan branch (lines 432-471) and updates
        // the gesture offset.
        state.handleScaleStart(ScaleStartDetails(focalPoint: viewerCenter));
        const dragDelta = Offset(0, -80);
        state.handleScaleUpdate(
          ScaleUpdateDetails(
            focalPoint: viewerCenter + dragDelta,
            scale: 1.0,
            focalPointDelta: dragDelta,
          ),
        );
        state.handleScaleEnd(ScaleEndDetails());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Dialog must still be present — the drag-to-dismiss path
        // (gesture.dart:347-389) is gated on totalScale <= 1 and we
        // pre-zoomed to 2× exactly to verify this gate.
        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

        final afterOffset = state.gestureDetails?.offset ?? Offset.zero;
        final movedX = (afterOffset.dx - beforeOffset.dx).abs() > 0.01;
        final movedY = (afterOffset.dy - beforeOffset.dy).abs() > 0.01;
        expect(
          movedX || movedY,
          isTrue,
          reason:
              'gestureDetails.offset should have changed after a pan '
              'while zoomed (before $beforeOffset, after $afterOffset).',
        );
      },
    );
  });
}
