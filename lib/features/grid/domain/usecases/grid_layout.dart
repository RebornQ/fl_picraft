import 'dart:math' as math;

import '../entities/grid_type.dart';

/// Pure rectangle in canvas-space coordinates. Ints because the
/// rasterizer works in integer pixels.
class GridRect {
  const GridRect({
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
    return other is GridRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'GridRect(x: $x, y: $y, w: $width, h: $height)';
}

/// Result of slicing the canvas into a grid of equal-size square cells.
///
/// [rects] is in row-major order (left-to-right, top-to-bottom) so
/// callers iterating over it produce files in the order users expect
/// (e.g. for 3x3 → top-row left, top-row middle, top-row right, ...).
class GridLayout {
  const GridLayout({
    required this.rows,
    required this.cols,
    required this.rects,
  });

  final int rows;
  final int cols;
  final List<GridRect> rects;

  int get cellCount => rects.length;
}

/// Compute the per-cell rectangles for slicing a canvas of size
/// `cols * cellSide + spacing * (cols - 1)` × `rows * cellSide +
/// spacing * (rows - 1)` into uniform `cellSide × cellSide` cells.
///
/// Every cell is a **square** of the same edge length [cellSide], laid
/// out row-major on a regular grid with [spacing] pixels between
/// adjacent cells. There is no residual distribution — the caller is
/// expected to have already chosen a cellSide that fits its source crop
/// (the renderer derives it from `computeSourceCropRect`).
///
/// ```
///   gap = max(0, spacing.round())
///   rect[r, c] = (c * (cellSide + gap), r * (cellSide + gap), cellSide, cellSide)
/// ```
///
/// Returns an empty (all-zero rects) layout when [cellSide] is `<= 0`
/// so callers can degrade gracefully.
GridLayout computeGridLayout({
  required int cellSide,
  required GridType type,
  double spacing = 0,
}) {
  final rows = type.rows;
  final cols = type.cols;
  final gap = math.max(0, spacing.round());
  final side = math.max(0, cellSide);

  final rects = <GridRect>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      rects.add(
        GridRect(
          x: c * (side + gap),
          y: r * (side + gap),
          width: side,
          height: side,
        ),
      );
    }
  }

  return GridLayout(rows: rows, cols: cols, rects: rects);
}
