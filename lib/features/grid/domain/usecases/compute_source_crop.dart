import 'dart:math' as math;

/// Default normalized offset for the canvas drag-select crop: centered on
/// the source image. Component values are in `[0, 1]` — `dx = 0.5, dy =
/// 0.5` puts the **center** of the crop square at the geometric center of
/// the source.
const SourceOffset kDefaultSourceOffset = SourceOffset(0.5, 0.5);

/// Default scale for the drag-select crop. `1.0` = cover-fit (the largest
/// inscribed square that fits inside the source).
const double kDefaultSourceScale = 1.0;

/// Hard lower bound for the user-facing source scale (slider / pinch).
/// Below this the crop would expose pixels outside the source, so
/// [computeSourceSquareRect] / [clampSourceScale] pin to this floor.
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
/// coordinate of the **center** of the chosen square crop, divided by
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

/// Integer-pixel square rect carved out of the source image, ready to
/// hand to `img.copyCrop`. Mirrors the shape of `GridRect` for the
/// renderer's convenience.
class SourceSquareRect {
  const SourceSquareRect({
    required this.x,
    required this.y,
    required this.side,
  });

  final int x;
  final int y;
  final int side;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SourceSquareRect &&
        other.x == x &&
        other.y == y &&
        other.side == side;
  }

  @override
  int get hashCode => Object.hash(x, y, side);

  @override
  String toString() => 'SourceSquareRect(x: $x, y: $y, side: $side)';
}

/// Clamp the user-requested [scale] to `[kMinSourceScale, kMaxSourceScale]`.
double clampSourceScale(double scale) {
  if (scale.isNaN || !scale.isFinite) return kDefaultSourceScale;
  return scale.clamp(kMinSourceScale, kMaxSourceScale).toDouble();
}

/// Compute the integer-pixel square rect of the source image that should
/// be carved out for grid splitting, given the user's normalized
/// `(offset, scale)` selection.
///
/// At [scale] = `1.0` and [offset] = `(0.5, 0.5)` the result is the
/// largest centered square inscribed in the source (the legacy
/// "center-cover" behaviour). At [scale] = `2.0` the square's side
/// shrinks to half; at [scale] = `4.0` it shrinks to a quarter. The
/// offset is auto-clamped so the rect never spills past the source's
/// bounds.
///
/// Returns `null` for degenerate inputs (zero / negative dimensions, or
/// a scale value that resolves to zero side length).
SourceSquareRect? computeSourceSquareRect({
  required int sourceWidth,
  required int sourceHeight,
  required SourceOffset offset,
  required double scale,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) return null;
  if (scale <= 0 || scale.isNaN || !scale.isFinite) return null;

  final clampedScale = clampSourceScale(scale);
  final shortSide = math.min(sourceWidth, sourceHeight);
  final sideDouble = shortSide / clampedScale;
  final side = math.max(1, sideDouble.round());
  if (side <= 0) return null;

  // Clamp the requested center so the square stays fully inside the
  // source. Same as [clampSourceOffset] but inlined to avoid a second
  // division pass — the canvas widget is the public clamp consumer.
  final halfX = sideDouble / 2 / sourceWidth;
  final halfY = sideDouble / 2 / sourceHeight;
  final clampedDx = halfX >= 0.5 ? 0.5 : offset.dx.clamp(halfX, 1 - halfX);
  final clampedDy = halfY >= 0.5 ? 0.5 : offset.dy.clamp(halfY, 1 - halfY);

  final centerX = clampedDx * sourceWidth;
  final centerY = clampedDy * sourceHeight;
  final x = (centerX - sideDouble / 2).round();
  final y = (centerY - sideDouble / 2).round();

  // Integer-rounding can drift a pixel past the bounds on extreme
  // inputs; re-clamp so `img.copyCrop` never receives an out-of-bounds
  // rect.
  final maxX = math.max(0, sourceWidth - side);
  final maxY = math.max(0, sourceHeight - side);
  final clampedX = x.clamp(0, maxX);
  final clampedY = y.clamp(0, maxY);
  return SourceSquareRect(x: clampedX, y: clampedY, side: side);
}

/// Clamp a normalized [offset] so the square crop (sized by [scale])
/// stays fully inside a source whose width-over-height aspect is
/// [sourceAspect].
///
/// Used by the canvas gesture handler to keep `state.sourceOffset` in
/// the legal range as the user drags / zooms. The renderer always
/// re-clamps via [computeSourceSquareRect] so the result remains
/// authoritative — this helper exists so the widget can update the
/// notifier with a value that already reads "intentional" instead of
/// needing the controller to silently truncate it.
SourceOffset clampSourceOffset({
  required SourceOffset offset,
  required double scale,
  required double sourceAspect,
}) {
  if (sourceAspect <= 0 || sourceAspect.isNaN || !sourceAspect.isFinite) {
    return kDefaultSourceOffset;
  }
  final clampedScale = clampSourceScale(scale);
  // shortSide / sourceWidth along x; shortSide / sourceHeight along y.
  // With aspect = w/h: when aspect >= 1 (landscape) shortSide = h,
  // so cropNormX = (h / scale) / w = 1/(scale*aspect); cropNormY = 1/scale.
  // When aspect < 1 (portrait) shortSide = w, so cropNormX = 1/scale;
  // cropNormY = aspect/scale.
  final double cropNormX;
  final double cropNormY;
  if (sourceAspect >= 1) {
    cropNormX = 1.0 / (clampedScale * sourceAspect);
    cropNormY = 1.0 / clampedScale;
  } else {
    cropNormX = 1.0 / clampedScale;
    cropNormY = sourceAspect / clampedScale;
  }
  final halfX = cropNormX / 2;
  final halfY = cropNormY / 2;
  final dx = halfX >= 0.5 ? 0.5 : offset.dx.clamp(halfX, 1 - halfX);
  final dy = halfY >= 0.5 ? 0.5 : offset.dy.clamp(halfY, 1 - halfY);
  return SourceOffset(dx.toDouble(), dy.toDouble());
}
