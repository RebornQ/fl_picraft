import 'dart:typed_data';

/// Stub implementation — replaced by `file_writer_io.dart` on
/// non-web targets via the conditional import in
/// `file_dialog_save_datasource.dart`.
///
/// Web should never call this: the web path passes bytes directly to
/// `FilePicker.platform.saveFile()` (which delegates the download to
/// the browser blob URL flow we own in `web_blob_download.dart`).
Future<void> writeFileBytes(String path, Uint8List bytes) {
  throw UnsupportedError(
    'writeFileBytes is not supported on this platform — '
    'the conditional import resolved to the stub.',
  );
}
