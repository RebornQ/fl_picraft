import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/usecases/compute_center_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/center_cell_overlay.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 400×400 square source — keeps grid cells square in either mode so
/// the gesture isolation test stays focused on hit-testing, not on the
/// underlying crop math.
Uint8List _squareBytes() {
  final canvas = img.Image(width: 400, height: 400, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(60, 60, 120, 255));
  return Uint8List.fromList(img.encodePng(canvas));
}

ImportedImage _squareSource() => ImportedImage(
  bytes: _squareBytes(),
  width: 400,
  height: 400,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 17),
);

ImportedImage _centerImage() {
  final canvas = img.Image(width: 200, height: 200, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(220, 220, 220, 255));
  return ImportedImage(
    bytes: Uint8List.fromList(img.encodePng(canvas)),
    width: 200,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 17),
  );
}

Widget _wrap({required Widget child, required ImportedImage source}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => [source]),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, height: 300, child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'social mode 3×3: drag within the center cell drives CenterCellOverlay, '
    'not the canvas drag',
    (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _wrap(
          source: _squareSource(),
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const GridPreviewCanvas();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable social mode, install a center image, and bump the
      // center-image scale above 1 so the offset has room to move
      // (cover-fit at scale=1 leaves zero pan surplus on a square
      // image — see `clampCenterOffset` in compute_center_transform).
      // Also bump the canvas crop scale > 1 so the source-level offset
      // also has legal room to move — this is what lets us distinguish
      // "the inner gesture fired exclusively" from "the outer clamp
      // ate the delta".
      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_centerImage());
      notifier.setCenterScale(1.8);
      notifier.setSourceScale(2.0);
      await tester.pumpAndSettle();

      final initialState = capturedRef.read(gridEditorControllerProvider);
      expect(initialState.nineGridSocialMode, true);
      expect(initialState.centerImage, isNotNull);
      final initialSourceOffset = initialState.sourceOffset;
      expect(initialState.centerOffset, kCenterOffsetZero);

      // The CenterCellOverlay widget is mounted as a Positioned child
      // of the canvas Stack when social mode + a center image are
      // both present. Drag directly on that widget's rect — its
      // `HitTestBehavior.opaque` recognizer must claim the gesture
      // over the outer canvas detector.
      final overlayFinder = find.byType(CenterCellOverlay);
      expect(overlayFinder, findsOneWidget);
      await tester.timedDrag(
        overlayFinder,
        const Offset(40, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      final after = capturedRef.read(gridEditorControllerProvider);
      // Center cell overlay's offset should change (the gesture
      // reached CenterCellOverlay), but the canvas-level sourceOffset
      // stays unchanged because the center cell's
      // `HitTestBehavior.opaque` recognizer wins inside its bounds.
      expect(
        after.centerOffset,
        isNot(equals(kCenterOffsetZero)),
        reason:
            'gesture inside center cell should drive CenterCellOverlay '
            '(R-DRAG-05)',
      );
      expect(
        after.sourceOffset,
        initialSourceOffset,
        reason: 'background canvas drag must not fire inside center cell',
      );
    },
  );

  testWidgets(
    'non-social mode: drag inside the canvas drives the source-crop offset '
    'as usual (no CenterCellOverlay mounted)',
    (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _wrap(
          source: _squareSource(),
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const GridPreviewCanvas();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: no center overlay should be present without social
      // mode + center image.
      final initial = capturedRef.read(gridEditorControllerProvider);
      expect(initial.nineGridSocialMode, false);

      // On a square source at scale=1 the legal offset is exactly the
      // center, so drag should be a no-op — exercising the clamp path
      // ensures the gesture **does** dispatch to the canvas, but the
      // offset stays clamped at default.
      // To prove dispatch happened, override scale to 2.0 first so
      // there is room to move.
      capturedRef
          .read(gridEditorControllerProvider.notifier)
          .setSourceScale(2.0);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(GridPreviewCanvas), const Offset(40, 0));
      await tester.pumpAndSettle();

      final after = capturedRef.read(gridEditorControllerProvider);
      expect(
        after.sourceOffset.dx,
        isNot(equals(initial.sourceOffset.dx)),
        reason: 'canvas drag should mutate sourceOffset in non-social mode',
      );
    },
  );
}
