import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/usecases/suggested_name.dart';
import 'batch_persist_adapter.dart';
import 'web_blob_download_datasource.dart';
import 'web_zip_composer.dart';

/// MIME type used by the Web ZIP download anchor. Most browsers
/// honor `application/zip` for the standard ZIP container.
const String _kZipMimeType = 'application/zip';

/// Function the web blob download goes through. Extracted as a
/// typedef so tests can inject a deterministic stub instead of
/// hitting a real `<a>.click()` in a headless test runner.
///
/// Returns the raw [SaveResult] from the underlying datasource so the
/// adapter can pass any already-translated `SaveFailure.message`
/// through verbatim — wrapping the message a second time via
/// [saveFailureMessage] would double-prefix the snackbar copy with
/// `保存失败：保存失败：…`. Synchronous throws (composer OOM, transport
/// crash) are still caught by the adapter's outer `try`/`catch`.
typedef WebBlobDownloader =
    Future<SaveResult> Function(
      Uint8List bytes,
      String fileName,
      String mimeType,
    );

/// Default web blob downloader — defers to the existing
/// [WebBlobDownloadDataSource.save], which already returns a
/// [SaveResult] with the appropriate zh-CN message frame.
Future<SaveResult> _defaultWebBlobDownload(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  const downloader = WebBlobDownloadDataSource();
  return downloader.save(bytes, fileName: fileName, mimeType: mimeType);
}

/// Web batch persistence — pulls every cell sequentially, composes a
/// single ZIP in memory, and triggers exactly one browser download.
///
/// Memory shape: pull all → buffer → encode → download, peak ~ Σ
/// bytes. PRD MVP scope is at most 9 cells (3×3 grid), well below the
/// browser heap limit; OOM at extreme inputs is caught by
/// [try]/[catch] and surfaced as [SaveFailure].
///
/// Behavior:
///   * All cells pulled successfully → ZIP encoded → download
///     triggered → returns [SaveSuccess] with `location: 'Downloads'`
///     and `count: total`.
///   * Any per-cell pull or zip/download step throws → returns
///     [SaveFailure]. There are no partial downloads on web — the
///     browser sees a single click or nothing — so we don't credit
///     partial saves.
///   * Producer returns `null` early → archive contains whatever was
///     pulled before; if zero cells pulled, returns [SaveFailure].
///
/// Filename convention (PRD §文件命名规约):
///   * Outer:  `flpicraft_<yyyyMMdd_HHmmss>.zip`
///   * Folder: `flpicraft_<yyyyMMdd_HHmmss>/` (top-level subdir)
///   * Inner:  `flpicraft_<ts>_<index>.<ext>` (1-based index)
class WebZipPersistAdapter extends BatchPersistAdapter {
  const WebZipPersistAdapter({
    WebBlobDownloader? downloader,
    Uint8List Function({
      required Iterable<ZipEntry> entries,
      required String rootFolder,
    })?
    zipComposer,
  }) : _download = downloader ?? _defaultWebBlobDownload,
       _composeZip = zipComposer ?? _defaultComposeZip;

  final WebBlobDownloader _download;
  final Uint8List Function({
    required Iterable<ZipEntry> entries,
    required String rootFolder,
  })
  _composeZip;

  @override
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  }) async {
    if (total <= 0) {
      return const SaveFailure('没有可导出的内容');
    }

    final entries = <ZipEntry>[];
    try {
      for (var i = 0; i < total; i++) {
        final bytes = await next(i);
        if (bytes == null) {
          // Producer ended early — package whatever has been pulled.
          break;
        }
        final name = suggestedName(format, at: at, index: i + 1);
        entries.add((name: name, bytes: bytes));
      }
    } catch (e) {
      // Pulling / processing a cell failed before we had any chance
      // to download — no partial state on web.
      return SaveFailure(saveFailureMessage(e));
    }

    if (entries.isEmpty) {
      return const SaveFailure('没有可导出的内容');
    }

    try {
      final folder = suggestedZipFolderName(at: at);
      final outerName = suggestedZipName(at: at);
      // Compose + download is the most expensive web-side stage — give
      // it its own DevTools region so the parent `export.save` marker
      // (added by the repository) can be sub-divided when triaging
      // slow batches.
      Timeline.startSync('export.zip');
      final Uint8List zipBytes;
      try {
        zipBytes = _composeZip(entries: entries, rootFolder: folder);
      } finally {
        Timeline.finishSync();
      }
      final downloadResult = await _download(
        zipBytes,
        outerName,
        _kZipMimeType,
      );
      // Pass the downloader's SaveResult through verbatim:
      //   * Success → enrich with the entry count so the snackbar can
      //     surface "已保存 N 张".
      //   * Failure / cancel → forward the message untouched so the
      //     downloader's pre-translated `保存失败：…` frame is not
      //     wrapped again (which would double-prefix the copy).
      switch (downloadResult) {
        case SaveSuccess():
          return SaveSuccess(location: 'Downloads', count: entries.length);
        case SaveFailure():
          return downloadResult;
        case SaveCancelled():
          // Web blob download has no user-cancellable dialog. Reaching
          // here would be a regression in the downloader impl — surface
          // it as a SaveFailure so the user sees something actionable.
          return const SaveFailure('保存失败：浏览器下载意外中止');
      }
    } catch (e) {
      // Synchronous throws (composer OOM / unexpected transport crash)
      // still funnel into the standard "保存失败：…" frame.
      return SaveFailure(saveFailureMessage(e));
    }
  }
}

/// Thin wrapper so the default constructor binding matches the
/// composer's named-parameter signature.
Uint8List _defaultComposeZip({
  required Iterable<ZipEntry> entries,
  required String rootFolder,
}) {
  return composeZip(entries: entries, rootFolder: rootFolder);
}
