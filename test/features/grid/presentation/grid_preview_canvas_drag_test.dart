import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/usecases/compute_source_crop.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Builds a non-square (600×300 landscape) source bytes.
Uint8List _landscapeBytes() {
  final canvas = img.Image(width: 600, height: 300, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(80, 120, 200, 255));
  return Uint8List.fromList(img.encodePng(canvas));
}

ImportedImage _landscapeSource() => ImportedImage(
  bytes: _landscapeBytes(),
  width: 600,
  height: 300,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 17),
);

Widget _wrap({required Widget child, required ImportedImage initialSource}) {
  return ProviderScope(
    overrides: [
      // Seed the grid-kind import session so the controller picks the
      // source on first build.
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => [initialSource]),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 320, height: 320, child: child)),
    ),
  );
}

void main() {
  group('GridPreviewCanvas — drag-select gesture', () {
    testWidgets(
      'horizontal drag mutates sourceOffset.dx on a landscape source',
      (tester) async {
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          _wrap(
            initialSource: _landscapeSource(),
            child: Consumer(
              builder: (ctx, ref, _) {
                capturedRef = ref;
                return const GridPreviewCanvas();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: initial state should be the cover-fit default.
        final initial = capturedRef.read(gridEditorControllerProvider);
        expect(initial.hasSource, true);
        expect(initial.sourceOffset, kDefaultSourceOffset);
        expect(initial.sourceScale, kDefaultSourceScale);

        // Drag the canvas to the right — finger pushes image right,
        // crop window moves left, so the offset.dx decreases (clamped
        // at the legal minimum 0.25 for a landscape 2:1 source at
        // scale=1).
        final canvasFinder = find.byType(GridPreviewCanvas);
        await tester.drag(canvasFinder, const Offset(120, 0));
        await tester.pumpAndSettle();

        final after = capturedRef.read(gridEditorControllerProvider);
        expect(
          after.sourceOffset.dx,
          lessThan(initial.sourceOffset.dx),
          reason:
              'finger-rightward drag should pull the crop window leftward '
              '(decreasing dx)',
        );
        // Vertical extent has only one legal y at scale=1 on landscape
        // so dy stays clamped at 0.5.
        expect(after.sourceOffset.dy, closeTo(0.5, 1e-9));
      },
    );

    testWidgets('the controller exposes the new offset via setSourceOffset', (
      tester,
    ) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _wrap(
          initialSource: _landscapeSource(),
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const GridPreviewCanvas();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      // Push the offset all the way to the left edge.
      notifier.setSourceOffset(const SourceOffset(0.0, 0.5));
      await tester.pumpAndSettle();
      final state = capturedRef.read(gridEditorControllerProvider);
      // Clamped at halfX = 0.25 for landscape 2:1 at scale=1.
      expect(state.sourceOffset.dx, closeTo(0.25, 1e-9));
      expect(state.hasNonDefaultCrop, true);
    });

    testWidgets('resetCrop restores defaults and toggles hasNonDefaultCrop', (
      tester,
    ) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _wrap(
          initialSource: _landscapeSource(),
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const GridPreviewCanvas();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setSourceOffset(const SourceOffset(0.0, 0.5));
      notifier.setSourceScale(2.0);
      await tester.pumpAndSettle();
      expect(
        capturedRef.read(gridEditorControllerProvider).hasNonDefaultCrop,
        true,
      );

      notifier.resetCrop();
      await tester.pumpAndSettle();
      final reset = capturedRef.read(gridEditorControllerProvider);
      expect(reset.sourceOffset, kDefaultSourceOffset);
      expect(reset.sourceScale, kDefaultSourceScale);
      expect(reset.hasNonDefaultCrop, false);
    });
  });
}
