import 'dart:math' as math;

/// User-facing scale bounds for the nine-grid-social replacement image
/// (PRD §九宫格朋友圈 — "Scale range: 0.5x – 2x").
///
/// **Convention**: scale is **cover-relative** — `1.0` means the image
/// just fully covers the cell (no transparent borders); `2.0` means
/// the image is twice that size (zoomed in, with cropping); `0.5`
/// would mean half cover-fit, but that exposes transparent area and is
/// clamped at the next-higher safe value by [clampUserScale].
const double kMinCenterScale = 0.5;
const double kMaxCenterScale = 2;

/// Default user-facing scale — image cover-fits the cell at first.
const double kDefaultCenterScale = 1;

/// Default pan offset — image starts centered on the cell.
const CenterOffset kCenterOffsetZero = CenterOffset(0, 0);

/// Effective lower bound for user-facing scale, post-clamp. Below 1.0
/// the cell would expose transparent area, so the controller pins the
/// scale to this floor regardless of the slider position. Surfaced as
/// a helper so widget code reads intentional rather than magic-numbery.
const double kEffectiveMinCenterScale = 1;

/// Domain-only 2-D translation vector for the replacement image.
///
/// Kept as a plain class (instead of `Offset` from `dart:ui`) so the
/// `domain/` layer remains framework-free — UI code maps to/from
/// `Offset` at the presentation boundary. Units are **cell-target
/// pixels** (i.e. what the user sees / drags in the preview): `(0, 0)`
/// means the scaled image is centered on the cell; positive `dx`
/// shifts it right, positive `dy` shifts it down.
class CenterOffset {
  const CenterOffset(this.dx, this.dy);

  final double dx;
  final double dy;

  CenterOffset copyWith({double? dx, double? dy}) {
    return CenterOffset(dx ?? this.dx, dy ?? this.dy);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CenterOffset && other.dx == dx && other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'CenterOffset($dx, $dy)';
}

/// "Cover-fit" scale factor — the **absolute** multiplier on the
/// replacement image's raw dimensions that makes it fully cover
/// [cellWidth] x [cellHeight] with no transparent border.
///
/// For an image smaller than the cell on either axis, this exceeds 1.0;
/// for an image larger than the cell on both axes, this is below 1.0.
/// Used internally by the rasterizer and the preview widget to convert
/// user-facing scale (where `1.0` = cover-fit) into the absolute pixel
/// multiplier needed for `img.copyCrop` / widget sizing.
///
/// Returns `1.0` for degenerate inputs so downstream math doesn't
/// divide by zero.
double coverScaleFactor({
  required int imageWidth,
  required int imageHeight,
  required int cellWidth,
  required int cellHeight,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return 1;
  if (cellWidth <= 0 || cellHeight <= 0) return 1;
  final sx = cellWidth / imageWidth;
  final sy = cellHeight / imageHeight;
  return math.max(sx, sy);
}

/// Clamp the user-requested [scale] to `[kEffectiveMinCenterScale,
/// kMaxCenterScale]`.
///
/// PRD's edge case "Scale at 0.5x exposes transparent area | Disallow
/// — clamp scale lower bound to fit" — anything below 1.0 cover-fit
/// pins to 1.0; anything above 2.0 pins to 2.0.
double clampUserScale(double scale) {
  return scale.clamp(kEffectiveMinCenterScale, kMaxCenterScale).toDouble();
}

/// Clamp the pan offset so the scaled replacement image always covers
/// the cell — i.e. no transparent edges peek through after
/// transformation.
///
/// Given [userScale] (cover-relative, where `1.0` = cover-fit), the
/// image's effective pixel extent on the cell is
/// `imageWidth * coverScale * userScale`. The image is allowed to
/// slide along an axis by at most `(extent - cellSize) / 2` before
/// its trailing edge enters the cell.
///
/// When the effective extent is below the cell size on an axis (only
/// possible if [userScale] is itself below the cover-fit floor, which
/// [clampUserScale] prevents in normal flow), the offset on that axis
/// collapses to `0` so the image stays centered.
CenterOffset clampCenterOffset({
  required CenterOffset offset,
  required int imageWidth,
  required int imageHeight,
  required int cellWidth,
  required int cellHeight,
  required double userScale,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return kCenterOffsetZero;
  if (cellWidth <= 0 || cellHeight <= 0) return kCenterOffsetZero;
  final cover = coverScaleFactor(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
  final effective = cover * userScale;
  final scaledW = imageWidth * effective;
  final scaledH = imageHeight * effective;
  final maxDx = (scaledW - cellWidth) / 2;
  final maxDy = (scaledH - cellHeight) / 2;
  final clampedX = maxDx <= 0 ? 0.0 : offset.dx.clamp(-maxDx, maxDx);
  final clampedY = maxDy <= 0 ? 0.0 : offset.dy.clamp(-maxDy, maxDy);
  return CenterOffset(clampedX.toDouble(), clampedY.toDouble());
}

/// Result of resolving a user-requested transform against the bounds.
class ClampedCenterTransform {
  const ClampedCenterTransform({required this.scale, required this.offset});

  /// User-facing scale, clamped to `[1.0, 2.0]`.
  final double scale;

  /// Pan offset, clamped so the scaled image always covers the cell.
  final CenterOffset offset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClampedCenterTransform &&
        other.scale == scale &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(scale, offset);
}

/// Resolve a user-requested `(scale, offset)` pair into a transform
/// that satisfies the PRD's bounds.
///
/// Order of operations matters: the scale is clamped **first** because
/// the offset bounds depend on the scaled image's effective dimensions.
ClampedCenterTransform clampCenterTransform({
  required double scale,
  required CenterOffset offset,
  required int imageWidth,
  required int imageHeight,
  required int cellWidth,
  required int cellHeight,
}) {
  final clampedScale = clampUserScale(scale);
  final clampedOffset = clampCenterOffset(
    offset: offset,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    userScale: clampedScale,
  );
  return ClampedCenterTransform(scale: clampedScale, offset: clampedOffset);
}

/// Compute the rectangle (in source-image pixels) of the replacement
/// image that should be **drawn onto** the cell.
///
/// At [userScale] = `1.0` (cover-fit) the slice is the largest
/// centered rect that matches the cell's aspect ratio — same width
/// and height as the image on the cover axis. At [userScale] > `1.0`
/// the slice shrinks (we crop more aggressively).
///
/// `offset` is in **cell-target pixels** (the unit the user touches),
/// so the renderer divides by the absolute effective scale to convert
/// back to source pixels before shifting the slice.
///
/// Returns `null` when the inputs collapse to a degenerate rect.
CenterSourceRect? computeCenterSourceRect({
  required int imageWidth,
  required int imageHeight,
  required int cellWidth,
  required int cellHeight,
  required double userScale,
  required CenterOffset offset,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return null;
  if (cellWidth <= 0 || cellHeight <= 0) return null;
  if (userScale <= 0) return null;

  final cover = coverScaleFactor(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
  final effectiveScale = cover * userScale;
  if (effectiveScale <= 0) return null;

  // Slice of the source image (in source pixels) that maps to the
  // cell. At cover-fit one axis is the full image and the other is
  // cropped to match the cell's aspect ratio; at higher scale both
  // axes shrink.
  final sliceW = cellWidth / effectiveScale;
  final sliceH = cellHeight / effectiveScale;

  // The user-facing offset is in cell-target pixels. Convert to source
  // pixels and shift the slice's center accordingly.
  final centerX = imageWidth / 2 - offset.dx / effectiveScale;
  final centerY = imageHeight / 2 - offset.dy / effectiveScale;
  final x = centerX - sliceW / 2;
  final y = centerY - sliceH / 2;
  return CenterSourceRect(
    x: x.round(),
    y: y.round(),
    width: math.max(1, sliceW.round()),
    height: math.max(1, sliceH.round()),
  );
}

/// Integer-pixel rect carved out of the replacement image, in source
/// coordinates. Mirrors the shape of `GridRect` so the renderer can
/// pipe it straight into `img.copyCrop`.
class CenterSourceRect {
  const CenterSourceRect({
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
    return other is CenterSourceRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CenterSourceRect(x: $x, y: $y, w: $width, h: $height)';
}
