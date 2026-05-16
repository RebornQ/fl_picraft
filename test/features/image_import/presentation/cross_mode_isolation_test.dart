import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

/// Cross-editor isolation regression tests. The implementation lives in
/// `lib/features/image_import/presentation/providers/image_import_provider.dart`
/// where `imageImportControllerProvider` is keyed by
/// `ImageImportSessionKind`. These tests assert the family produces
/// genuinely independent sessions per editor (PRD AC2.1 — AC2.3) and
/// that one editor's state survives a brief visit to the other (AC2.4).
///
/// These run as plain `test`s, not `testWidgets`, because the family
/// provider semantics are observable purely through `ProviderContainer`
/// — no widget tree is involved, and `testWidgets`'s `FakeAsync` keeps
/// the AsyncNotifier scheduler micro-tasks pending past tearDown.

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
    importedAt: DateTime.utc(2026, 5, 16),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const <RawImageBytes>[]);
  });

  group('Cross-mode import session isolation', () {
    late _MockRepo repo;

    setUp(() {
      repo = _MockRepo();
    });

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test(
      'AC2.1: stitch imports do not appear in the grid editor state',
      () async {
        when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
          (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
        );
        final container = makeContainer();
        addTearDown(container.dispose);

        // Build both editor controllers so their `ref.listen` wires up to
        // the correct family instance before the import runs.
        container.read(stitchEditorControllerProvider);
        container.read(gridEditorControllerProvider);
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).future,
        );
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.grid).future,
        );

        // Import 3 images into the stitch session.
        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();

        expect(
          container.read(stitchEditorControllerProvider).images,
          hasLength(3),
        );
        expect(
          container.read(gridEditorControllerProvider).hasSource,
          isFalse,
          reason: 'grid editor must not see the stitch imports',
        );
        expect(
          container.read(importedImagesProvider(ImageImportSessionKind.grid)),
          isEmpty,
        );
      },
    );

    test(
      'AC2.2: grid imports do not appear in the stitch editor state',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('grid-source')]));
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(stitchEditorControllerProvider);
        container.read(gridEditorControllerProvider);
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).future,
        );
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.grid).future,
        );

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.grid,
              ).notifier,
            )
            .pickFromGallery();

        expect(container.read(gridEditorControllerProvider).hasSource, isTrue);
        expect(
          container.read(stitchEditorControllerProvider).images,
          isEmpty,
          reason: 'stitch editor must not see grid imports',
        );
      },
    );

    test(
      'AC2.3: AsyncError on stitch session never leaks into the grid state',
      () async {
        when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
          (_) async => const ImportFailure(
            InvalidImageData('Mocked failure for stitch import'),
          ),
        );
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(stitchEditorControllerProvider);
        container.read(gridEditorControllerProvider);
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).future,
        );
        await container.read(
          imageImportControllerProvider(ImageImportSessionKind.grid).future,
        );

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();

        // Stitch surface is in error; grid surface stays in clean data.
        final stitchState = container.read(
          imageImportControllerProvider(ImageImportSessionKind.stitch),
        );
        final gridState = container.read(
          imageImportControllerProvider(ImageImportSessionKind.grid),
        );
        expect(stitchState, isA<AsyncError<List<ImportedImage>>>());
        expect(gridState, isA<AsyncData<List<ImportedImage>>>());
        expect(gridState.valueOrNull, isEmpty);
      },
    );

    test('AC2.4: tab-switch round-trip preserves the stitch session', () async {
      // Simulates "stitch imported 3 → user opens grid tab → comes
      // back to stitch → stitch still has the 3 images". The
      // `StatefulShellRoute` semantics are owned by the app shell,
      // but the underlying invariant is "the controller's state
      // outlives any individual screen". Verified here by reading
      // the controller before / after a no-op grid editor build
      // (mimicking the grid tab mounting and unmounting).
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(stitchEditorControllerProvider);
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
        container.read(stitchEditorControllerProvider).images,
        hasLength(3),
      );

      // Visit grid (build the grid editor's controller) and leave.
      // The default Riverpod provider lifetime is non-autoDispose,
      // so the stitch session survives.
      container.read(gridEditorControllerProvider);
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.grid).future,
      );

      // Back to stitch — it should still have 3 images.
      expect(
        container.read(stitchEditorControllerProvider).images,
        hasLength(3),
        reason:
            'stitch session must survive the user briefly visiting the '
            'grid editor (analogue of a StatefulShellRoute tab switch)',
      );
    });
  });
}
