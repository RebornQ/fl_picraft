import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/cell_overlay.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({required int w, required int h}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 128, 0, 255));
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _image({required int w, required int h, int seed = 0}) {
  return ImportedImage(
    bytes: _validPng(w: w, h: h),
    width: w,
    height: h,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 18, 0, 0, seed),
  );
}

Widget _harness({required Widget child, double size = 200}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => const []),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: size, height: size, child: child),
      ),
    ),
  );
}

void main() {
  group('Replaced cell drag — clamp uses real cell geometry', () {
    testWidgets(
      'horizontal drag on a 400x200 image at scale=1.0 produces non-zero '
      'offset.dx',
      (tester) async {
        // Regression: before this fix, setCellOffset used the replacement
        // image's own width/height as the cell-shape proxy. For any non-
        // same-aspect image, that collapses maxDx/maxDy to 0 at scale=1.0,
        // pinning the offset to (0, 0) and making the image visually
        // immovable. We assert the opposite — a horizontal drag must
        // actually pan a horizontal image on its long axis.
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _harness(
            child: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                return const CellOverlay(
                  cellIndex: 0,
                  rows: 3,
                  cols: 3,
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                  isGesturing: false,
                );
              },
            ),
          ),
        );

        // Seed cell 0 with a horizontal 400x200 replacement image.
        capturedRef
            .read(gridEditorControllerProvider.notifier)
            .setCellImage(0, _image(w: 400, h: 200, seed: 1));
        await tester.pumpAndSettle();

        // Horizontal drag of widget-px 30. With cell == source (both 200),
        // widget-per-source ratio is 1.0 → source delta == widget delta.
        // coverScale = max(200/400, 200/200) = 1.0; effective scaledW =
        // 400; maxDx (source-px) = (400 - 200) / 2 = 100 → 30 is within
        // bounds and must survive the clamp.
        await tester.drag(find.byType(CellOverlay), const Offset(30, 0));
        await tester.pumpAndSettle();

        final replacement = capturedRef
            .read(gridEditorControllerProvider)
            .cellReplacements[0];
        expect(replacement, isNotNull);
        expect(
          replacement!.offset.dx,
          isNot(0),
          reason:
              'horizontal drag on a non-same-aspect image at scale=1.0 must '
              'produce a non-zero offset.dx — the bug clamped both axes to '
              "zero because the provider used the image's own width as the "
              'cell-shape proxy',
        );
        // Drag was purely horizontal; the vertical axis has zero surplus
        // (image height == cell height at cover-fit) so dy stays clamped.
        expect(replacement.offset.dy, 0);
      },
    );

    testWidgets(
      'diagonal drag after scale=2.0 produces non-zero offset on both axes',
      (tester) async {
        // After the user pinches a same-aspect replacement to scale=2.0,
        // the effective image extent exceeds the cell on both axes, so a
        // diagonal drag must pan both dx and dy. This guards the re-clamp
        // path inside setCellScale + the offset clamp inside setCellOffset.
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _harness(
            child: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                return const CellOverlay(
                  cellIndex: 0,
                  rows: 3,
                  cols: 3,
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                  isGesturing: false,
                );
              },
            ),
          ),
        );

        // Seed cell 0 with a same-aspect 200x200 image, then bump scale to
        // 2.0 (the cover-relative max). At scale=2.0 the image's effective
        // extent is 400x400, leaving 100px of half-surplus on each axis.
        final notifier = capturedRef.read(
          gridEditorControllerProvider.notifier,
        );
        notifier.setCellImage(0, _image(w: 200, h: 200, seed: 2));
        notifier.setCellScale(0, 2.0, cellWidth: 200, cellHeight: 200);
        await tester.pumpAndSettle();

        // Diagonal drag of widget-px (40, 30) → source delta (40, 30),
        // both within maxDx = maxDy = 100.
        await tester.drag(find.byType(CellOverlay), const Offset(40, 30));
        await tester.pumpAndSettle();

        final replacement = capturedRef
            .read(gridEditorControllerProvider)
            .cellReplacements[0];
        expect(replacement, isNotNull);
        expect(replacement!.scale, 2.0);
        expect(
          replacement.offset.dx,
          isNot(0),
          reason: 'horizontal component of diagonal drag should pan dx',
        );
        expect(
          replacement.offset.dy,
          isNot(0),
          reason: 'vertical component of diagonal drag should pan dy',
        );
      },
    );
  });
}
