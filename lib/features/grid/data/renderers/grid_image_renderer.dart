import 'dart:developer' show Timeline;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_center_transform.dart';
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
    final centerBytes = req.centerImageBytes;
    if (centerBytes != null &&
        centerBytes.length >= kIsolateSourceByteThreshold) {
      return true;
    }
    return false;
  }
}

/// Index of the center cell in a row-major 3x3 layout. Surfaced as a
/// named constant so the social-mode branching reads intentional rather
/// than magic-numbery.
const int kCenterCellIndex = 4;

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

  // PRD §4.2 algorithm step 1: "Crop source to square (longest side =
  // min(srcW, srcH); center crop)" — only applied when the request
  // explicitly opts into the nine-grid-social pipeline so the regular
  // 3x3 mode keeps showing the full source as before.
  final source = request.nineGridSocialMode
      ? _centerCropToSquare(decoded)
      : decoded;

  final layout = computeGridLayout(
    sourceWidth: source.width,
    sourceHeight: source.height,
    type: request.gridType,
    spacing: request.spacing,
  );

  final radius = math.max(0, request.cornerRadius.round());

  // Decode the center-replacement image **once**, only when the
  // request asks for it. Falls back to no-replacement on a bad decode
  // so a corrupt center image doesn't tank the whole export.
  img.Image? centerImage;
  if (request.hasCenterReplacement) {
    centerImage = img.decodeImage(request.centerImageBytes!);
  }

  final cells = <Uint8List>[];
  Timeline.startSync('grid.cell-render');
  try {
    for (var i = 0; i < layout.rects.length; i++) {
      final rect = layout.rects[i];
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
      img.Image cell;
      if (centerImage != null && i == kCenterCellIndex) {
        cell = _composeCenterCell(
          center: centerImage,
          cellWidth: rect.width,
          cellHeight: rect.height,
          scale: request.centerScale,
          offset: request.centerOffset,
        );
      } else {
        cell = img.copyCrop(
          source,
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        );
      }
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

/// Returns a centred minimum-side square crop of [src]. Used by the
/// nine-grid-social pipeline (PRD §4.2 step 1) so the resulting 9 cells
/// are themselves squares regardless of the original aspect ratio.
img.Image _centerCropToSquare(img.Image src) {
  if (src.width == src.height) return src;
  final shortSide = math.min(src.width, src.height);
  final cropX = (src.width - shortSide) ~/ 2;
  final cropY = (src.height - shortSide) ~/ 2;
  return img.copyCrop(
    src,
    x: cropX,
    y: cropY,
    width: shortSide,
    height: shortSide,
  );
}

/// Crop the replacement [center] image with the user-controlled
/// `(scale, offset)` transform and resize it to the cell dimensions.
///
/// The math lives in `domain/usecases/compute_center_transform.dart`
/// so the same clamping rules drive both the preview gesture overlay
/// and the rasterizer here.
img.Image _composeCenterCell({
  required img.Image center,
  required int cellWidth,
  required int cellHeight,
  required double scale,
  required CenterOffset offset,
}) {
  final clamped = clampCenterTransform(
    scale: scale,
    offset: offset,
    imageWidth: center.width,
    imageHeight: center.height,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
  final sourceRect = computeCenterSourceRect(
    imageWidth: center.width,
    imageHeight: center.height,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    userScale: clamped.scale,
    offset: clamped.offset,
  );
  if (sourceRect == null) {
    // Degenerate transform — emit a transparent cell so the output
    // count still matches the 9-cell expectation.
    return img.Image(width: cellWidth, height: cellHeight, numChannels: 4);
  }
  // Clamp the crop rect to the source image bounds. `clampCenterOffset`
  // already guarantees the slice stays inside the image (the offset
  // can never push it past the edge once the scale floor is enforced),
  // but the integer rounding inside `computeCenterSourceRect` can drift
  // by one pixel on degenerate inputs.
  final clampedX = sourceRect.x.clamp(0, math.max(0, center.width - 1)).toInt();
  final clampedY = sourceRect.y
      .clamp(0, math.max(0, center.height - 1))
      .toInt();
  final clampedW = sourceRect.width.clamp(1, center.width - clampedX).toInt();
  final clampedH = sourceRect.height.clamp(1, center.height - clampedY).toInt();
  final cropped = img.copyCrop(
    center,
    x: clampedX,
    y: clampedY,
    width: clampedW,
    height: clampedH,
  );
  if (cropped.width == cellWidth && cropped.height == cellHeight) {
    return cropped;
  }
  return img.copyResize(
    cropped,
    width: cellWidth,
    height: cellHeight,
    interpolation: img.Interpolation.cubic,
  );
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
