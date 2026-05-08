import 'dart:math' as math;

import '../entities/stitch_mode.dart';

/// Pure rectangle in canvas coordinates. Ints because the rasterizer
/// works in integer pixels.
class StitchRect {
  const StitchRect({
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
    return other is StitchRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'StitchRect(x: $x, y: $y, w: $width, h: $height)';
}

/// Result of laying out an image list onto a single canvas. The
/// rectangles are listed in the same order as the input list and are
/// inset by the outer border + corner radius offsets where applicable.
class StitchLayout {
  const StitchLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.imageRects,
    this.srcCrops,
  });

  final int canvasWidth;
  final int canvasHeight;
  final List<StitchRect> imageRects;

  /// Per-image source crop rectangles (in the source image's pixel
  /// coordinates). Same length as [imageRects] when populated; a `null`
  /// element means "use the full source image". Only the
  /// movie-subtitle layout sets this; plain vertical / horizontal leave
  /// it `null`.
  final List<StitchRect?>? srcCrops;
}

/// Single image dimension fed to [computeStitchLayout]. We accept just
/// `width` / `height` (no bytes) because the layout math is purely
/// dimensional.
class StitchImageSize {
  const StitchImageSize({required this.width, required this.height});
  final int width;
  final int height;
}

/// Compute the canvas size and per-image rectangle for the supplied
/// list of source images.
///
/// Behavior:
/// * vertical → all images scale to the **first** image's width;
///   stacked vertically with `spacing` between adjacent images.
/// * horizontal → all images scale to the **first** image's height;
///   laid out left-to-right with `spacing` between them.
/// * `borderWidth` insets the assembled image by the same amount on
///   every side (so the canvas grows by `2 * borderWidth`).
/// * When [subtitleOnlyMode] is true AND mode is vertical AND there are
///   ≥2 images, the layout switches to the movie-subtitle algorithm:
///   the first image is rendered fully and each subsequent image
///   contributes only the bottom [subtitleBandHeight] pixel band of
///   its width-normalized form. `spacing` is ignored in this mode
///   (bands butt up against each other to mimic the layered overlay
///   effect from PRD §3.3).
///
/// Returns an empty layout (`canvasWidth`/`canvasHeight` = 0,
/// `imageRects` = []) when [sizes] is empty so callers can render an
/// empty-state placeholder without special-casing.
StitchLayout computeStitchLayout({
  required List<StitchImageSize> sizes,
  required StitchMode mode,
  required double spacing,
  required double borderWidth,
  bool subtitleOnlyMode = false,
  double subtitleBandHeight = 120,
}) {
  if (sizes.isEmpty) {
    return const StitchLayout(canvasWidth: 0, canvasHeight: 0, imageRects: []);
  }
  final border = math.max(0, borderWidth.round());
  final gap = math.max(0, spacing.round());

  // Movie-subtitle is a vertical-mode flag-overlay (see PRD §3.3 and
  // task `05-08-movie-subtitle`). With <2 images there is nothing to
  // overlay, so we degrade to plain vertical silently.
  if (subtitleOnlyMode && mode == StitchMode.vertical && sizes.length >= 2) {
    return _layoutMovieSubtitle(
      sizes,
      border: border,
      bandHeight: math.max(1, subtitleBandHeight.round()),
    );
  }

  return switch (mode) {
    StitchMode.vertical => _layoutVertical(sizes, border: border, gap: gap),
    StitchMode.horizontal => _layoutHorizontal(sizes, border: border, gap: gap),
  };
}

StitchLayout _layoutVertical(
  List<StitchImageSize> sizes, {
  required int border,
  required int gap,
}) {
  final targetWidth = sizes.first.width;
  if (targetWidth <= 0) {
    return const StitchLayout(canvasWidth: 0, canvasHeight: 0, imageRects: []);
  }
  final rects = <StitchRect>[];
  var cursorY = border;
  for (var i = 0; i < sizes.length; i++) {
    final s = sizes[i];
    final scaledHeight = s.height <= 0
        ? 0
        : math.max(1, (s.height * targetWidth / s.width).round());
    rects.add(
      StitchRect(
        x: border,
        y: cursorY,
        width: targetWidth,
        height: scaledHeight,
      ),
    );
    cursorY += scaledHeight;
    if (i != sizes.length - 1) cursorY += gap;
  }
  return StitchLayout(
    canvasWidth: targetWidth + 2 * border,
    canvasHeight: cursorY + border,
    imageRects: rects,
  );
}

StitchLayout _layoutHorizontal(
  List<StitchImageSize> sizes, {
  required int border,
  required int gap,
}) {
  final targetHeight = sizes.first.height;
  if (targetHeight <= 0) {
    return const StitchLayout(canvasWidth: 0, canvasHeight: 0, imageRects: []);
  }
  final rects = <StitchRect>[];
  var cursorX = border;
  for (var i = 0; i < sizes.length; i++) {
    final s = sizes[i];
    final scaledWidth = s.width <= 0
        ? 0
        : math.max(1, (s.width * targetHeight / s.height).round());
    rects.add(
      StitchRect(
        x: cursorX,
        y: border,
        width: scaledWidth,
        height: targetHeight,
      ),
    );
    cursorX += scaledWidth;
    if (i != sizes.length - 1) cursorX += gap;
  }
  return StitchLayout(
    canvasWidth: cursorX + border,
    canvasHeight: targetHeight + 2 * border,
    imageRects: rects,
  );
}

/// Movie-subtitle layout (PRD §3.3). All images width-normalize to the
/// first image's width. The first image renders fully; each subsequent
/// image contributes only its bottom [bandHeight] pixel band (in the
/// scaled coordinate space).
///
/// Algorithm:
/// ```
///   targetW   = sizes[0].width
///   H_full    = sizes[0].height (already at targetW so no rescale)
///   H_band    = min(scaledHeight_i, bandHeight)  for i ≥ 1
///   canvasW   = targetW
///   canvasH   = H_full + Σ(H_band_i)
/// ```
/// Each subsequent image's `srcCrop` selects the bottom slice of the
/// **source** image whose height ratio matches the dest band's ratio
/// inside the scaled image. The renderer then crops + scales to the
/// dest rect.
StitchLayout _layoutMovieSubtitle(
  List<StitchImageSize> sizes, {
  required int border,
  required int bandHeight,
}) {
  final targetWidth = sizes.first.width;
  if (targetWidth <= 0) {
    return const StitchLayout(canvasWidth: 0, canvasHeight: 0, imageRects: []);
  }

  final rects = <StitchRect>[];
  final crops = <StitchRect?>[];
  var cursorY = border;

  // First image renders fully (no source crop).
  final first = sizes.first;
  final firstScaledHeight = first.height <= 0
      ? 0
      : math.max(1, (first.height * targetWidth / first.width).round());
  rects.add(
    StitchRect(
      x: border,
      y: cursorY,
      width: targetWidth,
      height: firstScaledHeight,
    ),
  );
  crops.add(null);
  cursorY += firstScaledHeight;

  // Subsequent images contribute only their bottom band.
  for (var i = 1; i < sizes.length; i++) {
    final s = sizes[i];
    if (s.width <= 0 || s.height <= 0) {
      // Degenerate source — emit a zero-height band so indices stay
      // aligned and the renderer can skip it.
      rects.add(
        StitchRect(x: border, y: cursorY, width: targetWidth, height: 0),
      );
      crops.add(const StitchRect(x: 0, y: 0, width: 0, height: 0));
      continue;
    }
    final scaledHeight = math.max(
      1,
      (s.height * targetWidth / s.width).round(),
    );
    // Effective band height in scaled-canvas coords. If the scaled
    // image is shorter than the requested band, we use its full height
    // (PRD edge case: "Image height < band height").
    final effBand = math.min(scaledHeight, bandHeight);
    // Map the effective band back to source pixels.
    final srcCropHeight = math
        .max(1, (effBand * s.height / scaledHeight).round())
        .clamp(1, s.height);
    final srcCropY = (s.height - srcCropHeight).clamp(0, s.height - 1);

    rects.add(
      StitchRect(x: border, y: cursorY, width: targetWidth, height: effBand),
    );
    crops.add(
      StitchRect(x: 0, y: srcCropY, width: s.width, height: srcCropHeight),
    );
    cursorY += effBand;
  }

  return StitchLayout(
    canvasWidth: targetWidth + 2 * border,
    canvasHeight: cursorY + border,
    imageRects: rects,
    srcCrops: crops,
  );
}
