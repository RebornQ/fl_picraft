import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_editor_state.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

/// Provider-level tests for `StitchEditorController` focused on the
/// movie-subtitle band-height auto-reset rule
/// (task: `05-18-subtitle-reset-on-reselect`).
///
/// These run as plain `test`s, not `testWidgets`, because the
/// assertions target the controller's `state` — no widget tree is
/// involved. See `.trellis/spec/frontend/quality-guidelines.md` →
/// "Pattern: Plain `test` over `testWidgets` for `AsyncNotifier`-only
/// assertions" for the rationale.

class _MockRepo extends Mock implements ImageImportRepository {}

ImportedImage _image(String path) {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 1, height: 1)),
  );
  return ImportedImage(
    sourcePath: path,
    bytes: bytes,
    width: 1,
    height: 1,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 18),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const <RawImageBytes>[]);
  });

  group('StitchEditorController subtitle-band-height reset', () {
    late _MockRepo repo;

    setUp(() {
      repo = _MockRepo();
    });

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
      );
    }

    Future<void> primeBoth(ProviderContainer container) async {
      // Build the editor controller so `ref.listen` is wired up before
      // any import runs.
      container.read(stitchEditorControllerProvider);
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).future,
      );
    }

    test('empty → first image picked: percent resets to default '
        '(even if previously customized)', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')]));
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      // Customize the percent before any image arrives — simulates
      // the slider being touched while the editor is empty.
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.30);
      expect(
        container
            .read(stitchEditorControllerProvider)
            .subtitleBandHeightPercent,
        0.30,
      );

      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(1));
      expect(
        state.subtitleBandHeightPercent,
        kDefaultSubtitleBandHeightPercent,
        reason:
            'Picking the first image after an empty session must reset '
            'the band-height percent to the default.',
      );
    });

    test('non-empty → append more images: percent unchanged', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')]));
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      // First import — percent resets to default per the rule.
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      expect(
        container.read(stitchEditorControllerProvider).images,
        hasLength(1),
      );

      // User customizes the percent now that there's a first image.
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.40);

      // Append more — the list goes from 1 → 2 (still non-empty
      // before the change), so the reset rule must NOT fire.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('b')]));
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(2));
      expect(state.subtitleBandHeightPercent, 0.40);
    });

    test('clear all → pick again: percent resets to default', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a'), _image('b')]));
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.35);
      expect(
        container
            .read(stitchEditorControllerProvider)
            .subtitleBandHeightPercent,
        0.35,
      );

      // Clear via the editor — which routes through the import
      // controller. The list goes 2 → 0 → (next import) 1.
      container.read(stitchEditorControllerProvider.notifier).clear();
      expect(container.read(stitchEditorControllerProvider).images, isEmpty);
      // Percent unchanged when going non-empty → empty.
      expect(
        container
            .read(stitchEditorControllerProvider)
            .subtitleBandHeightPercent,
        0.35,
      );

      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('c')]));
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(1));
      expect(
        state.subtitleBandHeightPercent,
        kDefaultSubtitleBandHeightPercent,
      );
    });

    test(
      'remove all one-by-one to empty → pick again: percent resets',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('a'), _image('b')]));
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();
        container
            .read(stitchEditorControllerProvider.notifier)
            .setSubtitleBandHeightPercent(0.42);

        // Remove last, then first — list goes 2 → 1 → 0.
        container.read(stitchEditorControllerProvider.notifier).removeImage(1);
        expect(
          container
              .read(stitchEditorControllerProvider)
              .subtitleBandHeightPercent,
          0.42,
          reason: 'mid-list removal must not reset',
        );
        container.read(stitchEditorControllerProvider.notifier).removeImage(0);
        expect(container.read(stitchEditorControllerProvider).images, isEmpty);
        expect(
          container
              .read(stitchEditorControllerProvider)
              .subtitleBandHeightPercent,
          0.42,
          reason: 'transitioning to empty must not reset by itself',
        );

        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('c')]));
        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();

        final state = container.read(stitchEditorControllerProvider);
        expect(state.images, hasLength(1));
        expect(
          state.subtitleBandHeightPercent,
          kDefaultSubtitleBandHeightPercent,
        );
      },
    );

    test('reorder while non-empty: percent unchanged', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.28);

      // Move the first item to position 2 (standard reorderable
      // newIndex convention — post-removal coords).
      container.read(stitchEditorControllerProvider.notifier).reorder(0, 2);

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(3));
      expect(state.subtitleBandHeightPercent, 0.28);
    });

    test('remove non-first while still non-empty: percent unchanged', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.33);

      container.read(stitchEditorControllerProvider.notifier).removeImage(1);

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(2));
      expect(state.subtitleBandHeightPercent, 0.33);
    });

    test('initial mount with a pre-existing image list: percent NOT reset '
        'when more images are later added', () async {
      // Pre-populate the import session BEFORE building the stitch
      // editor controller. This simulates the editor mounting onto a
      // session that already holds images (e.g. shell tab switch).
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('seed')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      // Build the import controller first and seed it.
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).future,
      );
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(1),
      );

      // Now build the stitch editor controller — its `build()` sees
      // initial = [seed] and seeds state.images with that. The
      // listener wires up but does NOT fire yet.
      final initialState = container.read(stitchEditorControllerProvider);
      expect(initialState.images, hasLength(1));
      expect(
        initialState.subtitleBandHeightPercent,
        kDefaultSubtitleBandHeightPercent,
      );

      // Customize the percent — simulates the user touching the
      // slider on a session that was already populated.
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.45);

      // Trigger a subsequent import. The listener fires for the
      // first time with prev=null (Riverpod's listen contract) and
      // next=[seed, more]. The `state.images.isEmpty` guard must
      // prevent a reset here.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('more')]));
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      final state = container.read(stitchEditorControllerProvider);
      expect(state.images, hasLength(2));
      expect(
        state.subtitleBandHeightPercent,
        0.45,
        reason:
            'Mounting onto a pre-existing non-empty session must not '
            'trigger the band-height reset on the listener first-fire.',
      );
    });
  });
}
