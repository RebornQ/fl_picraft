import 'dart:typed_data';

/// Stub — replaced by `web_blob_download_web.dart` on web via the
/// conditional import in `web_download_datasource.dart`.
///
/// Non-web platforms route through the gallery saver (mobile) or the
/// file_picker save dialog (desktop) and never call this.
Future<void> downloadBlob(Uint8List bytes, String fileName, String mimeType) {
  throw UnsupportedError(
    'downloadBlob is only available on the web build. '
    'The conditional import resolved to the stub.',
  );
}
