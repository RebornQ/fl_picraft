import 'dart:typed_data';

import 'web_zip_composer.dart';

/// Stub — replaced by `web_zip_composer_web.dart` on web via the
/// conditional import in `web_zip_composer.dart`.
///
/// Non-web platforms never construct a [WebZipPersistAdapter] (the
/// dispatch factory routes them to desktop / mobile adapters instead),
/// so this stub should never run in practice. Reaching it indicates a
/// routing bug — throwing [UnsupportedError] surfaces the mistake
/// loudly rather than producing a silent zero-byte download.
Uint8List composeZipImpl({
  required Iterable<ZipEntry> entries,
  required String rootFolder,
}) {
  throw UnsupportedError(
    'composeZip is only available on the web build. '
    'The conditional import resolved to the stub.',
  );
}
