import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'web_zip_composer.dart';

/// Web-only implementation of [composeZipImpl]. Builds an in-memory
/// [Archive], stuffs each entry under `<rootFolder>/<name>`, and
/// returns the encoded ZIP bytes for handoff to the blob-download
/// path.
///
/// `package:archive` is imported ONLY here — non-web builds resolve
/// the conditional import to `web_zip_composer_stub.dart` and the
/// `archive` package code is excluded from their bundle.
///
/// PRD §技术方案: ZIP 结构 = 子目录
/// `flpicraft_<ts>/{flpicraft_<ts>_N.<ext>}` 外层 `flpicraft_<ts>.zip`.
Uint8List composeZipImpl({
  required Iterable<ZipEntry> entries,
  required String rootFolder,
}) {
  // Defensive: ZIP entry names must NOT start with `/` (some
  // extractors complain). Strip any leading slash from rootFolder
  // before joining with the entry name.
  final folder = rootFolder.endsWith('/')
      ? rootFolder.substring(0, rootFolder.length - 1)
      : rootFolder;

  final archive = Archive();
  for (final entry in entries) {
    final path = folder.isEmpty ? entry.name : '$folder/${entry.name}';
    archive.addFile(ArchiveFile.bytes(path, entry.bytes));
  }
  // `encodeBytes` returns Uint8List directly (4.x); the older
  // `encode(...)` is an alias that returns List<int>, but using the
  // typed form keeps the public API of composeZip narrow.
  return ZipEncoder().encodeBytes(archive);
}
