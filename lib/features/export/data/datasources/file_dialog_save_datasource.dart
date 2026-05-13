import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/save_result.dart';
// Conditional import: the IO impl is selected on every non-web
// target; the web stub throws (web should route through the blob
// downloader, not this class).
import 'file_writer_stub.dart' if (dart.library.io) 'file_writer_io.dart';

/// Saves bytes by prompting the user via the OS native save dialog
/// (`file_picker.saveFile()`), then writing the chosen path.
///
/// Desktop-only (macOS / Windows / Linux). The web download path is
/// owned by `WebBlobDownloadDataSource`; iOS / Android route to
/// `GallerySaverDataSource`.
///
/// Three-layer defense per the directory-structure spec:
///   1. UI hides the desktop CTA on non-desktop via [isSupported].
///   2. Repository short-circuits with a typed failure.
///   3. [save] throws [UnsupportedError] as the last guarantee.
class FileDialogSaveDataSource {
  const FileDialogSaveDataSource();

  /// True on macOS / Windows / Linux.
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Open the OS save dialog and write [bytes] to the user's choice.
  ///
  /// Returns:
  /// * [SaveSuccess] with the absolute path on success.
  /// * [SaveCancelled] when the user dismisses the dialog.
  /// * [SaveFailure] on any OS-level error.
  Future<SaveResult> save(Uint8List bytes, {required String fileName}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'FileDialogSaveDataSource: only available on desktop.',
      );
    }

    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save image',
        fileName: fileName,
      );
      if (path == null) return const SaveCancelled();
      // file_picker's `saveFile` on desktop only chooses the path;
      // we own the actual byte write.
      await writeFileBytes(path, bytes);
      return SaveSuccess(location: path);
    } catch (e) {
      return SaveFailure('Save failed: $e');
    }
  }
}
