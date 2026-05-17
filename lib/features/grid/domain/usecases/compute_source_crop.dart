import 'dart:math' as math;

/// Default normalized offset for the canvas drag-select crop: centered on
/// the source image. Component values are in `[0, 1]` — `dx = 0.5, dy =
/// 0.5` puts the **center** of the crop rectangle at the geometric center
/// of the source.
const SourceOffset kDefaultSourceOffset = SourceOffset(0.5, 0.5);

/// Default scale for the drag-select crop. `1.0` = cover-fit (the largest
/// inscribed rectangle of the target aspect that fits inside the source).
const double kDefaultSourceScale = 1.0;

/// Hard lower bound for the user-facing source scale (slider / pinch).
/// Below this the crop would expose pixels outside the source, so
/// [computeSourceCropRect] / [clampSourceScale] pin to this floor.
const double kMinSourceScale = 1.0;

/// Hard upper bound for the user-facing source scale (PRD ST-C, R-DRAG-02).
const double kMaxSourceScale = 4.0;

/// Domain-only 2-D normalized offset for the canvas drag-select crop.
///
/// Kept as a plain class (instead of `Offset` from `dart:ui`) so the
/// `domain/` layer stays framework-free — the presentation layer maps to
/// / from `Offset` at the widget boundary. Components are **normalized**
/// to `[0, 1]` where `(0, 0)` is the source's top-left corner and `(1,
/// 1)` is the bottom-right. Conceptually this is the source-pixel
/// coordinate of the **center** of the chosen crop rectangle, divided by
/// the source's dimensions.
class SourceOffset {
  const SourceOffset(this.dx, this.dy);

  final double dx;
  final double dy;

  SourceOffset copyWith({double? dx, double? dy}) {
    return SourceOffset(dx ?? this.dx, dy ?? this.dy);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SourceOffset && other.dx == dx && other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'SourceOffset($dx, $dy)';
}

/// Integer-pixel rectangle carved out of the source image, ready to hand
/// to `img.copyCrop`. The rect's aspect ratio matches the editor's
/// requested `targetAspect` (= grid `cols / rows`), so a square crop is
/// the special case `targetAspect == 1.0`.
class SourceCropRect {
  const SourceCropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SourceCropRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'SourceCropRect(x: $x, y: $y, w: $width, h: $height)';
}

/// Clamp the user-requested [scale] to `[kMinSourceScale, kMaxSourceScale]`.
double clampSourceScale(double scale) {
  if (scale.isNaN || !scale.isFinite) return kDefaultSourceScale;
  return scale.clamp(kMinSourceScale, kMaxSourceScale).toDouble();
}

/// Compute the largest inscribed rectangle of aspect [targetAspect] inside
/// a `sourceWidth × sourceHeight` source, divided by [scale]. Returns
/// `(baseW, baseH)` at scale = 1 — callers divide by `scale` to obtain the
/// shrunk crop size.
({double baseW, double baseH}) _inscribedRectAtCoverFit({
  required int sourceWidth,
  required int sourceHeight,
  required double targetAspect,
}) {
  final sourceAspect = sourceWidth / sourceHeight;
  if (sourceAspect >= targetAspect) {
    // Source is wider (relative to target) → height-bound.
    final baseH = sourceHeight.toDouble();
    final baseW = baseH * targetAspect;
    return (baseW: baseW, baseH: baseH);
  }
  // Source is taller (relative to target) → width-bound.
  final baseW = sourceWidth.toDouble();
  final baseH = baseW / targetAspect;
  return (baseW: baseW, baseH: baseH);
}

/// Compute the integer-pixel rectangle of the source image that should be
/// carved out for grid splitting, given the user's normalized
/// `(offset, scale)` selection and the editor's `targetAspect` (= grid
/// `cols / rows`).
///
/// At [scale] = `1.0` and [offset] = `(0.5, 0.5)` the result is the
/// largest centered rectangle of aspect [targetAspect] inscribed in the
/// source. At [scale] = `2.0` both width and height shrink to half; at
/// [scale] = `4.0` to a quarter. The offset is auto-clamped so the rect
/// never spills past the source's bounds.
///
/// When [targetAspect] is `1.0` (the default) the result reduces to a
/// centered square — the legacy behaviour callers had before subtask B.
///
/// Returns `null` for degenerate inputs (zero / negative dimensions, or a
/// scale value that resolves to zero side length).
SourceCropRect? computeSourceCropRect({
  required int sourceWidth,
  required int sourceHeight,
  required SourceOffset offset,
  required double scale,
  double targetAspect = 1.0,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) return null;
  if (scale <= 0 || scale.isNaN || !scale.isFinite) return null;
  if (targetAspect <= 0 || targetAspect.isNaN || !targetAspect.isFinite) {
    return null;
  }

  final clampedScale = clampSourceScale(scale);
  final base = _inscribedRectAtCoverFit(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    targetAspect: targetAspect,
  );
  final widthDouble = base.baseW / clampedScale;
  final heightDouble = base.baseH / clampedScale;
  final width = math.max(1, widthDouble.round());
  final height = math.max(1, heightDouble.round());
  if (width <= 0 || height <= 0) return null;

  // Clamp the requested center so the rect stays fully inside the source.
  final halfX = widthDouble / 2 / sourceWidth;
  final halfY = heightDouble / 2 / sourceHeight;
  final clampedDx = halfX >= 0.5 ? 0.5 : offset.dx.clamp(halfX, 1 - halfX);
  final clampedDy = halfY >= 0.5 ? 0.5 : offset.dy.clamp(halfY, 1 - halfY);

  final centerX = clampedDx * sourceWidth;
  final centerY = clampedDy * sourceHeight;
  final x = (centerX - widthDouble / 2).round();
  final y = (centerY - heightDouble / 2).round();

  // Integer-rounding can drift a pixel past the bounds on extreme inputs;
  // re-clamp so `img.copyCrop` never receives an out-of-bounds rect.
  final maxX = math.max(0, sourceWidth - width);
  final maxY = math.max(0, sourceHeight - height);
  final clampedX = x.clamp(0, maxX);
  final clampedY = y.clamp(0, maxY);
  return SourceCropRect(x: clampedX, y: clampedY, width: width, height: height);
}

/// Clamp a normalized [offset] so the crop rectangle (sized by [scale]
/// and shaped by [targetAspect]) stays fully inside a source whose
/// width-over-height aspect is [sourceAspect].
///
/// Used by the canvas gesture handler to keep `state.sourceOffset` in
/// the legal range as the user drags / zooms. The renderer always
/// re-clamps via [computeSourceCropRect] so the result remains
/// authoritative — this helper exists so the widget can update the
/// notifier with a value that already reads "intentional" instead of
/// needing the controller to silently truncate it.
SourceOffset clampSourceOffset({
  required SourceOffset offset,
  required double scale,
  required double sourceAspect,
  double targetAspect = 1.0,
}) {
  if (sourceAspect <= 0 || sourceAspect.isNaN || !sourceAspect.isFinite) {
    return kDefaultSourceOffset;
  }
  if (targetAspect <= 0 || targetAspect.isNaN || !targetAspect.isFinite) {
    return kDefaultSourceOffset;
  }
  final clampedScale = clampSourceScale(scale);
  // Inscribed rect at scale=1: width / height in normalized source coords.
  //   sourceAspect >= targetAspect → height-bound
  //     baseW = sourceH * targetAspect = sourceW * (targetAspect / sourceAspect)
  //     baseH = sourceH
  //     cropNormX = baseW / sourceW = targetAspect / sourceAspect
  //     cropNormY = baseH / sourceH = 1
  //   sourceAspect <  targetAspect → width-bound
  //     baseW = sourceW
  //     baseH = sourceW / targetAspect
  //     cropNormX = 1
  //     cropNormY = sourceAspect / targetAspect
  // Then divide by clampedScale to account for zoom.
  final double cropNormX;
  final double cropNormY;
  if (sourceAspect >= targetAspect) {
    cropNormX = targetAspect / (sourceAspect * clampedScale);
    cropNormY = 1.0 / clampedScale;
  } else {
    cropNormX = 1.0 / clampedScale;
    cropNormY = sourceAspect / (targetAspect * clampedScale);
  }
  final halfX = cropNormX / 2;
  final halfY = cropNormY / 2;
  final dx = halfX >= 0.5 ? 0.5 : offset.dx.clamp(halfX, 1 - halfX);
  final dy = halfY >= 0.5 ? 0.5 : offset.dy.clamp(halfY, 1 - halfY);
  return SourceOffset(dx.toDouble(), dy.toDouble());
}
