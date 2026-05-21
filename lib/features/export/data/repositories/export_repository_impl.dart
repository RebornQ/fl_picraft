import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_request.dart';
import '../../domain/entities/export_source.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/repositories/export_repository.dart';
import '../../domain/usecases/suggested_name.dart';
import '../datasources/batch_persist_adapter.dart';
import '../datasources/file_dialog_save_datasource.dart';
import '../datasources/gallery_saver_datasource.dart';
import '../datasources/web_blob_download_datasource.dart';
import '../preview_renderer.dart';

/// Signature for the **single-file** platform-dispatch step used by
/// the stitch path. Exposed so tests can inject a deterministic fake
/// without needing real plugin channels.
///
/// Grid / multi-image paths use [BatchPersistAdapter] instead — see
/// the `batch_persist_adapter.dart` interface.
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
/// Two dispatch surfaces:
///   * Single-file (stitch) path uses [_persist] internally — kept
///     intact so the existing `_exportSingle` behavior is byte-
///     identical post-refactor.
///   * Grid / multi-image path delegates to a [BatchPersistAdapter]
///     so the per-platform "1 dialog / 1 download" UX collapses N
///     OS confirms into 1 (PRD §05-21-batch-export-all).
///
/// The dispatch rules live HERE so presentation widgets never branch
/// on `kIsWeb` / `defaultTargetPlatform` themselves — UI just calls
/// [exportAndSave] and renders the [SaveResult].
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl({
    GallerySaverDataSource? gallery,
    FileDialogSaveDataSource? fileDialog,
    WebBlobDownloadDataSource? webDownload,
    @visibleForTesting BatchPersistAdapter? batchAdapter,
    @visibleForTesting PersistAdapter? persistOverride,
  }) : _gallery = gallery ?? const GallerySaverDataSource(),
       _fileDialog = fileDialog ?? const FileDialogSaveDataSource(),
       _webDownload = webDownload ?? const WebBlobDownloadDataSource(),
       _batchAdapter = batchAdapter ?? defaultBatchPersistAdapter(),
       _persistOverride = persistOverride;

  final GallerySaverDataSource _gallery;
  final FileDialogSaveDataSource _fileDialog;
  final WebBlobDownloadDataSource _webDownload;
  final BatchPersistAdapter _batchAdapter;
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
    // Single-cell shortcut: stitch cache hit. Bypass the batch adapter
    // entirely so the UX is byte-identical to a stitch export (one
    // file, no per-cell index suffix).
    if (processed.length == 1) {
      try {
        final name = suggestedName(format);
        return await _persist(processed.single, format, name);
      } catch (e) {
        return SaveFailure(exportFailureMessage(e));
      }
    }

    // Multi-cell cache hit (grid path). Route through the batch
    // adapter so the platform-specific "1 dialog / 1 download" UX
    // mirrors the cold path.
    //
    // Wrapped in `Timeline.startSync('export.save')` so DevTools shows
    // the same region for grid batches as for the stitch single-file
    // path — keeps "save plugin took N ms" triage symmetric across
    // sources. The adapter is free to add finer-grained subregions
    // (e.g. `export.zip` for Web) inside its own implementation.
    final at = DateTime.now();
    Timeline.startSync('export.save');
    try {
      return await _batchAdapter.persistMany(
        total: processed.length,
        next: (i) async => i < processed.length ? processed[i] : null,
        format: format,
        at: at,
      );
    } finally {
      Timeline.finishSync();
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

  /// Pull-based grid pipeline. Hands the cells off to the batch
  /// adapter which decides the memory shape (desktop / mobile stream
  /// write; web buffer + zip). Per-cell partial-save accounting lives
  /// inside the adapter so the repo stays platform-agnostic.
  ///
  /// Wrapped in `Timeline.startSync('export.save')` for parity with
  /// the stitch path's `_persist` marker — DevTools timeline shows
  /// "save plugin took N ms" regardless of which source feeds the
  /// pipeline. Per-cell `_processOne` calls retain their own
  /// `export.process` markers via the closure body.
  Future<SaveResult> _exportGrid(
    List<Uint8List> cells,
    ExportRequest request,
  ) async {
    if (cells.isEmpty) {
      return const SaveFailure('没有可导出的内容');
    }
    final at = DateTime.now();
    Timeline.startSync('export.save');
    try {
      return await _batchAdapter.persistMany(
        total: cells.length,
        next: (i) async {
          if (i < 0 || i >= cells.length) return null;
          return _processOne(cells[i], request);
        },
        format: request.format,
        at: at,
      );
    } finally {
      Timeline.finishSync();
    }
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
  ///
  /// **Single-file path only** — the grid path goes through
  /// [_batchAdapter] now, see [_exportGrid] and [persistOnly].
  Future<SaveResult> _persist(
    Uint8List bytes,
    ExportFormat format,
    String fileName,
  ) async {
    Timeline.startSync('export.save');
    try {
      // Tests can short-circuit the platform dispatch with a deterministic
      // adapter — exercises the stitch path without needing real
      // `gal` / `file_picker` / `package:web` plugin channels.
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
