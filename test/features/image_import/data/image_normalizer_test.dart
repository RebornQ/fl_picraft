import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/data/utils/image_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('decodeImageMetadata', () {
    test('returns null for empty bytes', () {
      expect(decodeImageMetadata(Uint8List(0)), isNull);
    });

    test('returns null for bytes that aren\'t a recognized image', () {
      final junk = Uint8List.fromList(List<int>.generate(64, (i) => i));
      expect(decodeImageMetadata(junk), isNull);
    });

    test('detects PNG width / height / mime', () {
      final bytes = _encodePng(width: 24, height: 12);
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      expect(result!.width, 24);
      expect(result.height, 12);
      expect(result.mimeType, 'image/png');
    });

    test('detects JPEG width / height / mime', () {
      final bytes = _encodeJpeg(width: 50, height: 30);
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      expect(result!.width, 50);
      expect(result.height, 30);
      expect(result.mimeType, 'image/jpeg');
    });

    test('detects GIF', () {
      final bytes = _encodeGif(width: 8, height: 8);
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      expect(result!.mimeType, 'image/gif');
    });
  });

  group('ImageNormalizer.normalize', () {
    test('returns ImportedImage for valid PNG bytes', () async {
      final bytes = _encodePng(width: 16, height: 8);
      final fixedNow = DateTime.utc(2026, 5, 9, 12);
      final normalizer = ImageNormalizer(now: () => fixedNow);

      final image = await normalizer.normalize(
        bytes,
        sourcePath: '/tmp/sample.png',
        declaredMimeType: 'image/png',
      );

      expect(image, isNotNull);
      expect(image!.bytes, bytes);
      expect(image.sourcePath, '/tmp/sample.png');
      expect(image.width, 16);
      expect(image.height, 8);
      expect(image.mimeType, 'image/png');
      expect(image.importedAt, fixedNow);
    });

    test('returns null when bytes aren\'t a recognized image', () async {
      final normalizer = ImageNormalizer();
      final image = await normalizer.normalize(
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
      );
      expect(image, isNull);
    });

    test('overrides incorrect declaredMimeType from byte sniffing', () async {
      final pngBytes = _encodePng(width: 4, height: 4);
      final normalizer = ImageNormalizer();

      final image = await normalizer.normalize(
        pngBytes,
        declaredMimeType: 'application/octet-stream',
      );

      expect(image, isNotNull);
      expect(
        image!.mimeType,
        'image/png',
        reason:
            'Normalizer must trust magic-byte detection over caller-supplied '
            'MIME hints, otherwise generic `octet-stream` from image_picker '
            'leaks through to downstream features.',
      );
    });

    test('keeps sourcePath null for clipboard / drag-drop bytes', () async {
      final bytes = _encodePng(width: 1, height: 1);
      final normalizer = ImageNormalizer();

      final image = await normalizer.normalize(bytes);

      expect(image, isNotNull);
      expect(image!.sourcePath, isNull);
    });

    test('decodes a >2MB buffer correctly (compute fallback path)', () async {
      // Random noise resists PNG compression — necessary because a flat
      // gradient compresses below the 2MB threshold and would silently
      // bypass the off-isolate decode path.
      final bytes = _encodePngNoise(width: 1024, height: 1024);
      expect(
        bytes.length,
        greaterThan(kDecodeIsolateThresholdBytes),
        reason:
            'Test fixture must exceed isolate threshold to actually exercise '
            'the off-thread decode path.',
      );

      final normalizer = ImageNormalizer();
      final image = await normalizer.normalize(bytes);

      expect(image, isNotNull);
      expect(image!.width, 1024);
      expect(image.height, 1024);
    });
  });
}

Uint8List _encodePng({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _encodePngNoise({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  // Math.Random is uniform across [0, 1<<32) which produces real entropy
  // — PNG can only compress runs and patterns so noise stays close to
  // the raw byte size after encoding.
  final rng = math.Random(42);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        rng.nextInt(256),
        rng.nextInt(256),
        rng.nextInt(256),
        255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _encodeJpeg({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _encodeGif({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodeGif(image));
}
