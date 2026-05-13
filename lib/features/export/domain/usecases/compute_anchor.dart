import '../entities/watermark_anchor.dart';

/// Integer pixel coordinate the rasterizer plots the text's top-left
/// corner at. Records keep the math layer dependency-free.
typedef WatermarkPosition = ({int x, int y});

/// Default margin (in source pixels) between the watermark and the
/// nearest canvas edge. Matches the PRD note "Margin = 16px from the
/// chosen edge anchor".
const int kDefaultWatermarkMargin = 16;

/// Compute the top-left pixel position of a watermark text run on a
/// canvas of size [canvasWidth] x [canvasHeight], honouring [anchor]
/// and the per-edge [margin].
///
/// Pure: no plugin/Flutter imports. Caller measures the rendered
/// [textWidth] / [textHeight] in source pixels and passes them in;
/// this keeps the function reusable from both the `image`-package
/// rasterizer and a hypothetical `dart:ui` one.
///
/// Behaviour:
/// * Left column → left edge + margin
/// * Center column → centered horizontally (margin ignored)
/// * Right column → right edge − textWidth − margin
/// * Same convention applied vertically
///
/// The returned position may be negative or extend past the canvas
/// when the text is wider/taller than the canvas (callers should
/// first shrink/ellipsize text to fit — see `applyWatermark`).
WatermarkPosition computeAnchor(
  WatermarkAnchor anchor,
  int canvasWidth,
  int canvasHeight,
  int textWidth,
  int textHeight, {
  int margin = kDefaultWatermarkMargin,
}) {
  final int x;
  switch (anchor.column) {
    case 0:
      x = margin;
      break;
    case 1:
      x = ((canvasWidth - textWidth) / 2).round();
      break;
    default: // 2 → right column
      x = canvasWidth - textWidth - margin;
      break;
  }

  final int y;
  switch (anchor.row) {
    case 0:
      y = margin;
      break;
    case 1:
      y = ((canvasHeight - textHeight) / 2).round();
      break;
    default: // 2 → bottom row
      y = canvasHeight - textHeight - margin;
      break;
  }

  return (x: x, y: y);
}
