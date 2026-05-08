import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
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
        imageImportControllerProvider.future,
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
      await container.read(imageImportControllerProvider.future);
      await container
          .read(imageImportControllerProvider.notifier)
          .pickFromGallery();

      final state = container.read(imageImportControllerProvider);
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
      await container.read(imageImportControllerProvider.future);

      // Drop 25 raw items.
      await container
          .read(imageImportControllerProvider.notifier)
          .addFromDrop(
            List.generate(
              25,
              (_) => RawImageBytes(bytes: Uint8List.fromList([0])),
            ),
          );

      final list = container.read(imageImportControllerProvider).valueOrNull!;
      expect(
        list,
        hasLength(kMaxImportSessionImages),
        reason:
            'Even when the repository returns more than 20 images, the '
            'controller must enforce the per-session cap.',
      );
      final controller = container.read(imageImportControllerProvider.notifier);
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
      await container.read(imageImportControllerProvider.future);

      await container
          .read(imageImportControllerProvider.notifier)
          .pasteFromClipboard();

      final state = container.read(imageImportControllerProvider);
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
      await container.read(imageImportControllerProvider.future);
      await container
          .read(imageImportControllerProvider.notifier)
          .pickFromGallery();
      expect(container.read(importedImagesProvider), hasLength(1));

      // Now simulate user cancelling the camera prompt.
      when(
        () => repo.captureFromCamera(),
      ).thenAnswer((_) async => const ImportFailure(ImportCancelled()));
      await container
          .read(imageImportControllerProvider.notifier)
          .captureFromCamera();

      // List should still have the originally-picked image.
      expect(container.read(importedImagesProvider), hasLength(1));
    });

    test('removeAt drops the indexed image', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider.future);
      await container
          .read(imageImportControllerProvider.notifier)
          .pickFromGallery();

      container.read(imageImportControllerProvider.notifier).removeAt(1);

      final list = container.read(importedImagesProvider);
      expect(list.map((i) => i.sourcePath).toList(), ['a', 'c']);
    });

    test('reorder swaps positions correctly', () async {
      when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
        (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider.future);
      await container
          .read(imageImportControllerProvider.notifier)
          .pickFromGallery();

      // Move 'a' to the end (ListView.reorder convention: newIndex
      // counts the gap *after* the destination, so newIndex=3 inserts
      // at the end of a 3-item list).
      container.read(imageImportControllerProvider.notifier).reorder(0, 3);

      final list = container.read(importedImagesProvider);
      expect(list.map((i) => i.sourcePath).toList(), ['b', 'c', 'a']);
    });

    test('clear empties the list', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')]));

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(imageImportControllerProvider.future);
      await container
          .read(imageImportControllerProvider.notifier)
          .pickFromGallery();

      container.read(imageImportControllerProvider.notifier).clear();

      expect(container.read(importedImagesProvider), isEmpty);
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
