import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_request.dart';
import '../../domain/entities/export_source.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/entities/watermark_config.dart';
import '../../domain/repositories/export_repository.dart';
import '../../domain/usecases/suggested_name.dart';
import '../datasources/file_dialog_save_datasource.dart';
import '../datasources/gallery_saver_datasource.dart';
import '../datasources/web_blob_download_datasource.dart';
import '../image_encoder.dart';
import '../watermark_renderer.dart';

/// Signature for the platform-dispatch step. Exposed so tests can
/// inject a deterministic fake that exercises the grid loop's
/// partial-save accounting without needing real plugin channels.
typedef PersistAdapter =
    Future<SaveResult> Function(
      Uint8List bytes,
      ExportFormat format,
      String fileName,
    );

/// Default [ExportRepository] implementation.
///
/// Composes the existing watermark rasterizer (`05-08-watermark`) with
/// the new per-format encoder and a platform-dispatching save adapter.
///
/// The dispatch rules live HERE so presentation widgets never branch
/// on `kIsWeb` / `defaultTargetPlatform` themselves — UI just calls
/// [exportAndSave] and renders the [SaveResult].
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl({
    GallerySaverDataSource? gallery,
    FileDialogSaveDataSource? fileDialog,
    WebBlobDownloadDataSource? webDownload,
    @visibleForTesting PersistAdapter? persistOverride,
  }) : _gallery = gallery ?? const GallerySaverDataSource(),
       _fileDialog = fileDialog ?? const FileDialogSaveDataSource(),
       _webDownload = webDownload ?? const WebBlobDownloadDataSource(),
       _persistOverride = persistOverride;

  final GallerySaverDataSource _gallery;
  final FileDialogSaveDataSource _fileDialog;
  final WebBlobDownloadDataSource _webDownload;
  final PersistAdapter? _persistOverride;

  @override
  Future<SaveResult> exportAndSave(ExportRequest request) async {
    switch (request.source) {
      case StitchExportSource(:final bytes):
        return _exportSingle(bytes, request);
      case GridExportSource(:final cells):
        return _exportGrid(cells, request);
    }
  }

  // ---- per-shape pipelines ----------------------------------------------

  Future<SaveResult> _exportSingle(
    Uint8List bytes,
    ExportRequest request,
  ) async {
    try {
      final processed = await _processOne(bytes, request);
      final name = suggestedName(request.format);
      final result = await _persist(processed, request.format, name);
      return result;
    } catch (e) {
      return SaveFailure(exportFailureMessage(e));
    }
  }

  /// Cell-by-cell pipeline. Stops at the first failure so the user
  /// sees one consistent error instead of n stacked snackbars. Cells
  /// already on disk before the failure are credited in the returned
  /// result so the snackbar never claims more (or less) than what
  /// actually landed.
  Future<SaveResult> _exportGrid(
    List<Uint8List> cells,
    ExportRequest request,
  ) async {
    if (cells.isEmpty) {
      return const SaveFailure('没有可导出的内容');
    }
    String? lastLocation;
    var saved = 0;
    final now = DateTime.now();

    for (var i = 0; i < cells.length; i++) {
      try {
        final processed = await _processOne(cells[i], request);
        final name = suggestedName(request.format, at: now, index: i + 1);
        final result = await _persist(processed, request.format, name);
        switch (result) {
          case SaveSuccess(:final location):
            saved++;
            lastLocation = location ?? lastLocation;
          case SaveCancelled():
            // Honor the user's dismiss, but credit the cells already
            // on disk. Returning [SaveSuccess] with the partial count
            // surfaces honest "已保存 N 张" snackbar copy instead of
            // going silent and hiding what was saved.
            if (saved > 0) {
              return SaveSuccess(location: lastLocation, count: saved);
            }
            return result;
          case SaveFailure(:final message):
            if (saved == 0) return result;
            return SaveFailure(
              partialSaveFailureMessage(
                saved: saved,
                total: cells.length,
                cause: message,
              ),
            );
        }
      } catch (e) {
        if (saved == 0) {
          return SaveFailure(exportFailureMessage(e));
        }
        return SaveFailure(
          partialSaveFailureMessage(
            saved: saved,
            total: cells.length,
            cause: e,
          ),
        );
      }
    }
    return SaveSuccess(location: lastLocation, count: saved);
  }

  /// Watermark composite + final encode.
  ///
  /// Dispatched through [compute] so the watermark rasterizer's
  /// `img.decodeImage` / `img.drawString` / `img.encodePng|Jpg` —
  /// each multi-millisecond on real-sized photos — never blocks the
  /// UI isolate. Mirrors the isolate-hop pattern already used by
  /// `StitchImageRenderer` and `GridImageRenderer`.
  ///
  /// The repository previously ran this synchronously on the main
  /// isolate, which prevented `ExportState.isSaving` from rendering
  /// a loading state — the UI never got a frame to schedule before
  /// the platform save dialog popped. See `.trellis/tasks/
  /// 05-20-fix-export-save-ui-jank/prd.md` for the incident.
  ///
  /// Wrapped in `Timeline.startSync('export.process')` so DevTools can
  /// triage where time is spent (process vs. save plugin) when an
  /// export feels slow.
  Future<Uint8List> _processOne(Uint8List bytes, ExportRequest req) async {
    Timeline.startSync('export.process');
    try {
      final request = _ProcessOneRequest(
        bytes: bytes,
        watermark: req.watermark,
        format: req.format,
        quality: req.quality,
      );
      try {
        return await compute(_processOneInIsolate, request);
      } catch (_) {
        // Fallback for pure-Dart unit tests where the Flutter binding
        // is unavailable (compute throws). The synchronous path
        // produces identical bytes. Mirrors
        // `stitch_image_renderer.dart` and `grid_image_renderer.dart`.
        return _processOneInIsolate(request);
      }
    } finally {
      Timeline.finishSync();
    }
  }

  /// Pick the right save adapter for the running platform.
  ///
  /// Order of checks mirrors `defaultTargetPlatform` / `kIsWeb`:
  /// web → mobile → desktop. The repository's typed failure (step 2
  /// of the three-layer defense) makes the dispatch errors visible
  /// in tests even when the datasource's own guard fires later.
  ///
  /// Wrapped in `Timeline.startSync('export.save')` so DevTools can
  /// distinguish "save plugin took N ms" from upstream watermark/encode
  /// time when triaging slow exports.
  Future<SaveResult> _persist(
    Uint8List bytes,
    ExportFormat format,
    String fileName,
  ) async {
    Timeline.startSync('export.save');
    try {
      // Tests can short-circuit the platform dispatch with a deterministic
      // adapter — exercises the grid loop's partial-save accounting
      // without needing real `gal` / `file_picker` / `package:web`
      // plugin channels.
      final override = _persistOverride;
      if (override != null) {
        return await override(bytes, format, fileName);
      }
      if (WebBlobDownloadDataSource.isSupported) {
        return await _webDownload.save(
          bytes,
          fileName: fileName,
          mimeType: format.mimeType,
        );
      }
      if (GallerySaverDataSource.isSupported) {
        // gal appends the extension itself — strip the user-facing
        // `.png` / `.jpg` we generated for the desktop/web path.
        final mobileName = _stripExtension(fileName);
        return await _gallery.save(bytes, fileName: mobileName);
      }
      if (FileDialogSaveDataSource.isSupported) {
        return await _fileDialog.save(bytes, fileName: fileName);
      }
      return SaveFailure(
        '当前平台暂不支持保存图片（${kIsWeb ? "web" : defaultTargetPlatform}）',
      );
    } finally {
      Timeline.finishSync();
    }
  }

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }
}

/// Argument bundle for [_processOneInIsolate]. SendPort-transferable
/// (only `Uint8List`, primitives, and immutable value objects whose
/// fields are themselves SendPort-transferable) so it can hop into a
/// background isolate via [compute].
///
/// Library-private because nothing outside this file needs to construct
/// one — [ExportRepositoryImpl] is the sole producer.
class _ProcessOneRequest {
  const _ProcessOneRequest({
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
Future<Uint8List> _processOneInIsolate(_ProcessOneRequest r) async {
  final watermarked = await applyWatermark(r.bytes, r.watermark);
  return encodeForExport(watermarked, r.format, quality: r.quality);
}
