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
  });

  final int canvasWidth;
  final int canvasHeight;
  final List<StitchRect> imageRects;
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
///
/// Returns an empty layout (`canvasWidth`/`canvasHeight` = 0,
/// `imageRects` = []) when [sizes] is empty so callers can render an
/// empty-state placeholder without special-casing.
StitchLayout computeStitchLayout({
  required List<StitchImageSize> sizes,
  required StitchMode mode,
  required double spacing,
  required double borderWidth,
}) {
  if (sizes.isEmpty) {
    return const StitchLayout(canvasWidth: 0, canvasHeight: 0, imageRects: []);
  }
  final border = math.max(0, borderWidth.round());
  final gap = math.max(0, spacing.round());

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
