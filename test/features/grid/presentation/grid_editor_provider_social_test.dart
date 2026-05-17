import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/entities/grid_editor_state.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/compute_center_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements ImageImportRepository {}

ImportedImage _image(String tag, {int w = 300, int h = 300}) => ImportedImage(
  bytes: Uint8List.fromList([
    for (var i = 0; i < tag.length; i++) tag.codeUnitAt(i),
  ]),
  width: w,
  height: h,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 14),
);

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
    );
  }

  group('GridEditorController — nine-grid-social mode', () {
    test('initial state has social mode off and no center image', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final state = container.read(gridEditorControllerProvider);
      expect(state.nineGridSocialMode, false);
      expect(state.centerImage, isNull);
      expect(state.centerScale, kDefaultCenterScale);
      expect(state.centerOffset, kCenterOffsetZero);
    });

    test('setNineGridSocialMode(true) locks grid type to 3x3', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      // Start from 2x3 to prove the lock kicks in.
      notifier.setGridType(GridType.g2x3);
      expect(
        container.read(gridEditorControllerProvider).gridType,
        GridType.g2x3,
      );
      notifier.setNineGridSocialMode(true);
      final state = container.read(gridEditorControllerProvider);
      expect(state.nineGridSocialMode, true);
      expect(state.gridType, GridType.g3x3);
    });

    test('setGridType is ignored while social mode is on', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setGridType(GridType.g2x3); // should be no-op
      expect(
        container.read(gridEditorControllerProvider).gridType,
        GridType.g3x3,
      );
    });

    test('setNineGridSocialMode(false) clears center image state', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('center'));
      notifier.setCenterScale(1.5);
      notifier.setCenterOffset(const CenterOffset(30, 20));

      // Sanity: state populated.
      var state = container.read(gridEditorControllerProvider);
      expect(state.centerImage, isNotNull);
      expect(state.centerScale, 1.5);

      notifier.setNineGridSocialMode(false);
      state = container.read(gridEditorControllerProvider);
      expect(state.nineGridSocialMode, false);
      expect(state.centerImage, isNull);
      expect(state.centerScale, kDefaultCenterScale);
      expect(state.centerOffset, kCenterOffsetZero);
    });

    test(
      'setCenterImage(null) clears the replacement and resets transform',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(gridEditorControllerProvider.notifier);
        notifier.setNineGridSocialMode(true);
        notifier.setCenterImage(_image('center'));
        notifier.setCenterScale(1.8);

        notifier.setCenterImage(null);

        final state = container.read(gridEditorControllerProvider);
        expect(state.centerImage, isNull);
        expect(state.centerScale, kDefaultCenterScale);
        expect(state.centerOffset, kCenterOffsetZero);
      },
    );

    test('setCenterScale clamps below cover-fit to 1.0', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('center', w: 100, h: 100));
      notifier.setCenterScale(0.5);
      expect(
        container.read(gridEditorControllerProvider).centerScale,
        1,
        reason: 'PRD edge case: 0.5x clamps to cover-fit',
      );
    });

    test('setCenterScale clamps above 2.0 to the PRD ceiling', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('center'));
      notifier.setCenterScale(5);
      expect(container.read(gridEditorControllerProvider).centerScale, 2);
    });

    test('setCenterOffset is a no-op without a center image', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterOffset(const CenterOffset(40, 40));
      expect(
        container.read(gridEditorControllerProvider).centerOffset,
        kCenterOffsetZero,
        reason: 'Offset can only be set after a center image is picked',
      );
    });

    test('setCenterOffset clamps to the half-surplus when scale > 1', () {
      // No source set → controller's `_currentCenterCellExtent`
      // falls back to 256 px. Center image 300x300 → cover = 256/300.
      // At userScale=1.5 effective = cover * 1.5 ≈ 1.28. Scaled image
      // = 300 * 1.28 ≈ 384. Surplus = 384 - 256 = 128 → half-surplus
      // 64. An offset request of 100 should clamp to 64.
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('center'));
      notifier.setCenterScale(1.5);
      notifier.setCenterOffset(const CenterOffset(100, 100));
      final state = container.read(gridEditorControllerProvider);
      expect(state.centerOffset.dx, 64);
      expect(state.centerOffset.dy, 64);
    });

    test(
      'pickCenterImage swallows ImportFailure and keeps existing state',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => const ImportFailure(ImportCancelled()));

        final container = makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(gridEditorControllerProvider.notifier);
        notifier.setNineGridSocialMode(true);
        final existing = _image('existing');
        notifier.setCenterImage(existing);

        await notifier.pickCenterImage();

        expect(
          container.read(gridEditorControllerProvider).centerImage,
          existing,
          reason: 'cancellation must not wipe an existing replacement',
        );
      },
    );

    test('pickCenterImage replaces center image on ImportSuccess', () async {
      final picked = _image('picked');
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([picked]));

      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);

      await notifier.pickCenterImage();

      expect(container.read(gridEditorControllerProvider).centerImage, picked);
    });

    test('pickCenterImage does not pollute the main import session', () async {
      // The grid editor's "source" image comes from the import
      // session — we want the center-image pick to be a peer flow,
      // not touch the session. Verifying by inspecting that we never
      // see the picked image surface in the main session list.
      final picked = _image('picked-center');
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([picked]));

      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gridEditorControllerProvider.notifier);
      // Trigger initial build of the grid-scoped import controller.
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.grid).future,
      );

      notifier.setNineGridSocialMode(true);
      await notifier.pickCenterImage();

      final session = container.read(
        importedImagesProvider(ImageImportSessionKind.grid),
      );
      expect(
        session,
        isEmpty,
        reason: 'center pick must not append to the grid import session',
      );
    });
  });

  group('GridEditorState — nine-grid-social helpers', () {
    test(
      'isSocialModeActiveWithReplacement is true only when both fields set',
      () {
        var state = GridEditorState.initial();
        expect(state.isSocialModeActiveWithReplacement, false);

        state = state.copyWith(nineGridSocialMode: true);
        expect(state.isSocialModeActiveWithReplacement, false);

        state = state.copyWith(centerImage: _image('c'));
        expect(state.isSocialModeActiveWithReplacement, true);

        state = state.copyWith(nineGridSocialMode: false);
        expect(state.isSocialModeActiveWithReplacement, false);
      },
    );

    test('hasCenterImage reflects the centerImage field', () {
      var state = GridEditorState.initial();
      expect(state.hasCenterImage, false);
      state = state.copyWith(centerImage: _image('c'));
      expect(state.hasCenterImage, true);
      state = state.copyWith(clearCenterImage: true);
      expect(state.hasCenterImage, false);
    });
  });
}
