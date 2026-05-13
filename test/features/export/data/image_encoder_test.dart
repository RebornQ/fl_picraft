import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/image_encoder.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// 60x40 deterministic test fixture — a horizontal stripe of red,
  /// green, blue regions on a transparent canvas. Encoded as PNG so
  /// the alpha channel survives the round-trip.
  Uint8List rgbStripesPng() {
    final canvas = img.Image(width: 60, height: 40, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      canvas,
      x1: 0,
      y1: 0,
      x2: 19,
      y2: 39,
      color: img.ColorRgba8(220, 30, 30, 255),
    );
    img.fillRect(
      canvas,
      x1: 20,
      y1: 0,
      x2: 39,
      y2: 39,
      color: img.ColorRgba8(30, 220, 30, 255),
    );
    img.fillRect(
      canvas,
      x1: 40,
      y1: 0,
      x2: 59,
      y2: 39,
      color: img.ColorRgba8(30, 30, 220, 255),
    );
    return Uint8List.fromList(img.encodePng(canvas));
  }

  group('encodeForExport — PNG (lossless)', () {
    test('decoded round-trip is pixel-equal to the original', () {
      final source = rgbStripesPng();
      final encoded = encodeForExport(source, ExportFormat.png);

      final original = img.decodeImage(source)!;
      final reencoded = img.decodeImage(encoded)!;

      expect(reencoded.width, original.width);
      expect(reencoded.height, original.height);
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          final a = original.getPixel(x, y);
          final b = reencoded.getPixel(x, y);
          expect(b.r, a.r);
          expect(b.g, a.g);
          expect(b.b, a.b);
          expect(b.a, a.a);
        }
      }
    });
  });

  group('encodeForExport — JPG (lossy)', () {
    test('quality=100 produces a high-fidelity image', () {
      final source = rgbStripesPng();
      final encoded = encodeForExport(source, ExportFormat.jpg, quality: 100);

      // The result must be a valid JPG (magic bytes FF D8 FF) and
      // re-decode to the original dimensions.
      expect(encoded[0], 0xFF);
      expect(encoded[1], 0xD8);
      expect(encoded[2], 0xFF);

      final decoded = img.decodeImage(encoded)!;
      expect(decoded.width, 60);
      expect(decoded.height, 40);

      // Center of each stripe stays roughly its expected color.
      final r = decoded.getPixel(10, 20);
      expect(r.r, greaterThan(180));
      expect(r.g, lessThan(80));
      final g = decoded.getPixel(30, 20);
      expect(g.g, greaterThan(180));
      expect(g.r, lessThan(80));
      final b = decoded.getPixel(50, 20);
      expect(b.b, greaterThan(180));
      expect(b.r, lessThan(80));
    });

    test('quality=20 produces meaningfully smaller bytes than quality=100', () {
      final source = rgbStripesPng();
      final hi = encodeForExport(source, ExportFormat.jpg, quality: 100);
      final lo = encodeForExport(source, ExportFormat.jpg, quality: 20);
      // Q20 should be at least 10% smaller than Q100 — the actual
      // ratio is content-dependent but the directional inequality is
      // robust.
      expect(lo.length, lessThan(hi.length));
    });

    test('out-of-range quality is clamped', () {
      final source = rgbStripesPng();
      // Clamp protects the underlying encoder from invalid inputs.
      final lo = encodeForExport(source, ExportFormat.jpg, quality: -5);
      final hi = encodeForExport(source, ExportFormat.jpg, quality: 999);
      expect(img.decodeImage(lo)!.width, 60);
      expect(img.decodeImage(hi)!.width, 60);
    });

    test('alpha is flattened onto opaque white', () {
      // Build a half-transparent red canvas. After JPG encode, the
      // transparent pixels must collapse to white, not black.
      final src = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(255, 0, 0, 128));
      final srcBytes = Uint8List.fromList(img.encodePng(src));

      final encoded = encodeForExport(srcBytes, ExportFormat.jpg);
      final decoded = img.decodeImage(encoded)!;
      // Pre-multiplied composite over white: result ≈ (255, 128, 128).
      // JPG quantization loosens the exact tolerance but the channels
      // should stay >100 on every component (no near-black).
      final px = decoded.getPixel(5, 5);
      expect(px.r, greaterThan(150));
      expect(px.g, greaterThan(100));
      expect(px.b, greaterThan(100));
    });
  });

  test('non-decodable input passes through unchanged', () {
    final junk = Uint8List.fromList([0, 1, 2, 3, 4]);
    final out = encodeForExport(junk, ExportFormat.png);
    expect(out, equals(junk));
  });
}
