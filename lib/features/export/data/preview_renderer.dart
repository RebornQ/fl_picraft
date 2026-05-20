import 'package:flutter/foundation.dart';

import '../domain/entities/export_format.dart';
import '../domain/entities/watermark_config.dart';
import 'image_encoder.dart';
import 'watermark_renderer.dart';

/// Signature for the watermark-composite + final-encode stage of the
/// export pipeline.
///
/// Exposed as a typedef so callers (preview controller, save controller)
/// can inject a synchronous fake in tests — `compute()` runs in a real
/// isolate and bypasses `FakeAsync`, so unit tests that assert on
/// debounce / call-count semantics can't drive the production
/// implementation directly.
typedef ProcessBytesFn =
    Future<Uint8List> Function({
      required Uint8List source,
      required WatermarkConfig watermark,
      required ExportFormat format,
      required int quality,
    });

/// Production implementation of [ProcessBytesFn].
///
/// Composes the watermark rasterizer (`05-08-watermark`) and the
/// per-format encoder into a single isolate hop. Both callees
/// ([applyWatermark], [encodeForExport]) are pure-Dart and isolate-safe
/// per `.trellis/spec/frontend/directory-structure.md` → "Pattern:
/// Isolate-safe rasterizer in `data/`", so the function can be invoked
/// through [compute] from any caller.
///
/// The function deliberately does NOT add a `Timeline.startSync(...)`
/// region — callers wrap it with their own timeline label
/// (`export.preview` vs `export.process`) so DevTools can attribute
/// time spent to the preview vs the save path.
///
/// Falls back to synchronous execution when the Flutter binding is
/// unavailable (pure-Dart unit tests) so the function stays usable
/// outside of `flutter_test`. The synchronous path produces identical
/// bytes. Mirrors `stitch_image_renderer.dart` and
/// `grid_image_renderer.dart` and the legacy `_processOne` it
/// supersedes.
Future<Uint8List> processExportBytes({
  required Uint8List source,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
}) async {
  final request = _ProcessExportRequest(
    bytes: source,
    watermark: watermark,
    format: format,
    quality: quality,
  );
  try {
    return await compute(_processExportInIsolate, request);
  } catch (_) {
    return _processExportInIsolate(request);
  }
}

/// Argument bundle for [_processExportInIsolate]. SendPort-transferable
/// (only `Uint8List`, primitives, and immutable value objects whose
/// fields are themselves SendPort-transferable) so it can hop into a
/// background isolate via [compute].
///
/// Library-private because nothing outside this file needs to construct
/// one — [processExportBytes] is the sole producer.
class _ProcessExportRequest {
  const _ProcessExportRequest({
    required this.bytes,
    required this.watermark,
    required this.format,
    required this.quality,
  });

  final Uint8List bytes;
  final WatermarkConfig watermark;
  final ExportFormat format;
  final int quality;
}

/// Top-level (i.e. non-closure) entry function so it can be the
/// argument to [compute].
///
/// Runs the two CPU-heavy stages — watermark composite + final encode —
/// back-to-back inside the same isolate hop. Both callees
/// ([applyWatermark], [encodeForExport]) are pure-Dart and isolate-safe
/// per `.trellis/spec/frontend/directory-structure.md` → "Pattern:
/// Isolate-safe rasterizer in `data/`".
///
/// Kept private to this library so it can't be accidentally invoked on
/// the main isolate from outside.
Future<Uint8List> _processExportInIsolate(_ProcessExportRequest r) async {
  final watermarked = await applyWatermark(r.bytes, r.watermark);
  return encodeForExport(watermarked, r.format, quality: r.quality);
}
