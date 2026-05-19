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

  group('decodeImageMetadata — EXIF Orientation', () {
    test('JPEG without EXIF reports orientation == 1', () {
      final bytes = _encodeJpeg(width: 40, height: 30);
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      expect(result!.orientation, 1);
    });

    test('JPEG with EXIF Orientation=6 reports orientation == 6', () {
      final bytes = _encodeJpegWithOrientation(
        width: 1440,
        height: 1080,
        orientation: 6,
      );
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      // Header-only dims are the *raw* (pre-rotation) values — that's
      // exactly the failure mode the normalizer's bake path fixes.
      expect(result!.width, 1440);
      expect(result.height, 1080);
      expect(result.orientation, 6);
    });

    test('PNG reports orientation == 1 (no EXIF on PNG fast path)', () {
      final bytes = _encodePng(width: 32, height: 32);
      final result = decodeImageMetadata(bytes);

      expect(result, isNotNull);
      expect(result!.orientation, 1);
    });
  });

  group('ImageNormalizer.normalize — EXIF Orientation bake', () {
    test(
      'JPEG with Orientation=6 → swaps width/height and clears EXIF tag',
      () async {
        // Build a "1440×1080 + Orientation=6" fixture — same shape as
        // the camera JPEGs that triggered the original 1080×1440
        // squish bug in the grid editor.
        final bytes = _encodeJpegWithOrientation(
          width: 1440,
          height: 1080,
          orientation: 6,
        );
        final normalizer = ImageNormalizer();

        final image = await normalizer.normalize(bytes);

        expect(image, isNotNull);
        // After baking, the *user-visible* orientation is the new
        // pixel grid — orientation=6 is a +90° rotation, so a
        // raw-1440×1080 JPEG presents as 1080×1440 on screen.
        expect(image!.width, 1080);
        expect(image.height, 1440);
        expect(image.mimeType, 'image/jpeg');

        // Bytes were rewritten (no longer identical to the input).
        expect(image.bytes, isNot(equals(bytes)));

        // And the rewritten bytes no longer carry an Orientation tag —
        // so downstream consumers (Flutter `Image.memory`, the
        // `image:` package's `decodeImage` in the grid renderer) will
        // both treat the file as identity-oriented.
        final exif = img.decodeJpgExif(image.bytes);
        expect(
          exif?.imageIfd.hasOrientation ?? false,
          isFalse,
          reason:
              'Baked JPEG must not retain the original Orientation tag, '
              'otherwise Flutter would rotate the already-rotated pixels '
              'and the squish bug returns in the opposite direction.',
        );
      },
    );

    test('JPEG with Orientation=1 → fast path keeps bytes identical', () async {
      final bytes = _encodeJpegWithOrientation(
        width: 50,
        height: 30,
        orientation: 1,
      );
      final normalizer = ImageNormalizer();

      final image = await normalizer.normalize(bytes);

      expect(image, isNotNull);
      expect(image!.width, 50);
      expect(image.height, 30);
      expect(
        image.bytes,
        same(bytes),
        reason:
            'Orientation=1 must short-circuit the bake path — no decode, no '
            're-encode — so the original Uint8List instance flows through.',
      );
    });

    test(
      'JPEG without any EXIF tag → fast path keeps bytes identical',
      () async {
        final bytes = _encodeJpeg(width: 40, height: 24);
        final normalizer = ImageNormalizer();

        final image = await normalizer.normalize(bytes);

        expect(image, isNotNull);
        expect(image!.width, 40);
        expect(image.height, 24);
        expect(image.bytes, same(bytes));
      },
    );

    test(
      'PNG → fast path keeps bytes identical (no EXIF read attempted)',
      () async {
        final bytes = _encodePng(width: 16, height: 8);
        final normalizer = ImageNormalizer();

        final image = await normalizer.normalize(bytes);

        expect(image, isNotNull);
        expect(image!.bytes, same(bytes));
        expect(image.width, 16);
        expect(image.height, 8);
      },
    );

    test('JPEG with Orientation=3 (180°) → bake keeps width/height', () async {
      // Orientation 3 is a 180° rotation — width/height don't swap,
      // but the bake path still runs (bytes get rewritten, EXIF tag
      // cleared). Sanity-checks that we handle the non-swap branch.
      final bytes = _encodeJpegWithOrientation(
        width: 80,
        height: 40,
        orientation: 3,
      );
      final normalizer = ImageNormalizer();

      final image = await normalizer.normalize(bytes);

      expect(image, isNotNull);
      expect(image!.width, 80);
      expect(image.height, 40);
      expect(image.bytes, isNot(equals(bytes)));

      final exif = img.decodeJpgExif(image.bytes);
      expect(exif?.imageIfd.hasOrientation ?? false, isFalse);
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

/// Builds a JPEG whose EXIF Orientation tag is set to [orientation]
/// (1..8). The pixel buffer is filled with a recognisable per-axis
/// gradient so that — if a downstream test ever needs to verify "did
/// the bake actually rotate the pixels?" — the post-bake pixels can be
/// sampled against the expected transform.
///
/// This fixture mirrors the typical mobile-camera output that causes
/// the 1080×1440 squish bug: a JPEG whose raw header dimensions are
/// landscape (e.g. 1440×1080) but whose Orientation=6 tells viewers
/// "rotate 90° CW for display".
Uint8List _encodeJpegWithOrientation({
  required int width,
  required int height,
  required int orientation,
}) {
  final image = img.Image(width: width, height: height);
  // Gradient so the decoder has real data to round-trip (some
  // older JPEG decoders treat a fully black image as a degenerate
  // case).
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        (x * 255) ~/ width,
        (y * 255) ~/ height,
        128,
        255,
      );
    }
  }
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

Uint8List _encodeGif({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodeGif(image));
}
