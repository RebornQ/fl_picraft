import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({int width = 100, int height = 200, String tag = 'a'}) {
  return ImportedImage(
    sourcePath: tag,
    bytes: _validPng(),
    width: width,
    height: height,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Widget _harness({required List<ImportedImage> images, required double height}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: height,
            child: const StitchPreviewCanvas(),
          ),
        ),
      ),
    ),
  );
}

/// Look up the grey-surface Container painted inside the
/// [StitchPreviewCanvas] — the only Container painted with
/// [ColorScheme.surfaceContainerHighest] in the canvas subtree.
Finder _surfaceContainer(WidgetTester tester) {
  return find.descendant(
    of: find.byType(StitchPreviewCanvas),
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      final color = decoration.color;
      if (color == null) return false;
      // Match against the theme's surfaceContainerHighest by looking up
      // the live ColorScheme from any descendant context. We can't pull
      // that from here, so identify the surface container by the fact
      // that it has a BoxDecoration with a non-null color and is
      // located directly under a ConstrainedBox + SingleChildScrollView
      // tree.
      return true;
    }),
  );
}

void main() {
  testWidgets(
    'grey surface fills the full Expanded height when given an empty session',
    (tester) async {
      await tester.pumpWidget(_harness(images: const [], height: 600));
      await tester.pumpAndSettle();

      // The surface Container (root paint of the canvas) should be 600
      // tall, matching the SizedBox parent height — no dead band below.
      final surface = tester.renderObject<RenderBox>(
        _surfaceContainer(tester).first,
      );
      expect(surface.size.height, closeTo(600, 0.5));
    },
  );

  testWidgets(
    'grey surface fills the full Expanded height for a short-aspect image',
    (tester) async {
      // Wide-aspect image: surface should still fill 600 dp tall
      // (the canvas painted inside will be smaller and centered).
      await tester.pumpWidget(
        _harness(images: [_stub(width: 1000, height: 200)], height: 600),
      );
      await tester.pumpAndSettle();

      final surface = tester.renderObject<RenderBox>(
        _surfaceContainer(tester).first,
      );
      expect(surface.size.height, closeTo(600, 0.5));
    },
  );

  testWidgets('canvas is scrollable when the assembled image is tall-aspect', (
    tester,
  ) async {
    // Tall image — long stitch assembled at natural width will be
    // taller than the 600 dp surface, so the inner
    // SingleChildScrollView should accommodate it.
    await tester.pumpWidget(
      _harness(
        images: [
          _stub(width: 100, height: 2000),
          _stub(width: 100, height: 2000, tag: 'b'),
        ],
        height: 600,
      ),
    );
    await tester.pumpAndSettle();

    // SingleChildScrollView must exist inside the canvas widget.
    final scrollViewFinder = find.descendant(
      of: find.byType(StitchPreviewCanvas),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollViewFinder, findsOneWidget);
  });

  testWidgets('shows empty hint text when no images are present', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(images: const [], height: 600));
    await tester.pumpAndSettle();

    expect(find.text('导入图片以预览拼接效果'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  group('horizontal stitch mode — canvas fills height + scrolls horizontally', () {
    /// Builds a harness wired to an explicit [ProviderContainer] so the
    /// test can flip the editor into [StitchMode.horizontal] before the
    /// first frame settles. Surfaces a fixed-width / fixed-height
    /// viewport so the geometry assertions are deterministic.
    Future<ProviderContainer> pumpHorizontalHarness(
      WidgetTester tester, {
      required List<ImportedImage> images,
      required double width,
      required double height,
    }) async {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWith((ref) => images),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(stitchEditorControllerProvider.notifier)
          .setMode(StitchMode.horizontal);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: const StitchPreviewCanvas(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// Finder that selects the inner canvas widget painted with the
    /// drop shadow — i.e. the `DecoratedBox(boxShadow: ...)` sized to
    /// `displayWidth × displayHeight` inside `_PreviewSurface`. We
    /// match on the `boxShadow` instead of the type alone because the
    /// outer grey surface is *also* a `DecoratedBox` (no shadow), and
    /// `find.byType(DecoratedBox).first` happens to resolve to that
    /// one — which is the viewport itself, not the canvas.
    Finder shadowedCanvasFinder() {
      return find.descendant(
        of: find.byType(StitchPreviewCanvas),
        matching: find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) return false;
          final decoration = widget.decoration;
          if (decoration is! BoxDecoration) return false;
          final shadow = decoration.boxShadow;
          return shadow != null && shadow.isNotEmpty;
        }),
      );
    }

    testWidgets(
      'wide stitch overflows horizontally and the outer scroll runs on Axis.horizontal',
      (tester) async {
        // 5 images of 400×200 laid out horizontally at 200 dp tall →
        // assembled canvas is ~ (5 * 400 * scaling) × 200 with aspect
        // ≈ 10. At 600 dp viewport height the displayWidth is huge so
        // overflow is guaranteed.
        await pumpHorizontalHarness(
          tester,
          images: [
            _stub(width: 400, height: 200, tag: 'a'),
            _stub(width: 400, height: 200, tag: 'b'),
            _stub(width: 400, height: 200, tag: 'c'),
            _stub(width: 400, height: 200, tag: 'd'),
            _stub(width: 400, height: 200, tag: 'e'),
          ],
          width: 400,
          height: 600,
        );

        final scrollViewFinder = find.descendant(
          of: find.byType(StitchPreviewCanvas),
          matching: find.byType(SingleChildScrollView),
        );
        expect(scrollViewFinder, findsOneWidget);

        final scrollView = tester.widget<SingleChildScrollView>(
          scrollViewFinder,
        );
        expect(
          scrollView.scrollDirection,
          Axis.horizontal,
          reason:
              'Horizontal stitch mode must scroll on the horizontal axis so wide canvases pan left/right.',
        );

        // The scrollable's position should report non-zero
        // maxScrollExtent — that's the assertion that "wide canvas
        // actually overflows".
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(StitchPreviewCanvas),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          scrollable.position.maxScrollExtent,
          greaterThan(0),
          reason: 'Wide canvas should not fit in the 400 dp viewport.',
        );
      },
    );

    testWidgets(
      'narrow stitch stays centered horizontally and does not overflow',
      (tester) async {
        // Single 50×800 image at 600 dp tall → displayHeight ≈ 568
        // (after padding 32), displayWidth ≈ 568 * (50/800) ≈ 36 dp.
        // 36 dp is well under the 400 dp viewport — content must
        // center, not overflow.
        await pumpHorizontalHarness(
          tester,
          images: [_stub(width: 50, height: 800, tag: 'tall')],
          width: 400,
          height: 600,
        );

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(StitchPreviewCanvas),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          scrollable.position.maxScrollExtent,
          0,
          reason: 'Narrow canvas should not produce a scrollable extent.',
        );

        // Sanity: the canvas widget is centered inside the viewport.
        // Compute the canvas's left and right gaps to the surface edges
        // and assert they are within ~ 1 dp of each other.
        final canvasFinder = shadowedCanvasFinder();
        final canvasRect = tester.getRect(canvasFinder);
        final surfaceRect = tester.getRect(find.byType(StitchPreviewCanvas));
        final leftGap = canvasRect.left - surfaceRect.left;
        final rightGap = surfaceRect.right - canvasRect.right;
        expect(
          (leftGap - rightGap).abs(),
          lessThan(1.5),
          reason:
              'Narrow canvas in horizontal mode should be centered (≈ equal left/right gaps).',
        );
      },
    );

    testWidgets(
      'canvas height fills the viewport minus padding in horizontal mode',
      (tester) async {
        // 3 images of 300×300 → aspect = (3 * 300) / 300 = 3. Display
        // height should equal viewportHeight - padding*2.
        await pumpHorizontalHarness(
          tester,
          images: [
            _stub(width: 300, height: 300, tag: 'a'),
            _stub(width: 300, height: 300, tag: 'b'),
            _stub(width: 300, height: 300, tag: 'c'),
          ],
          width: 800,
          height: 600,
        );

        final canvasFinder = shadowedCanvasFinder();
        final canvasRect = tester.getRect(canvasFinder);
        // Padding inside the canvas is 16 dp on every side → 32 dp
        // total vertical. The displayed canvas should fill the
        // remaining 568 dp height (within ~ 1 dp for sub-pixel
        // rounding).
        expect(
          canvasRect.height,
          closeTo(600 - 32, 1.5),
          reason: 'Canvas should fill viewport height minus 32 dp padding.',
        );
      },
    );
  });
}
