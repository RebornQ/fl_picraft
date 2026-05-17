import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/entities/cell_replacement.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_editor_state.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/compute_cell_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ImportedImage _img(int seed, {int w = 300, int h = 300}) {
  return ImportedImage(
    bytes: Uint8List.fromList([seed, seed + 1, seed + 2]),
    width: w,
    height: h,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 17, 0, 0, seed),
  );
}

void main() {
  group('CellReplacement value semantics', () {
    test('equality + hashCode follow image/scale/offset', () {
      final image = _img(1);
      final a = CellReplacement(image: image);
      final b = CellReplacement(image: image);
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = CellReplacement(image: image, scale: 1.5);
      expect(a, isNot(c));

      final d = CellReplacement(image: image, offset: const CellOffset(1, 0));
      expect(a, isNot(d));
    });

    test('defaults are cover-fit (scale=1) / zero offset', () {
      final r = CellReplacement(image: _img(1));
      expect(r.scale, kDefaultCellScale);
      expect(r.offset, kCellOffsetZero);
    });

    test('copyWith preserves unspecified fields', () {
      final r = CellReplacement(image: _img(1));
      final scaled = r.copyWith(scale: 1.75);
      expect(scaled.scale, 1.75);
      expect(scaled.image, r.image);
      expect(scaled.offset, r.offset);

      final moved = r.copyWith(offset: const CellOffset(10, 20));
      expect(moved.offset, const CellOffset(10, 20));
      expect(moved.scale, r.scale);
    });
  });

  group('GridEditorState.cellReplacements', () {
    test('default value is an empty map', () {
      final s = GridEditorState.initial();
      expect(s.cellReplacements, isEmpty);
    });

    test('copyWith replaces the whole map immutably', () {
      final base = GridEditorState.initial();
      final image = _img(2);
      final next = base.copyWith(
        cellReplacements: {0: CellReplacement(image: image)},
      );
      expect(base.cellReplacements, isEmpty);
      expect(next.cellReplacements, hasLength(1));
      expect(next.cellReplacements[0]?.image, image);
    });

    test('equality observes per-index replacement differences', () {
      final image = _img(3);
      final s1 = GridEditorState.initial().copyWith(
        cellReplacements: {0: CellReplacement(image: image)},
      );
      final s2 = GridEditorState.initial().copyWith(
        cellReplacements: {0: CellReplacement(image: image)},
      );
      expect(s1, s2);

      final s3 = GridEditorState.initial().copyWith(
        cellReplacements: {1: CellReplacement(image: image)},
      );
      expect(s1, isNot(s3));
    });
  });

  group('GridEditorController per-cell APIs', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);
    });

    test('setCellImage adds and removes entries by index', () {
      final notifier = container.read(gridEditorControllerProvider.notifier);
      final image = _img(4);

      notifier.setCellImage(0, image);
      var state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements, hasLength(1));
      expect(state.cellReplacements[0]?.image, image);
      expect(state.cellReplacements[0]?.scale, kDefaultCellScale);
      expect(state.cellReplacements[0]?.offset, kCellOffsetZero);

      // Adding a different index leaves the existing one alone.
      notifier.setCellImage(4, _img(5));
      state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements, hasLength(2));
      expect(state.cellReplacements.keys.toSet(), {0, 4});

      // Passing null removes the entry.
      notifier.setCellImage(0, null);
      state = container.read(gridEditorControllerProvider);
      expect(state.cellReplacements, hasLength(1));
      expect(state.cellReplacements.containsKey(0), isFalse);
      expect(state.cellReplacements[4]?.image, _img(5));
    });

    test('setCellScale clamps via clampUserScale', () {
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(0, _img(6));

      // 0.5 → clamped to 1.0.
      notifier.setCellScale(0, 0.5);
      expect(
        container.read(gridEditorControllerProvider).cellReplacements[0]?.scale,
        1.0,
      );

      // 3.0 → clamped to 2.0.
      notifier.setCellScale(0, 3.0);
      expect(
        container.read(gridEditorControllerProvider).cellReplacements[0]?.scale,
        2.0,
      );
    });

    test('setCellScale on an empty cell is a no-op', () {
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setCellScale(0, 1.5);
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        isEmpty,
      );
    });

    test('setCellOffset clamps against cover-fit bounds', () {
      final notifier = container.read(gridEditorControllerProvider.notifier);
      // Use a 300x300 image at scale=1.0 (default) — surplus = 0 →
      // offset must clamp to (0, 0).
      notifier.setCellImage(0, _img(7));
      notifier.setCellOffset(0, const CellOffset(100, 100));
      expect(
        container
            .read(gridEditorControllerProvider)
            .cellReplacements[0]
            ?.offset,
        kCellOffsetZero,
      );

      // Bump scale to 2.0 → effective extent 600x600, surplus 300,
      // half-surplus 150 → offset (100, 100) is legal.
      notifier.setCellScale(0, 2.0);
      notifier.setCellOffset(0, const CellOffset(100, 100));
      expect(
        container
            .read(gridEditorControllerProvider)
            .cellReplacements[0]
            ?.offset,
        const CellOffset(100, 100),
      );
    });

    test('resetCell removes the entry (alias of setCellImage(_, null))', () {
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(2, _img(8));
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        hasLength(1),
      );
      notifier.resetCell(2);
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        isEmpty,
      );
    });
  });

  group('GridEditorController.setGridType', () {
    test('clears cellReplacements when type changes', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);

      // Default is 3x3 — populate three replacements.
      notifier.setCellImage(0, _img(10));
      notifier.setCellImage(4, _img(11));
      notifier.setCellImage(8, _img(12));
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        hasLength(3),
      );

      // Switch to 2x2 → map must be empty (indices don't translate).
      notifier.setGridType(GridType.g2x2);
      expect(
        container.read(gridEditorControllerProvider).gridType,
        GridType.g2x2,
      );
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        isEmpty,
      );
    });

    test('preserves cellReplacements when type is unchanged', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);

      notifier.setCellImage(0, _img(20));
      // Re-setting the same type is a no-op (controller short-circuits).
      notifier.setGridType(GridType.g3x3);
      expect(
        container.read(gridEditorControllerProvider).cellReplacements,
        hasLength(1),
      );
    });

    test('preserves spacing / cornerRadius / source on type switch', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWith((_) => const []),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setSpacing(20);
      notifier.setCornerRadius(8);
      notifier.setCellImage(0, _img(30));

      notifier.setGridType(GridType.g2x3);
      final state = container.read(gridEditorControllerProvider);
      expect(state.spacing, 20);
      expect(state.cornerRadius, 8);
      expect(state.cellReplacements, isEmpty);
    });
  });
}
