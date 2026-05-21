import 'dart:typed_data';

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

    testWidgets('dialog contains an InteractiveViewer', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.minScale, 1.0);
      expect(iv.maxScale, 4.0);
    });

    testWidgets(
      'InteractiveViewer.boundaryMargin is infinite so pan is unlimited '
      'after zoom-in',
      (tester) async {
        await tester.pumpWidget(_dialogHarness(_smallPng()));
        await tester.pumpAndSettle();

        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(iv.boundaryMargin, const EdgeInsets.all(double.infinity));
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

      // Single tap on the image area → chrome shows again.
      await tester.tap(find.byType(InteractiveViewer));
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
    testWidgets('InteractiveViewer.minScale == 1.0 and panEnabled == false '
        'at identity', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      // Two pumps so the image stream listener can fire (intrinsic
      // size resolution) but not enough to trigger the auto-hide.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.minScale, 1.0);
      expect(iv.maxScale, 4.0);
      // panEnabled defaults to `false` while un-zoomed so the outer
      // PageView (Step 4) is free to claim horizontal drag.
      expect(iv.panEnabled, isFalse);
    });

    testWidgets(
      'double-tap on the image animates the controller up to ~2.0× scale',
      (tester) async {
        await tester.pumpWidget(_dialogHarness(_smallPng(width: 8, height: 8)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Locate the gesture detector that wraps the image and emit a
        // double-tap right at the centre.
        final viewerCenter = tester.getCenter(find.byType(InteractiveViewer));
        await tester.tapAt(viewerCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(viewerCenter);
        // Drive the zoom animation forward.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 300));

        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final scale = iv.transformationController!.value.getMaxScaleOnAxis();
        expect(scale, closeTo(2.0, 0.01));
        // After zoom, panEnabled should have flipped to true.
        expect(iv.panEnabled, isTrue);
      },
    );

    testWidgets('double-tap while zoomed resets the matrix to identity', (
      tester,
    ) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      // Pre-zoom by writing the matrix directly — same effect as
      // a manual pinch zoom for this assertion.
      iv.transformationController!.value = Matrix4.identity()
        ..scaleByDouble(2.0, 2.0, 1, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final viewerCenter = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(viewerCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));

      final matrix = iv.transformationController!.value;
      expect(matrix.getMaxScaleOnAxis(), closeTo(1.0, 0.001));
    });

    testWidgets('double-tap focal falls back to image centre when tap lands in '
        'letterbox', (tester) async {
      // A very wide image inside a normal viewport → tall letterbox
      // bands on the top and bottom.
      await tester.pumpWidget(_dialogHarness(_smallPng(width: 320, height: 8)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap in the lower letterbox so the AppBar (top of screen)
      // does not intercept the gesture. Default test viewport is
      // 800×600, image is rendered ~20 dp tall centred vertically,
      // so y ≈ 560 is solidly inside the bottom letterbox.
      final viewerRect = tester.getRect(find.byType(InteractiveViewer));
      final letterboxTap = Offset(
        viewerRect.left + viewerRect.width / 2,
        viewerRect.bottom - 40,
      );
      await tester.tapAt(letterboxTap);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(letterboxTap);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));

      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final scale = iv.transformationController!.value.getMaxScaleOnAxis();
      expect(scale, closeTo(2.0, 0.01));

      // Anchor was clamped to the image centre, so the translation
      // expresses (cx * (1 - scale)) where cx is the viewer's
      // horizontal centre.
      final translationX = iv.transformationController!.value.row0[3];
      final expectedTx = viewerRect.width / 2 * (1 - 2.0);
      expect(translationX, closeTo(expectedTx, 1.0));
    });
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

    testWidgets('multi-image dialog renders a PageView', (tester) async {
      await tester.pumpWidget(
        _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
      );
      await tester.pump();
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('PageView uses immersive physics that is a PageScrollPhysics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
      );
      await tester.pump();
      final pv = tester.widget<PageView>(find.byType(PageView));
      // Custom physics extends PageScrollPhysics.
      expect(pv.physics, isA<PageScrollPhysics>());
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

        // Fling left at >= PageView snap velocity so it commits to
        // the next page.
        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
        await tester.pumpAndSettle();

        expect(find.text('2 / 3'), findsOneWidget);
      },
    );

    testWidgets('vertical drag exceeding threshold pops the dialog', (
      tester,
    ) async {
      await tester.pumpWidget(_thumbnailHarness(_smallPng()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

      // Drag down by 200 px — well over the 100 px dismiss threshold.
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsNothing);
    });

    testWidgets(
      'vertical drag below threshold snaps back and keeps the dialog open',
      (tester) async {
        await tester.pumpWidget(_thumbnailHarness(_smallPng()));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PreviewThumbnail));
        await tester.pumpAndSettle();
        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

        // Drag down by 60 px — below the 100 px threshold.
        await tester.drag(find.byType(InteractiveViewer), const Offset(0, 60));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
      },
    );
  });

  group(
    'PreviewFullScreenDialog — regressions (desktop mouse + zoomed pan)',
    () {
      testWidgets(
        'PageView is wrapped in a ScrollConfiguration whose dragDevices include '
        'mouse / trackpad (desktop / web mouse-drag support)',
        (tester) async {
          await tester.pumpWidget(
            _multiDialogHarness([_smallPng(), _smallPng(), _smallPng()]),
          );
          await tester.pump();

          // Locate the ScrollConfiguration that immediately wraps the
          // PageView. There may be other ScrollConfiguration ancestors
          // contributed by MaterialApp; the one we install is the
          // closest enclosing ancestor of PageView.
          final scrollConfig = tester.widget<ScrollConfiguration>(
            find
                .ancestor(
                  of: find.byType(PageView),
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
                'desktop / web mouse drags can switch PageView pages '
                '(see Bug 1 in 05-22-export-preview-fullscreen-immersive).',
          );
          expect(devices.contains(PointerDeviceKind.trackpad), isTrue);
          // Touch / stylus retained (mobile parity).
          expect(devices.contains(PointerDeviceKind.touch), isTrue);
          expect(devices.contains(PointerDeviceKind.stylus), isTrue);
        },
      );

      testWidgets(
        'touch fling on PageView still advances pages (regression check that '
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
            find.byType(PageView),
            const Offset(-400, 0),
            1200,
          );
          await tester.pumpAndSettle();
          expect(find.text('2 / 3'), findsOneWidget);
        },
      );

      testWidgets('single-finger pan after double-tap zoom moves the matrix '
          '(outer vertical-drag recognizer is not in the arena while zoomed)', (
        tester,
      ) async {
        await tester.pumpWidget(_dialogHarness(_smallPng()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        // Pre-zoom the matrix via the controller (avoids relying on
        // the double-tap animation timing for this regression).
        iv.transformationController!.value = Matrix4.identity()
          ..scaleByDouble(2.0, 2.0, 1, 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        // Sanity: scale really is 2.0×.
        expect(
          iv.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(2.0, 0.001),
        );

        // Capture translation prior to drag.
        final beforeTx = iv.transformationController!.value.row0[3];
        final beforeTy = iv.transformationController!.value.row1[3];

        // Vertical drag while zoomed must reach InteractiveViewer's
        // ScaleGestureRecognizer (single-finger pan), NOT the outer
        // VerticalDragGestureRecognizer. If the outer recognizer were
        // still in the arena, the dialog would either pop or snap
        // back the body translation instead — and the IV translation
        // would not change.
        final center = tester.getCenter(find.byType(InteractiveViewer));
        await tester.dragFrom(center, const Offset(0, -80));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Dialog must still be present (drag-to-dismiss did NOT fire).
        expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

        final afterTx = iv.transformationController!.value.row0[3];
        final afterTy = iv.transformationController!.value.row1[3];
        // The translation must have moved on at least one axis — IV
        // pan is active. We don't care about the exact direction
        // (boundary clamps can swallow part of the delta) — just that
        // something moved.
        final movedX = (afterTx - beforeTx).abs() > 0.01;
        final movedY = (afterTy - beforeTy).abs() > 0.01;
        expect(
          movedX || movedY,
          isTrue,
          reason:
              'InteractiveViewer matrix translation should have changed '
              'after a single-finger pan while zoomed (tx '
              '$beforeTx → $afterTx, ty $beforeTy → $afterTy).',
        );
      });
    },
  );
}
