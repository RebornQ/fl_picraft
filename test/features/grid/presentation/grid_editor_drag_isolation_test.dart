import 'package:fl_picraft/features/grid/domain/usecases/compute_cell_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

ImportedImage _image({int seed = 0}) {
  return ImportedImage(
    bytes: Uint8List.fromList([seed, seed + 1, seed + 2]),
    width: 100,
    height: 100,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 17, 0, 0, seed),
  );
}

void main() {
  group('CellOverlay drag isolation (R-DRAG-05 generalized)', () {
    test('per-cell setCellScale only mutates the targeted index', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(0, _image(seed: 1));
      notifier.setCellImage(4, _image(seed: 2));
      notifier.setCellImage(8, _image(seed: 3));

      // Manipulate cell 4's scale; cells 0 and 8 must stay at defaults.
      notifier.setCellScale(4, 1.8);
      final state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements[0]?.scale, kDefaultCellScale);
      expect(state.cellReplacements[4]?.scale, 1.8);
      expect(state.cellReplacements[8]?.scale, kDefaultCellScale);
    });

    test('per-cell setCellOffset only mutates the targeted index', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(0, _image(seed: 1));
      notifier.setCellImage(4, _image(seed: 2));

      // Scale-up cell 4 so offset (5, 5) is legal.
      notifier.setCellScale(4, 2.0);
      notifier.setCellOffset(4, const CellOffset(5, 5));
      final state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements[0]?.offset, kCellOffsetZero);
      expect(state.cellReplacements[4]?.offset, const CellOffset(5, 5));
    });

    test('per-cell resetCell does not touch siblings', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      final imageA = _image(seed: 1);
      final imageB = _image(seed: 2);
      notifier.setCellImage(0, imageA);
      notifier.setCellImage(4, imageB);
      notifier.resetCell(0);

      final state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements.containsKey(0), isFalse);
      expect(state.cellReplacements[4]?.image, imageB);
    });
  });
}
