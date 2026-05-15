import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/save_result.dart';
// Conditional import: web build pulls in the real `package:web` impl;
// every other build resolves to the stub (which throws).
import 'web_blob_download_stub.dart'
    if (dart.library.js_interop) 'web_blob_download_web.dart';

/// Triggers a browser-side file download by constructing a Blob and
/// programmatically clicking an anchor element pointing at its
/// object URL.
///
/// Web-only. Three-layer defense (see spec):
///   1. UI hides the web CTA on non-web via [isSupported].
///   2. Repository short-circuits with a typed failure.
///   3. [save] throws [UnsupportedError] as the last guarantee.
class WebBlobDownloadDataSource {
  const WebBlobDownloadDataSource();

  /// True only on the web target.
  static bool get isSupported => kIsWeb;

  /// Trigger a browser download for [bytes] with the requested
  /// [fileName] and [mimeType].
  ///
  /// Always returns [SaveSuccess] on web — there's no user-visible
  /// dialog to cancel, the download starts immediately. Any thrown
  /// JS exception is caught and returned as [SaveFailure].
  Future<SaveResult> save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'WebBlobDownloadDataSource: only available on the web build.',
      );
    }
    try {
      await downloadBlob(bytes, fileName, mimeType);
      return const SaveSuccess(location: 'Downloads');
    } catch (e) {
      return SaveFailure(saveFailureMessage(e));
    }
  }
}
