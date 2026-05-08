import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/data/repositories/image_import_repository_impl.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ImageImportRepositoryImpl.importRawBytes', () {
    test('returns ImportFailure(ImportCancelled) for empty input', () async {
      final repo = ImageImportRepositoryImpl();

      final result = await repo.importRawBytes(const []);

      expect(result, isA<ImportFailure>());
      expect((result as ImportFailure).failure, isA<ImportCancelled>());
    });

    test('normalizes a single PNG into ImportSuccess', () async {
      final repo = ImageImportRepositoryImpl();
      final png = _png(width: 6, height: 4);

      final result = await repo.importRawBytes([
        RawImageBytes(bytes: png, suggestedName: 'one.png'),
      ]);

      expect(result, isA<ImportSuccess>());
      final success = result as ImportSuccess;
      expect(success.images, hasLength(1));
      expect(success.images.single.width, 6);
      expect(success.images.single.height, 4);
      expect(success.images.single.mimeType, 'image/png');
      expect(success.partial, isFalse);
      expect(success.skippedReason, isNull);
    });

    test('drops non-image entries and reports partial success', () async {
      final repo = ImageImportRepositoryImpl();
      final png = _png(width: 4, height: 4);
      final junk = Uint8List.fromList(const [0, 1, 2, 3, 4, 5, 6, 7]);

      final result = await repo.importRawBytes([
        RawImageBytes(bytes: png),
        RawImageBytes(bytes: junk),
      ]);

      expect(result, isA<ImportSuccess>());
      final success = result as ImportSuccess;
      expect(success.images, hasLength(1));
      expect(success.partial, isTrue);
      expect(success.skippedReason, isA<InvalidImageData>());
    });

    test('returns InvalidImageData failure when nothing decodes', () async {
      final repo = ImageImportRepositoryImpl();
      final junk = Uint8List.fromList(const [9, 9, 9, 9]);

      final result = await repo.importRawBytes([
        RawImageBytes(bytes: junk),
        RawImageBytes(bytes: junk),
      ]);

      expect(result, isA<ImportFailure>());
      expect((result as ImportFailure).failure, isA<InvalidImageData>());
    });

    test(
      'truncates inputs above the 20-image cap and flags TooManyImages',
      () async {
        final repo = ImageImportRepositoryImpl();
        // 25 valid PNGs — repository should keep 20 and report partial.
        final inputs = List.generate(
          25,
          (_) => RawImageBytes(bytes: _png(width: 2, height: 2)),
        );

        final result = await repo.importRawBytes(inputs);

        expect(result, isA<ImportSuccess>());
        final success = result as ImportSuccess;
        expect(success.images, hasLength(kMaxImportSessionImages));
        expect(success.partial, isTrue);
        expect(success.skippedReason, isA<TooManyImages>());
        final reason = success.skippedReason! as TooManyImages;
        expect(reason.attempted, 25);
        expect(reason.maxAllowed, kMaxImportSessionImages);
      },
    );

    test(
      'produces ImportedImage shapes identical across input variants',
      () async {
        // Same PNG bytes from "different sources" must produce identical
        // shapes (modulo sourcePath / declaredMimeType hints), per the
        // PRD's "All paths produce identical ImportedImage shape" criterion.
        final repo = ImageImportRepositoryImpl();
        final png = _png(width: 7, height: 9);

        final fromGalleryShape = await repo.importRawBytes([
          RawImageBytes(
            bytes: png,
            sourcePath: '/tmp/gallery.png',
            declaredMimeType: 'image/png',
          ),
        ]);
        final fromClipboardShape = await repo.importRawBytes([
          RawImageBytes(bytes: png),
        ]);

        expect(fromGalleryShape, isA<ImportSuccess>());
        expect(fromClipboardShape, isA<ImportSuccess>());

        final a = (fromGalleryShape as ImportSuccess).images.single;
        final b = (fromClipboardShape as ImportSuccess).images.single;

        expect(a.width, b.width);
        expect(a.height, b.height);
        expect(a.mimeType, b.mimeType);
        expect(a.bytes, b.bytes);
        // sourcePath legitimately differs by source; everything else
        // (the dimensions / bytes / mime) must be identical.
      },
    );
  });
}

Uint8List _png({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}
