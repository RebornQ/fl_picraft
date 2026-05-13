import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/entities/watermark_config.dart';
import '../domain/entities/watermark_font_size.dart';
import '../domain/usecases/compute_anchor.dart';

/// Composes [config] onto [source] and returns the encoded result.
///
/// * If the watermark is disabled or its text is empty / whitespace,
///   the source bytes are returned untouched.
/// * The output format mirrors the source — PNG decodes round-trip as
///   PNG, JPG/JPEG as JPG. This keeps the pipeline format-agnostic so
///   the export task can encode once at the end.
/// * Text is drawn in white with a 2px black drop shadow at every
///   anchor so dark backgrounds remain legible (PRD §5.5 edge case
///   "Very dark backgrounds → always white + shadow").
///
/// The function is pure-Dart and isolate-safe; it makes no calls into
/// `dart:ui` so it can be invoked through `compute(...)` from the
/// export pipeline.
Future<Uint8List> applyWatermark(
  Uint8List source,
  WatermarkConfig config,
) async {
  if (!config.hasVisibleWatermark) return source;

  final decoded = img.decodeImage(source);
  if (decoded == null) {
    // Not a format we can decode — bail without modifying.
    return source;
  }

  // Pick a starting bitmap font that matches the requested size,
  // then shrink (smaller font → smaller width) until the text fits.
  var font = _fontForSize(config.fontSize.pixels);
  final width = decoded.width;
  final height = decoded.height;
  // Total horizontal padding the text must clear (margin on each
  // side, even if anchor is left/right only one side applies — we use
  // both for the shrink heuristic to leave a visual breathing room).
  final maxTextWidth = width - kDefaultWatermarkMargin * 2;

  var measured = _measureString(font, config.text);
  if (maxTextWidth <= 0) {
    // Source is narrower than the margin allotment — nothing sensible
    // to draw.
    return source;
  }
  while (measured.width > maxTextWidth && _smaller(font) != null) {
    font = _smaller(font)!;
    measured = _measureString(font, config.text);
  }

  // After shrinking to the smallest preset, ellipsize until it fits.
  var text = config.text;
  if (measured.width > maxTextWidth) {
    text = _ellipsize(text, font, maxTextWidth);
    measured = _measureString(font, text);
  }

  final pos = computeAnchor(
    config.anchor,
    width,
    height,
    measured.width,
    measured.height,
  );

  final alpha = (config.opacity.clamp(0.0, 1.0) * 255).round();

  // Black drop-shadow first (offset by +2,+2) at 70% of main alpha,
  // then the white glyph itself on top. Drawing both with the same
  // bitmap font guarantees pixel-aligned silhouettes.
  final shadowAlpha = (alpha * 0.7).round();
  img.drawString(
    decoded,
    text,
    font: font,
    x: pos.x + 2,
    y: pos.y + 2,
    color: img.ColorRgba8(0, 0, 0, shadowAlpha),
  );
  img.drawString(
    decoded,
    text,
    font: font,
    x: pos.x,
    y: pos.y,
    color: img.ColorRgba8(255, 255, 255, alpha),
  );

  // Re-encode using the same format the source arrived in.
  final encoded = _encodeMatching(source, decoded);
  return Uint8List.fromList(encoded);
}

/// Map a logical pixel size to the closest available bitmap font. The
/// `image` package only ships 14 / 24 / 48 / 96 px presets so this is
/// a nearest-match lookup, not arithmetic scaling.
img.BitmapFont _fontForSize(int pixels) {
  if (pixels <= 16) return img.arial14;
  if (pixels <= 32) return img.arial24;
  return img.arial48;
}

/// Step down to the next-smaller preset, or `null` if [font] is
/// already the smallest. Used by [applyWatermark] to auto-shrink
/// over-long strings while still respecting the
/// [kWatermarkMinShrinkPixels] floor (which arial14 already satisfies).
img.BitmapFont? _smaller(img.BitmapFont font) {
  if (identical(font, img.arial48)) return img.arial24;
  if (identical(font, img.arial24)) return img.arial14;
  return null;
}

class _Measured {
  const _Measured(this.width, this.height);
  final int width;
  final int height;
}

/// Measure a string's pixel bounds in [font] coordinates. Mirrors the
/// loop inside `image`'s own `drawString` so the position passed to
/// `drawString` lines up with the glyphs it actually renders.
///
/// Characters absent from the bitmap font (e.g. CJK glyphs, which
/// arial bitmaps don't ship) are silently skipped — same as the
/// `image` package itself. Callers expecting full Unicode coverage
/// should swap in a `dart:ui` rasterizer.
_Measured _measureString(img.BitmapFont font, String text) {
  var width = 0;
  var height = 0;
  for (final c in text.codeUnits) {
    final ch = font.characters[c];
    if (ch == null) continue;
    width += ch.xAdvance;
    final glyphHeight = ch.height + ch.yOffset;
    if (glyphHeight > height) height = glyphHeight;
  }
  if (height == 0) height = font.lineHeight;
  return _Measured(width, height);
}

/// Drop trailing characters until the run plus an ellipsis fits in
/// [maxWidth]. Falls back to returning just the ellipsis if even that
/// is too wide for the canvas.
String _ellipsize(String text, img.BitmapFont font, int maxWidth) {
  const ellipsis = '...';
  final ellipsisWidth = _measureString(font, ellipsis).width;
  if (ellipsisWidth >= maxWidth) return ellipsis;

  var working = text;
  while (working.isNotEmpty) {
    final probe = '$working$ellipsis';
    if (_measureString(font, probe).width <= maxWidth) return probe;
    working = working.substring(0, working.length - 1);
  }
  return ellipsis;
}

/// Encode [image] using the format detected from [source]'s magic
/// bytes so PNG inputs stay PNG, JPG inputs stay JPG. Falls back to
/// PNG when the format is unrecognized.
List<int> _encodeMatching(Uint8List source, img.Image image) {
  if (source.length >= 3 &&
      source[0] == 0xFF &&
      source[1] == 0xD8 &&
      source[2] == 0xFF) {
    return img.encodeJpg(image);
  }
  return img.encodePng(image);
}
