import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/watermark_renderer.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_font_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// 200x100 solid red PNG fixture. Encoded once per test via the
  /// `image` package so the bytes are deterministic across platforms.
  Uint8List redCanvas({int width = 200, int height = 100}) {
    final canvas = img.Image(width: width, height: height);
    img.fill(canvas, color: img.ColorRgb8(220, 30, 30));
    return Uint8List.fromList(img.encodePng(canvas));
  }

  group('applyWatermark — short-circuit paths', () {
    test('returns source untouched when disabled', () async {
      final source = redCanvas();
      final out = await applyWatermark(
        source,
        WatermarkConfig.initial(), // enabled: false by default
      );
      expect(identical(out, source), isTrue);
    });

    test('returns source untouched when text is empty', () async {
      final source = redCanvas();
      final out = await applyWatermark(
        source,
        WatermarkConfig.initial().copyWith(enabled: true, text: ''),
      );
      expect(identical(out, source), isTrue);
    });

    test('returns source untouched when text is whitespace-only', () async {
      final source = redCanvas();
      final out = await applyWatermark(
        source,
        WatermarkConfig.initial().copyWith(enabled: true, text: '   '),
      );
      expect(identical(out, source), isTrue);
    });
  });

  group('applyWatermark — actually composes', () {
    test('modifies bytes when watermark is active', () async {
      final source = redCanvas();
      final out = await applyWatermark(
        source,
        WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Hi',
          anchor: WatermarkAnchor.bottomRight,
        ),
      );
      expect(out, isNot(equals(source)));
      // Decoded result still matches source dimensions.
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 200);
      expect(decoded.height, 100);
    });

    test('produces deterministic output for a fixed config', () async {
      final source = redCanvas();
      final config = WatermarkConfig.initial().copyWith(
        enabled: true,
        text: 'Fl PiCraft',
        anchor: WatermarkAnchor.bottomRight,
        opacity: 0.5,
        fontSize: WatermarkFontSize.small,
      );
      final a = await applyWatermark(source, config);
      final b = await applyWatermark(source, config);
      expect(a, equals(b));
    });

    test('different anchors paint pixels in different regions', () async {
      final source = redCanvas();
      final cfg = WatermarkConfig.initial().copyWith(
        enabled: true,
        text: 'Hi',
        fontSize: WatermarkFontSize.small,
      );
      final tl = await applyWatermark(
        source,
        cfg.copyWith(anchor: WatermarkAnchor.topLeft),
      );
      final br = await applyWatermark(
        source,
        cfg.copyWith(anchor: WatermarkAnchor.bottomRight),
      );

      final tlImg = img.decodeImage(tl)!;
      final brImg = img.decodeImage(br)!;

      // The top-left region of [tl] must contain some non-red pixels
      // (watermark glyphs), while the same region of [br] must remain
      // entirely red. The bottom-right region is the inverse.
      expect(_regionAllRed(tlImg, 16, 16, 32, 32), isFalse);
      expect(_regionAllRed(brImg, 16, 16, 32, 32), isTrue);
      expect(_regionAllRed(brImg, 150, 70, 32, 24), isFalse);
    });
  });

  group('applyWatermark — edge cases', () {
    test('text wider than canvas is shrunk and/or ellipsized', () async {
      // Narrow canvas so even arial14 won't fit "Fl PiCraft Forever".
      final source = redCanvas(width: 80, height: 60);
      final out = await applyWatermark(
        source,
        WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Fl PiCraft Forever',
          fontSize: WatermarkFontSize.large,
          anchor: WatermarkAnchor.middleCenter,
        ),
      );
      // The renderer must still produce a decodable image of the
      // same size; the important assertion is that it didn't crash
      // attempting to draw an over-wide string.
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 80);
      expect(decoded.height, 60);
    });
  });
}

/// Returns true iff every pixel inside the rectangle starting at
/// ([x],[y]) with size [w]x[h] is roughly the red fixture color. Used
/// to assert that a region has *not* been touched by the watermark.
bool _regionAllRed(img.Image image, int x, int y, int w, int h) {
  for (var dy = 0; dy < h; dy++) {
    for (var dx = 0; dx < w; dx++) {
      final px = image.getPixel(x + dx, y + dy);
      if (!_isRedish(px)) return false;
    }
  }
  return true;
}

/// Returns true iff [pixel] is roughly the red fixture color, i.e.
/// hasn't been touched by the watermark composition. Tolerates small
/// rounding deltas from re-encode.
bool _isRedish(img.Pixel pixel) {
  final r = pixel.r.toInt();
  final g = pixel.g.toInt();
  final b = pixel.b.toInt();
  return r > 180 && g < 80 && b < 80;
}
