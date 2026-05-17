import 'dart:developer' show Timeline;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/stitch_mode.dart';
import '../../domain/usecases/detect_letterbox.dart';
import '../../domain/usecases/stitch_layout.dart';
import '../../domain/usecases/stitch_render_request.dart';

/// Above this many images (or any single image > 2MP) the renderer
/// runs through [compute] to keep the UI isolate responsive. The
/// PRD's perf budget is "20 images vertical stitch < 5s on a mid-tier
/// device" and "preview slider response < 100ms" — with native widgets
/// driving the preview the heavy lift is only the export call here.
@visibleForTesting
const int kIsolateImageCountThreshold = 5;
@visibleForTesting
const int kIsolatePixelThreshold = 2 * 1000 * 1000;

/// Renders the editor state to a single bitmap.
///
/// Lives under `data/` because it depends on the `image` package. The
/// pure layout math sits in `domain/usecases/stitch_layout.dart` and is
/// reused both here and by the preview widgets.
class StitchImageRenderer {
  const StitchImageRenderer();

  Future<Uint8List> render(StitchRenderRequest request) async {
    if (request.imageBytes.isEmpty) {
      throw StateError('Cannot render an empty image list.');
    }
    if (_shouldUseIsolate(request)) {
      try {
        return await compute(_renderInIsolate, request);
      } catch (_) {
        // Fallback for pure-Dart unit tests where Flutter binding is
        // unavailable (compute throws). The synchronous path produces
        // the same bytes.
        return _renderInIsolate(request);
      }
    }
    return _renderInIsolate(request);
  }

  bool _shouldUseIsolate(StitchRenderRequest req) {
    if (req.imageBytes.length >= kIsolateImageCountThreshold) return true;
    // We don't have decoded sizes here so use byte-length as a coarse
    // proxy — anything >2MB on disk is a strong hint we'll cross the
    // 2MP bar after decoding.
    for (final b in req.imageBytes) {
      if (b.length >= 2 * 1024 * 1024) return true;
    }
    return false;
  }
}

/// Top-level (i.e. non-closure) render function so it can be the
/// entry point for [compute].
///
/// Wraps each phase in `Timeline.startSync` / `finishSync` so DevTools'
/// performance overlay shows three nested bars (`stitch.decode`,
/// `stitch.compose`, `stitch.encode`) — turning the "where do the
/// 5 seconds go" question into a one-glance answer.
Uint8List _renderInIsolate(StitchRenderRequest request) {
  Timeline.startSync('stitch.decode');
  final decoded = <img.Image>[];
  try {
    for (final bytes in request.imageBytes) {
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw StateError(
          'StitchImageRenderer: failed to decode one of the input images.',
        );
      }
      decoded.add(image);
    }
  } finally {
    Timeline.finishSync();
  }

  Timeline.startSync('stitch.compose');
  late final img.Image canvas;
  try {
    // Auto-trim letterbox bars before layout when the request opts in
    // and the movie-subtitle path is going to be taken. Detection runs
    // inside the same isolate that already decoded the bytes — no
    // extra hop, no double-decode.
    List<LetterboxInsets>? letterboxInsets;
    if (request.autoTrimBlackBars &&
        request.subtitleOnlyMode &&
        request.mode == StitchMode.vertical &&
        decoded.length >= 2) {
      Timeline.startSync('stitch.letterbox');
      try {
        letterboxInsets = [for (final d in decoded) detectLetterbox(d)];
      } finally {
        Timeline.finishSync();
      }
    }

    final layout = computeStitchLayout(
      sizes: [
        for (final d in decoded)
          StitchImageSize(width: d.width, height: d.height),
      ],
      mode: request.mode,
      spacing: request.spacing,
      borderWidth: request.borderWidth,
      subtitleOnlyMode: request.subtitleOnlyMode,
      subtitleBandHeight: request.subtitleBandHeight,
      letterboxInsets: letterboxInsets,
    );

    if (layout.canvasWidth == 0 || layout.canvasHeight == 0) {
      throw StateError('StitchImageRenderer: degenerate canvas size.');
    }

    // White background so JPEG encodes opaquely; corner-radius cropping
    // re-introduces alpha pixels later.
    canvas = img.Image(
      width: layout.canvasWidth,
      height: layout.canvasHeight,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

    for (var i = 0; i < decoded.length; i++) {
      final src = decoded[i];
      final rect = layout.imageRects[i];
      if (rect.width <= 0 || rect.height <= 0) continue;
      // Movie-subtitle mode supplies a per-image source crop for indices
      // ≥1; null falls through to "use the full source".
      final srcCrop = layout.srcCrops?[i];
      final cropped = (srcCrop == null)
          ? src
          : img.copyCrop(
              src,
              x: srcCrop.x,
              y: srcCrop.y,
              width: math.max(1, srcCrop.width),
              height: math.max(1, srcCrop.height),
            );
      final scaled =
          (cropped.width == rect.width && cropped.height == rect.height)
          ? cropped
          : img.copyResize(
              cropped,
              width: rect.width,
              height: rect.height,
              interpolation: img.Interpolation.cubic,
            );
      img.compositeImage(
        canvas,
        scaled,
        dstX: rect.x,
        dstY: rect.y,
        dstW: rect.width,
        dstH: rect.height,
        blend: img.BlendMode.alpha,
      );
    }

    if (request.borderWidth > 0) {
      _drawOuterBorder(
        canvas,
        thickness: request.borderWidth.round(),
        argb: request.borderColorArgb,
      );
    }

    if (request.cornerRadius > 0) {
      _applyRoundedCorners(canvas, radius: request.cornerRadius.round());
    }
  } finally {
    Timeline.finishSync();
  }

  Timeline.startSync('stitch.encode');
  try {
    switch (request.format) {
      case StitchExportFormat.png:
        return Uint8List.fromList(img.encodePng(canvas));
      case StitchExportFormat.jpeg:
        // JPG can't carry alpha. Flatten onto white so the corner-radius
        // cutouts don't leak black.
        final flat = img.Image(
          width: canvas.width,
          height: canvas.height,
          numChannels: 3,
        );
        img.fill(flat, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(flat, canvas);
        return Uint8List.fromList(
          img.encodeJpg(flat, quality: request.jpegQuality.clamp(1, 100)),
        );
    }
  } finally {
    Timeline.finishSync();
  }
}

void _drawOuterBorder(
  img.Image canvas, {
  required int thickness,
  required int argb,
}) {
  final color = _argbToColor(argb);
  // Top
  img.fillRect(
    canvas,
    x1: 0,
    y1: 0,
    x2: canvas.width - 1,
    y2: thickness - 1,
    color: color,
  );
  // Bottom
  img.fillRect(
    canvas,
    x1: 0,
    y1: canvas.height - thickness,
    x2: canvas.width - 1,
    y2: canvas.height - 1,
    color: color,
  );
  // Left
  img.fillRect(
    canvas,
    x1: 0,
    y1: 0,
    x2: thickness - 1,
    y2: canvas.height - 1,
    color: color,
  );
  // Right
  img.fillRect(
    canvas,
    x1: canvas.width - thickness,
    y1: 0,
    x2: canvas.width - 1,
    y2: canvas.height - 1,
    color: color,
  );
}

/// Punch transparent pixels outside the inscribed rounded-rect so the
/// final image renders with the requested corner radius.
void _applyRoundedCorners(img.Image canvas, {required int radius}) {
  final w = canvas.width;
  final h = canvas.height;
  final r = math.min(radius, math.min(w, h) ~/ 2);
  if (r <= 0) return;

  for (var y = 0; y < r; y++) {
    for (var x = 0; x < r; x++) {
      // Top-left corner check.
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

img.ColorRgba8 _argbToColor(int argb) {
  final a = (argb >> 24) & 0xff;
  final r = (argb >> 16) & 0xff;
  final g = (argb >> 8) & 0xff;
  final b = argb & 0xff;
  return img.ColorRgba8(r, g, b, a);
}
