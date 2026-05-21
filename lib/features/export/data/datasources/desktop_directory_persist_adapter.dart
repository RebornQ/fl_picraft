import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/usecases/suggested_name.dart';
import 'batch_persist_adapter.dart';
// Conditional import: the IO impl is selected on every non-web
// target; the web stub throws. Desktop only runs on macOS / Windows /
// Linux so we always end up on the IO impl in practice.
import 'file_writer_stub.dart' if (dart.library.io) 'file_writer_io.dart';

/// Function the directory dialog goes through. Extracted as a typedef
/// so tests can inject a deterministic stub (no real `FilePicker`
/// plugin channel under unit tests).
typedef DirectoryPicker = Future<String?> Function({String? dialogTitle});

/// Function the per-file write goes through. Extracted as a typedef so
/// tests can inject a deterministic stub (real file IO not required
/// under unit tests).
typedef FileWriter = Future<void> Function(String path, Uint8List bytes);

/// Default desktop directory picker — calls
/// `FilePicker.platform.getDirectoryPath` with the standard zh-CN
/// dialog title.
Future<String?> _defaultPickDirectory({String? dialogTitle}) {
  return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
}

/// Desktop ([macOS] / [Windows] / [Linux]) batch persistence — one
/// directory pick followed by a sequential stream of file writes.
///
/// Memory shape: pull → write → discard, peak ~ 1 image. Cell N+1 is
/// not requested until cell N has been written and released.
///
/// Behavior:
///   * User dismisses the directory dialog → return [SaveCancelled]
///     and never pull from [next].
///   * All cells written → return [SaveSuccess] with the chosen
///     directory path and the count of files saved.
///   * Any per-cell failure (process throw or write IO error) → return
///     [SaveFailure] with the [partialSaveFailureMessage] frame and
///     the in-progress saved count. Already-written files are
///     **retained** on disk (no rollback) — the snackbar copy honestly
///     tells the user "已保存 X / Y 张" so they can decide whether to
///     clean up manually.
///
/// Filename convention:
///   `<chosen_dir>/flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>` where
///   `index` is 1-based per [suggestedName].
class DesktopDirectoryPersistAdapter extends BatchPersistAdapter {
  const DesktopDirectoryPersistAdapter({
    DirectoryPicker? directoryPicker,
    FileWriter? fileWriter,
    String dialogTitle = '选择导出文件夹',
  }) : _pickDirectory = directoryPicker ?? _defaultPickDirectory,
       _writeFile = fileWriter ?? writeFileBytes,
       _dialogTitle = dialogTitle;

  final DirectoryPicker _pickDirectory;
  final FileWriter _writeFile;
  final String _dialogTitle;

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

    String? directory;
    try {
      directory = await _pickDirectory(dialogTitle: _dialogTitle);
    } catch (e) {
      // The directory picker itself failed (rare — usually a plugin
      // channel error). Surface as a generic save failure since
      // nothing was written.
      return SaveFailure(saveFailureMessage(e));
    }

    if (directory == null) {
      // User dismissed — never pull from `next`, never write a byte.
      return const SaveCancelled();
    }

    var saved = 0;
    for (var i = 0; i < total; i++) {
      try {
        final bytes = await next(i);
        if (bytes == null) {
          // Producer signalled end-of-input before reaching [total].
          // Treat as a clean stop with whatever has been written so
          // far.
          break;
        }
        final name = suggestedName(format, at: at, index: i + 1);
        final path = p.join(directory, name);
        await _writeFile(path, bytes);
        saved++;
      } catch (e) {
        if (saved == 0) {
          return SaveFailure(saveFailureMessage(e));
        }
        return SaveFailure(
          partialSaveFailureMessage(saved: saved, total: total, cause: e),
        );
      }
    }

    if (saved == 0) {
      // Producer returned null on the very first pull — nothing to
      // report as success. Surface the empty result as a SaveFailure
      // so the snackbar tells the user something went wrong.
      return const SaveFailure('没有可导出的内容');
    }
    return SaveSuccess(location: directory, count: saved);
  }
}
