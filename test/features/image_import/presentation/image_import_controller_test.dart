import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements ImageImportRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const <RawImageBytes>[]);
  });

  // Most behaviour tests run against the stitch session — the controller
  // itself is identical across kinds, the family arg is only a cache
  // key. The dedicated "session isolation" group at the bottom of this
  // file pumps both kinds to assert they stay independent.
  const kind = ImageImportSessionKind.stitch;

  group('ImageImportController', () {
    late _MockRepo repo;

    setUp(() {
      repo = _MockRepo();
    });

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test('starts with an empty list', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final initial = await container.read(
        imageImportControllerProvider(kind).future,
      );
      expect(initial, isEmpty);
    });

    test('pickFromGallery appends successful images', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')], partial: false));

      final container = makeContainer();
      addTearDown(container.dispose);

      // Wait for initial build.
      await container.read(imageImportControllerProvider(kind).future);
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pickFromGallery();

      final state = container.read(imageImportControllerProvider(kind));
      expect(state.valueOrNull, isNotNull);
      expect(state.valueOrNull!, hasLength(1));
    });

    test('addFromDrop appends, respecting the 20-image cap', () async {
      // Repo returns 25 successful images for any input.
      when(() => repo.importRawBytes(any())).thenAnswer((invocation) async {
        final input =
            invocation.positionalArguments.first as List<RawImageBytes>;
        return ImportSuccess(
          List.generate(input.length, (i) => _image('drop-$i')),
        );
      });

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);

      // Drop 25 raw items.
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .addFromDrop(
            List.generate(
              25,
              (_) => RawImageBytes(bytes: Uint8List.fromList([0])),
            ),
          );

      final list = container
          .read(imageImportControllerProvider(kind))
          .valueOrNull!;
      expect(
        list,
        hasLength(kMaxImportSessionImages),
        reason:
            'Even when the repository returns more than 20 images, the '
            'controller must enforce the per-session cap.',
      );
      final controller = container.read(
        imageImportControllerProvider(kind).notifier,
      );
      expect(controller.lastWarning, isA<TooManyImages>());
    });

    test('pasteFromClipboard surfaces failures via AsyncError', () async {
      when(() => repo.pasteFromClipboard()).thenAnswer(
        (_) async => const ImportFailure(
          InvalidImageData('Clipboard does not contain a supported image.'),
        ),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);

      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pasteFromClipboard();

      final state = container.read(imageImportControllerProvider(kind));
      expect(state, isA<AsyncError<List<ImportedImage>>>());
      expect(state.error, isA<InvalidImageData>());
    });

    test('cancelled imports keep the previous list intact', () async {
      // First populate with one image.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('first')]));

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pickFromGallery();
      expect(container.read(importedImagesProvider(kind)), hasLength(1));

      // Now simulate user cancelling the camera prompt.
      when(
        () => repo.captureFromCamera(),
      ).thenAnswer((_) async => const ImportFailure(ImportCancelled()));
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .captureFromCamera();

      // List should still have the originally-picked image.
      expect(container.read(importedImagesProvider(kind)), hasLength(1));
    });

    test('removeAt drops the indexed image', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pickFromGallery();

      container.read(imageImportControllerProvider(kind).notifier).removeAt(1);

      final list = container.read(importedImagesProvider(kind));
      expect(list.map((i) => i.sourcePath).toList(), ['a', 'c']);
    });

    test(
      'reorder moves item forward across the list (post-removal index)',
      () async {
        when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
          (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
        );

        final container = makeContainer();
        addTearDown(container.dispose);
        await container.read(imageImportControllerProvider(kind).future);
        await container
            .read(imageImportControllerProvider(kind).notifier)
            .pickFromGallery();

        // reorderables convention: newIndex is the post-removal index
        // where the moved item should land. Moving 'a' (oldIndex=0) to
        // the end of a 3-item list = newIndex=2 (after removing 'a' the
        // remaining list is length 2, so position 2 means "append").
        container
            .read(imageImportControllerProvider(kind).notifier)
            .reorder(0, 2);

        final list = container.read(importedImagesProvider(kind));
        expect(list.map((i) => i.sourcePath).toList(), ['b', 'c', 'a']);
      },
    );

    test(
      'reorder moves item one slot forward (the user-reported bug)',
      () async {
        when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
          (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
        );

        final container = makeContainer();
        addTearDown(container.dispose);
        await container.read(imageImportControllerProvider(kind).future);
        await container
            .read(imageImportControllerProvider(kind).notifier)
            .pickFromGallery();

        // Move 'a' (oldIndex=0) to land just after 'b' — under the
        // reorderables convention this is newIndex=1 (post-removal:
        // remove 'a' from [a,b,c] → [b,c]; insert at 1 → [b, a, c]).
        // Regression for the bug where the previous `newIndex - 1`
        // double-adjustment short-circuited this move to a no-op.
        container
            .read(imageImportControllerProvider(kind).notifier)
            .reorder(0, 1);

        final list = container.read(importedImagesProvider(kind));
        expect(list.map((i) => i.sourcePath).toList(), ['b', 'a', 'c']);
      },
    );

    test('reorder moves item backward (post-removal index)', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pickFromGallery();

      // Move 'c' (oldIndex=2) to the front — newIndex=0 under either
      // convention (backward moves are unaffected by the bug; this
      // test guards against any future "fix" that overshoots in the
      // other direction).
      container
          .read(imageImportControllerProvider(kind).notifier)
          .reorder(2, 0);

      final list = container.read(importedImagesProvider(kind));
      expect(list.map((i) => i.sourcePath).toList(), ['c', 'a', 'b']);
    });

    test('clear empties the list', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')]));

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider(kind).future);
      await container
          .read(imageImportControllerProvider(kind).notifier)
          .pickFromGallery();

      container.read(imageImportControllerProvider(kind).notifier).clear();

      expect(container.read(importedImagesProvider(kind)), isEmpty);
    });
  });

  group('ImageImportController — per-mode session isolation', () {
    late _MockRepo repo;

    setUp(() {
      repo = _MockRepo();
    });

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test('stitch and grid sessions store images independently', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('only-stitch')]));

      final container = makeContainer();
      addTearDown(container.dispose);

      // Trigger initial build for both kinds so the family instances
      // exist in the container.
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).future,
      );
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.grid).future,
      );

      // Pick into stitch only.
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
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.grid)),
        isEmpty,
        reason: 'grid session must stay empty when only stitch was imported',
      );
    });

    test('lastWarning is per-instance', () async {
      // Stitch path produces a TooManyImages warning; grid path stays
      // clean.
      when(() => repo.importRawBytes(any())).thenAnswer((invocation) async {
        final input =
            invocation.positionalArguments.first as List<RawImageBytes>;
        return ImportSuccess(
          List.generate(input.length, (i) => _image('drop-$i')),
        );
      });

      final container = makeContainer();
      addTearDown(container.dispose);
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
          .addFromDrop(
            List.generate(
              25,
              (_) => RawImageBytes(bytes: Uint8List.fromList([0])),
            ),
          );

      final stitchController = container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
      );
      final gridController = container.read(
        imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
      );
      expect(stitchController.lastWarning, isA<TooManyImages>());
      expect(
        gridController.lastWarning,
        isNull,
        reason: 'grid session warning must not be flagged by stitch import',
      );
    });

    test('clear on one kind does not affect the other', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('shared')]));

      final container = makeContainer();
      addTearDown(container.dispose);

      // Populate both.
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
      await container
          .read(
            imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
          )
          .pickFromGallery();

      // Clear stitch only.
      container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .clear();

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        isEmpty,
      );
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.grid)),
        hasLength(1),
        reason: 'clearing stitch must not touch the grid session',
      );
    });

    test('AsyncError on stitch does not surface on grid', () async {
      when(() => repo.pasteFromClipboard()).thenAnswer(
        (_) async => const ImportFailure(
          InvalidImageData('Clipboard does not contain a supported image.'),
        ),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
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
          .pasteFromClipboard();

      final stitchState = container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch),
      );
      final gridState = container.read(
        imageImportControllerProvider(ImageImportSessionKind.grid),
      );
      expect(stitchState, isA<AsyncError<List<ImportedImage>>>());
      expect(
        gridState,
        isA<AsyncData<List<ImportedImage>>>(),
        reason: 'grid must remain in AsyncData when stitch fails',
      );
      expect(gridState.valueOrNull, isEmpty);
    });
  });
}

ImportedImage _image(String path) {
  // Use a real (tiny) PNG so byte sniffing in any consumer code stays
  // happy if the test ever feeds the bytes back through the normalizer.
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 1, height: 1)),
  );
  return ImportedImage(
    sourcePath: path,
    bytes: bytes,
    width: 1,
    height: 1,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 9),
  );
}
