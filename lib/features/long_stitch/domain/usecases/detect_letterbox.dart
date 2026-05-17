import 'package:image/image.dart' as img;

/// Letterbox detection result. Both inset values are non-negative
/// integer pixel counts. `LetterboxInsets.zero` means "no trimming".
class LetterboxInsets {
  const LetterboxInsets({required this.topPx, required this.bottomPx});

  /// Identity value. Used by the caller when the detector falls back
  /// gracefully (e.g. all-dark frame, degenerate dimensions).
  static const LetterboxInsets zero = LetterboxInsets(topPx: 0, bottomPx: 0);

  /// Pixels to skip from the top of the source image.
  final int topPx;

  /// Pixels to skip from the bottom of the source image.
  final int bottomPx;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LetterboxInsets &&
        other.topPx == topPx &&
        other.bottomPx == bottomPx;
  }

  @override
  int get hashCode => Object.hash(topPx, bottomPx);

  @override
  String toString() => 'LetterboxInsets(top: $topPx, bottom: $bottomPx)';
}

/// Scan [image] for solid letterbox bars at the top and bottom edges.
///
/// A row is treated as "dark" when at least [rowDarkRatio] of its
/// pixels have a luminance (per the standard BT.601 weighting) below
/// [luminanceThreshold]. The first non-dark row when walking top → bottom
/// is the top crop boundary; the first non-dark row when walking
/// bottom → top is the bottom crop boundary.
///
/// Edge cases:
/// * Empty or single-row images → [LetterboxInsets.zero].
/// * Whole-image dark frames (no non-dark row exists) →
///   [LetterboxInsets.zero] (don't trim; the user sees the unmodified
///   image and gets a clear signal that the heuristic gave up).
///
/// [luminanceThreshold] is expressed in [0, 1] normalized space; the
/// default `16/255` ≈ 0.063 maps to "very near black" and matches
/// typical letterbox bars in compressed video sources.
LetterboxInsets detectLetterbox(
  img.Image image, {
  double luminanceThreshold = 16 / 255,
  double rowDarkRatio = 0.99,
}) {
  final w = image.width;
  final h = image.height;
  if (w <= 0 || h <= 1) {
    return LetterboxInsets.zero;
  }

  final minDarkPixels = (w * rowDarkRatio).ceil();

  bool rowIsDark(int y) {
    var darkCount = 0;
    for (var x = 0; x < w; x++) {
      final pixel = image.getPixel(x, y);
      // getLuminanceNormalized returns the BT.601 luminance in [0, 1]
      // space regardless of the underlying pixel format.
      if (img.getLuminanceNormalized(pixel) < luminanceThreshold) {
        darkCount++;
      }
    }
    return darkCount >= minDarkPixels;
  }

  var topPx = 0;
  while (topPx < h && rowIsDark(topPx)) {
    topPx++;
  }
  if (topPx >= h) {
    // Whole image is dark — bail out (don't trim everything).
    return LetterboxInsets.zero;
  }

  var bottomPx = 0;
  while (bottomPx < h && rowIsDark(h - 1 - bottomPx)) {
    bottomPx++;
  }
  // Guard against the unlikely case where the bottom scan exhausts
  // before meeting the top boundary (shouldn't happen because the top
  // scan already proved at least one non-dark row exists, but keep
  // the bound safe to avoid a negative usable height in the caller).
  if (topPx + bottomPx >= h) {
    return LetterboxInsets.zero;
  }
  return LetterboxInsets(topPx: topPx, bottomPx: bottomPx);
}
