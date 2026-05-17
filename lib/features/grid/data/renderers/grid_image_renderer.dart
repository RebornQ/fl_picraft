import 'dart:developer' show Timeline;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_source_crop.dart';
import '../../domain/usecases/grid_layout.dart';
import '../../domain/usecases/grid_render_request.dart';

/// Above this many cells (or any source > 2MP) the renderer runs
/// through [compute] to keep the UI isolate responsive. Matches the
/// long-stitch thresholds so the perf budget stays consistent.
@visibleForTesting
const int kIsolateCellCountThreshold = 9;
@visibleForTesting
const int kIsolateSourceByteThreshold = 2 * 1024 * 1024;

/// Renders the grid-editor state into one PNG per cell.
///
/// Lives under `data/` because it depends on the pure-Dart `image`
/// package. The layout math sits in `domain/usecases/grid_layout.dart`
/// and is reused both here and by the preview widgets.
///
/// Isolate-safe: this file (and the top-level [_renderInIsolate] entry
/// point it dispatches to) imports nothing from `dart:ui` so it can
/// run via [compute] without breaking the way `TextPainter`-style APIs
/// do.
class GridImageRenderer {
  const GridImageRenderer();

  /// Render every cell as a separate PNG. Returned list is in
  /// row-major order (left-to-right, top-to-bottom) matching
  /// [computeGridLayout].
  Future<List<Uint8List>> render(GridRenderRequest request) async {
    if (request.sourceBytes.isEmpty) {
      throw StateError('GridImageRenderer: source bytes are empty.');
    }
    if (_shouldUseIsolate(request)) {
      try {
        return await compute(_renderInIsolate, request);
      } catch (_) {
        // Fallback for pure-Dart unit tests where the Flutter binding
        // is unavailable (compute throws). The synchronous path
        // produces identical bytes.
        return _renderInIsolate(request);
      }
    }
    return _renderInIsolate(request);
  }

  bool _shouldUseIsolate(GridRenderRequest req) {
    if (req.gridType.cellCount >= kIsolateCellCountThreshold) return true;
    if (req.sourceBytes.length >= kIsolateSourceByteThreshold) return true;
    return false;
  }
}

/// Top-level (i.e. non-closure) render function so it can be the
/// entry point for [compute].
///
/// Wraps the per-cell loop in `Timeline.startSync('grid.cell-render')`
/// and each cell's PNG encode in `Timeline.startSync('grid.encode')` so
/// DevTools' performance overlay shows where time goes when a grid
/// export feels slow.
List<Uint8List> _renderInIsolate(GridRenderRequest request) {
  final decoded = img.decodeImage(request.sourceBytes);
  if (decoded == null) {
    throw StateError('GridImageRenderer: failed to decode source image.');
  }

  final rows = request.gridType.rows;
  final cols = request.gridType.cols;
  final targetAspect = cols / rows;

  // PRD ST-C R-RENDER-01 / 05-17 Subtask B: crop the source to a
  // user-selected rectangle of aspect `cols / rows` **first**, then
  // slice that rectangle into uniform squares. Default offset / scale
  // → centered cover-fit crop.
  final cropped = _cropToSelectedRect(
    decoded,
    offset: request.sourceOffset,
    scale: request.sourceScale,
    targetAspect: targetAspect,
  );

  // Derive the square cellSide from the cropped width and the spacing
  // budget. We use the width-axis math because the crop's aspect is
  // exactly `cols / rows`, so cropW / cols == cropH / rows
  // (sub-pixel rounding aside). Reserve `gap * (cols - 1)` pixels
  // between cells before integer-dividing.
  final gap = math.max(0, request.spacing.round());
  final usableW = math.max(0, cropped.width - gap * (cols - 1));
  final cellSide = cols == 0 ? 0 : usableW ~/ cols;
  final layout = computeGridLayout(
    cellSide: cellSide,
    type: request.gridType,
    spacing: request.spacing,
  );

  final radius = math.max(0, request.cornerRadius.round());

  final cells = <Uint8List>[];
  Timeline.startSync('grid.cell-render');
  try {
    for (final rect in layout.rects) {
      if (rect.width <= 0 || rect.height <= 0) {
        // Degenerate cell (spacing ate the whole axis) — emit a 1x1
        // transparent placeholder so the output count still matches
        // the grid size.
        final blank = img.Image(width: 1, height: 1, numChannels: 4);
        Timeline.startSync('grid.encode');
        try {
          cells.add(Uint8List.fromList(img.encodePng(blank)));
        } finally {
          Timeline.finishSync();
        }
        continue;
      }
      // Map canvas-space rect → cropped-source-space rect 1:1 (the
      // layout was built against the cropped source's own dimensions).
      // Clamp width/height defensively in case the residual at the
      // bottom-right edge would step a pixel past the cropped bounds.
      final sx = rect.x;
      final sy = rect.y;
      final sw = math.min(rect.width, cropped.width - sx);
      final sh = math.min(rect.height, cropped.height - sy);
      if (sw <= 0 || sh <= 0) {
        final blank = img.Image(
          width: math.max(1, rect.width),
          height: math.max(1, rect.height),
          numChannels: 4,
        );
        Timeline.startSync('grid.encode');
        try {
          cells.add(Uint8List.fromList(img.encodePng(blank)));
        } finally {
          Timeline.finishSync();
        }
        continue;
      }
      final cell = img.copyCrop(cropped, x: sx, y: sy, width: sw, height: sh);
      if (radius > 0) {
        _applyRoundedCorners(cell, radius: radius);
      }
      Timeline.startSync('grid.encode');
      try {
        cells.add(Uint8List.fromList(img.encodePng(cell)));
      } finally {
        Timeline.finishSync();
      }
    }
  } finally {
    Timeline.finishSync();
  }
  return cells;
}

/// Crop [src] to the rectangular region picked by the user
/// (`offset` / `scale`) with the requested [targetAspect]. Default
/// `offset = (0.5, 0.5)` / `scale = 1.0` reproduces a centered
/// cover-fit crop of aspect [targetAspect].
img.Image _cropToSelectedRect(
  img.Image src, {
  required SourceOffset offset,
  required double scale,
  required double targetAspect,
}) {
  final rect = computeSourceCropRect(
    sourceWidth: src.width,
    sourceHeight: src.height,
    offset: offset,
    scale: scale,
    targetAspect: targetAspect,
  );
  if (rect == null) return src;
  // Defensive: the math should already guarantee in-bounds, but integer
  // rounding on degenerate inputs (1x1, etc.) can drift by a pixel.
  final maxW = math.max(0, src.width - rect.x);
  final maxH = math.max(0, src.height - rect.y);
  final w = math.min(rect.width, maxW);
  final h = math.min(rect.height, maxH);
  if (w <= 0 || h <= 0) return src;
  return img.copyCrop(src, x: rect.x, y: rect.y, width: w, height: h);
}

/// Punch transparent pixels outside the inscribed rounded-rect so the
/// final cell renders with the requested corner radius. Mirrors the
/// helper used by the long-stitch renderer.
void _applyRoundedCorners(img.Image canvas, {required int radius}) {
  final w = canvas.width;
  final h = canvas.height;
  final r = math.min(radius, math.min(w, h) ~/ 2);
  if (r <= 0) return;

  for (var y = 0; y < r; y++) {
    for (var x = 0; x < r; x++) {
      final dx = r - x;
      final dy = r - y;
      if (dx * dx + dy * dy > r * r) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
        canvas.setPixelRgba(w - 1 - x, y, 0, 0, 0, 0);
        canvas.setPixelRgba(x, h - 1 - y, 0, 0, 0, 0);
        canvas.setPixelRgba(w - 1 - x, h - 1 - y, 0, 0, 0, 0);
      }
    }
  }
}
