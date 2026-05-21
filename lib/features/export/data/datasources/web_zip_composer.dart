import 'dart:typed_data';

import 'web_zip_composer_stub.dart'
    if (dart.library.js_interop) 'web_zip_composer_web.dart';

/// Entry in a [composeZip] batch — the in-archive filename (without
/// the `<rootFolder>/` prefix) and its raw bytes.
typedef ZipEntry = ({String name, Uint8List bytes});

/// Build a single in-memory ZIP buffer containing [entries] under
/// [rootFolder] as a top-level subdirectory.
///
/// The resulting ZIP structure:
///
/// ```
/// <rootFolder>/<entry[0].name>
/// <rootFolder>/<entry[1].name>
/// …
/// ```
///
/// Conditional import topology — the real implementation lives in
/// `web_zip_composer_web.dart` and imports `package:archive/archive.dart`.
/// All non-web builds resolve to `web_zip_composer_stub.dart` which
/// throws [UnsupportedError]; the `archive` package is therefore
/// excluded from every non-web bundle.
///
/// Callers MUST be wrapped by [WebZipPersistAdapter] (web-only) — a
/// non-web build that reaches this entry point is a routing bug.
Uint8List composeZip({
  required Iterable<ZipEntry> entries,
  required String rootFolder,
}) {
  return composeZipImpl(entries: entries, rootFolder: rootFolder);
}
