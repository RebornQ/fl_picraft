import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_request.dart';
import '../../domain/entities/export_source.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/repositories/export_repository.dart';
import '../../domain/usecases/suggested_name.dart';
import '../datasources/file_dialog_save_datasource.dart';
import '../datasources/gallery_saver_datasource.dart';
import '../datasources/web_blob_download_datasource.dart';
import '../preview_renderer.dart';

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

  @override
  Future<SaveResult> persistOnly(
    List<Uint8List> processed,
    ExportFormat format,
  ) async {
    if (processed.isEmpty) {
      return const SaveFailure('没有可导出的内容');
    }
    // Single-cell shortcut: behaves identically to a stitch export
    // (one file, no per-cell index suffix). Avoids needing the caller
    // to know whether they came from grid or stitch — the bytes count
    // tells us.
    if (processed.length == 1) {
      try {
        final name = suggestedName(format);
        return await _persist(processed.single, format, name);
      } catch (e) {
        return SaveFailure(exportFailureMessage(e));
      }
    }

    String? lastLocation;
    var saved = 0;
    final now = DateTime.now();
    for (var i = 0; i < processed.length; i++) {
      try {
        final name = suggestedName(format, at: now, index: i + 1);
        final result = await _persist(processed[i], format, name);
        switch (result) {
          case SaveSuccess(:final location):
            saved++;
            lastLocation = location ?? lastLocation;
          case SaveCancelled():
            if (saved > 0) {
              return SaveSuccess(location: lastLocation, count: saved);
            }
            return result;
          case SaveFailure(:final message):
            if (saved == 0) return result;
            return SaveFailure(
              partialSaveFailureMessage(
                saved: saved,
                total: processed.length,
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
            total: processed.length,
            cause: e,
          ),
        );
      }
    }
    return SaveSuccess(location: lastLocation, count: saved);
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
  /// Thin wrapper around the public [processExportBytes] function
  /// (`lib/features/export/data/preview_renderer.dart`) so the preview
  /// path and the save path share a single rasterizer implementation.
  ///
  /// Wrapped in `Timeline.startSync('export.process')` so DevTools can
  /// triage where time is spent (process vs. save plugin) when an
  /// export feels slow. The preview path adds its own
  /// `Timeline.startSync('export.preview')` region.
  Future<Uint8List> _processOne(Uint8List bytes, ExportRequest req) async {
    Timeline.startSync('export.process');
    try {
      return await processExportBytes(
        source: bytes,
        watermark: req.watermark,
        format: req.format,
        quality: req.quality,
      );
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
