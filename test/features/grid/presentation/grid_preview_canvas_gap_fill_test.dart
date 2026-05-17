import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 600×600 square source so the cropped square equals the original
/// (avoiding any sourceOffset / sourceScale clamping surprises).
Uint8List _squareBytes() {
  final canvas = img.Image(width: 600, height: 600, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(200, 100, 50, 255));
  return Uint8List.fromList(img.encodePng(canvas));
}

ImportedImage _squareSource() => ImportedImage(
  bytes: _squareBytes(),
  width: 600,
  height: 600,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 17),
);

Widget _wrap({required Widget child, required ImportedImage initialSource}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => [initialSource]),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 320, height: 320, child: child)),
    ),
  );
}

/// Locates the grid-overlay [CustomPaint] (the painter whose
/// `runtimeType` matches `_GridOverlayPainter`). There are multiple
/// `CustomPaint`s in the widget tree (Material decoration uses them
/// too) — we narrow by painter type name so this test is robust to
/// chrome refactors.
Finder _gridOverlayFinder() => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      (w.painter?.runtimeType.toString() ?? '').contains('GridOverlayPainter'),
);

void main() {
  group('GridPreviewCanvas — gap fill painter', () {
    testWidgets(
      'spacing == 0: painter does NOT saveLayer (gap fill path is gated)',
      (tester) async {
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _wrap(
            initialSource: _squareSource(),
            child: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                return const GridPreviewCanvas();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Default spacing is 0 in GridEditorState.initial().
        expect(capturedRef.read(gridEditorControllerProvider).spacing, 0);

        final renderObject = tester.renderObject(_gridOverlayFinder().first);

        // When spacing == 0 the gap-fill path is gated out: the
        // painter never calls `saveLayer`. Asserting "no saveLayer
        // appears anywhere in the paint sequence" proves the gap
        // fill never ran. (`PaintPattern.something` matches the
        // first paint step against the predicate; with `isNot`, the
        // expectation is that no first-step saveLayer ever appears
        // — and because every gap fill in this painter starts with
        // saveLayer, no saveLayer anywhere = no gap fill anywhere.)
        expect(
          renderObject,
          isNot(paints..something((method, args) => method == #saveLayer)),
        );
      },
    );

    testWidgets('spacing > 0: painter fills viewport with surfaceContainer', (
      tester,
    ) async {
      late WidgetRef capturedRef;
      late ColorScheme capturedScheme;
      await tester.pumpWidget(
        _wrap(
          initialSource: _squareSource(),
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              capturedScheme = Theme.of(ctx).colorScheme;
              return const GridPreviewCanvas();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch spacing to a positive value and let the canvas
      // rebuild.
      capturedRef.read(gridEditorControllerProvider.notifier).setSpacing(30);
      await tester.pumpAndSettle();

      final renderObject = tester.renderObject(_gridOverlayFinder().first);

      // Assert: the painter's first two ops form the gap-fill prefix
      // — `saveLayer` (consumed via `something`, since PaintPattern
      // has no dedicated saveLayer matcher) immediately followed by
      // `drawRect` painted in surfaceContainer. We don't assert
      // exact cell-clear coordinates here (cell-rect math has its
      // own test in grid_layout_test.dart).
      expect(
        renderObject,
        paints
          ..something((method, args) => method == #saveLayer)
          ..rect(color: capturedScheme.surfaceContainer),
      );
    });

    testWidgets(
      'spacing > 0: gap color follows theme (dark mode swaps the fill)',
      (tester) async {
        late WidgetRef capturedRef;
        late ColorScheme capturedScheme;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              importedImagesProvider(
                ImageImportSessionKind.grid,
              ).overrideWith((_) => [_squareSource()]),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: Brightness.dark),
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  height: 320,
                  child: Consumer(
                    builder: (ctx, ref, _) {
                      capturedRef = ref;
                      capturedScheme = Theme.of(ctx).colorScheme;
                      return const GridPreviewCanvas();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        capturedRef.read(gridEditorControllerProvider.notifier).setSpacing(20);
        await tester.pumpAndSettle();

        final renderObject = tester.renderObject(_gridOverlayFinder().first);

        // Dark-mode surfaceContainer is a distinct color from the
        // light token — asserting on the live captured value keeps
        // the test self-contained without hard-coding hex.
        expect(
          renderObject,
          paints
            ..something((method, args) => method == #saveLayer)
            ..rect(color: capturedScheme.surfaceContainer),
        );
      },
    );
  });
}
