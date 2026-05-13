import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/entities/export_format.dart';
import '../domain/entities/export_quality.dart';

/// Re-encode [bytes] in the user-selected [format] with the
/// requested [quality] (JPG only).
///
/// * PNG path: decode → `encodePng` → lossless. Decoding the result
///   back must produce a pixel-identical image — see the round-trip
///   acceptance test in
///   `test/features/export/data/image_encoder_test.dart`.
/// * JPG path: decode → composite onto an opaque white canvas (JPG
///   has no alpha channel) → `encodeJpg(quality: ...)`. The quality
///   value is clamped to [kMinExportQuality]–[kMaxExportQuality]
///   before encoding so callers don't have to.
///
/// Pure-Dart and isolate-safe: only imports `package:image` (no
/// `dart:ui`). Callers may invoke this through `compute()` for heavy
/// images without trigger of `TextPainter` / `Canvas` restrictions
/// — see `.trellis/spec/frontend/directory-structure.md` →
/// "Pattern: Isolate-safe rasterizer in `data/`".
///
/// Returns the source bytes untouched when the input can't be
/// decoded (corrupt or unsupported file). The pipeline can still
/// persist *something* rather than crash; the caller surfaces a
/// snackbar based on the platform save result.
Uint8List encodeForExport(
  Uint8List bytes,
  ExportFormat format, {
  int quality = kDefaultExportQuality,
}) {
  // `img.decodeImage` invokes per-format `isValidFile` probes which
  // can throw on too-short / corrupt buffers (e.g. PSD's header read
  // crashes on 5 bytes). Treat any decode-time exception as
  // "unrecognized" and pass the bytes through.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return bytes;
  }
  if (decoded == null) return bytes;

  switch (format) {
    case ExportFormat.png:
      return Uint8List.fromList(img.encodePng(decoded));
    case ExportFormat.jpg:
      final flat = img.Image(
        width: decoded.width,
        height: decoded.height,
        numChannels: 3,
      );
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, decoded);
      return Uint8List.fromList(
        img.encodeJpg(flat, quality: clampExportQuality(quality)),
      );
  }
}
