import 'dart:math' as math;

import '../entities/grid_type.dart';

/// Pure rectangle in source-image coordinates. Ints because the
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

/// Result of slicing a source image into a grid of cells.
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

/// Compute the per-cell rectangles for slicing a [sourceWidth] x
/// [sourceHeight] source image into a [type] grid with [spacing]
/// pixels between adjacent cells.
///
/// Algorithm (prd L20–31):
/// ```
///   cellW = (sourceWidth  - spacing * (cols - 1)) / cols
///   cellH = (sourceHeight - spacing * (rows - 1)) / rows
///   rect[r, c] = (c * (cellW + spacing), r * (cellH + spacing), cellW, cellH)
/// ```
///
/// Edge case handling (prd L74):
/// * Integer rounding can leave a few pixels unallocated. Residual
///   pixels are distributed to the **last column** (width) and **last
///   row** (height) so the grid covers every source pixel without
///   gaps.
///
/// Returns an empty layout when the source is too small to fit even
/// one row of cells given the requested spacing — callers should
/// degrade gracefully.
GridLayout computeGridLayout({
  required int sourceWidth,
  required int sourceHeight,
  required GridType type,
  double spacing = 0,
}) {
  final rows = type.rows;
  final cols = type.cols;
  final gap = math.max(0, spacing.round());

  // Reserve gap-pixels between cells. If gaps already eat the whole
  // axis, fall back to zero-width cells so callers can still produce
  // a layout (empty rects are skipped by the renderer).
  final usableW = math.max(0, sourceWidth - gap * (cols - 1));
  final usableH = math.max(0, sourceHeight - gap * (rows - 1));

  // Use integer division so the residual is well-defined.
  final baseCellW = cols == 0 ? 0 : usableW ~/ cols;
  final baseCellH = rows == 0 ? 0 : usableH ~/ rows;
  final residualW = cols == 0 ? 0 : usableW - baseCellW * cols;
  final residualH = rows == 0 ? 0 : usableH - baseCellH * rows;

  final rects = <GridRect>[];

  // Pre-compute per-column widths and per-row heights so the residual
  // distribution lands on the last column / last row (prd L74).
  final colWidths = List<int>.generate(cols, (c) {
    return baseCellW + (c == cols - 1 ? residualW : 0);
  });
  final rowHeights = List<int>.generate(rows, (r) {
    return baseCellH + (r == rows - 1 ? residualH : 0);
  });

  // Pre-compute per-column / per-row starting offsets — cleaner than
  // accumulating inside the inner loop and keeps the math obvious.
  final colOffsets = List<int>.generate(cols, (c) {
    var x = 0;
    for (var k = 0; k < c; k++) {
      x += colWidths[k] + gap;
    }
    return x;
  });
  final rowOffsets = List<int>.generate(rows, (r) {
    var y = 0;
    for (var k = 0; k < r; k++) {
      y += rowHeights[k] + gap;
    }
    return y;
  });

  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      rects.add(
        GridRect(
          x: colOffsets[c],
          y: rowOffsets[r],
          width: colWidths[c],
          height: rowHeights[r],
        ),
      );
    }
  }

  return GridLayout(rows: rows, cols: cols, rects: rects);
}
