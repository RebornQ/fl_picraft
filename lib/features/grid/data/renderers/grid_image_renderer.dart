import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/grid_type.dart';
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
List<Uint8List> _renderInIsolate(GridRenderRequest request) {
  final source = img.decodeImage(request.sourceBytes);
  if (source == null) {
    throw StateError('GridImageRenderer: failed to decode source image.');
  }

  final layout = computeGridLayout(
    sourceWidth: source.width,
    sourceHeight: source.height,
    type: request.gridType,
    spacing: request.spacing,
  );

  final radius = math.max(0, request.cornerRadius.round());

  final cells = <Uint8List>[];
  for (final rect in layout.rects) {
    if (rect.width <= 0 || rect.height <= 0) {
      // Degenerate cell (spacing ate the whole axis) — emit a 1x1
      // transparent placeholder so the output count still matches
      // the grid size.
      final blank = img.Image(width: 1, height: 1, numChannels: 4);
      cells.add(Uint8List.fromList(img.encodePng(blank)));
      continue;
    }
    final cropped = img.copyCrop(
      source,
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    );
    if (radius > 0) {
      _applyRoundedCorners(cropped, radius: radius);
    }
    cells.add(Uint8List.fromList(img.encodePng(cropped)));
  }
  return cells;
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
