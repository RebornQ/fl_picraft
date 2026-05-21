import '../entities/export_format.dart';

/// File-name prefix for desktop / web saves. Matches the PRD's
/// "Default name: `flpicraft_<timestamp>.<ext>`".
const String kSuggestedNamePrefix = 'flpicraft';

/// Build a suggested file name for an export.
///
/// Returns either:
/// * `flpicraft_<yyyyMMdd_HHmmss>.<ext>` for a single composite
/// * `flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>` for the [index]-th
///   grid cell (0-based)
///
/// Pure: takes the timestamp as an argument so unit tests are
/// deterministic. Callers in production should pass `DateTime.now()`.
///
/// The function does NOT include the extension's leading dot — that's
/// already part of [ExportFormat.extension].
String suggestedName(ExportFormat format, {DateTime? at, int? index}) {
  final ts = _formatTimestamp(at ?? DateTime.now());
  final suffix = index == null ? '' : '_$index';
  return '${kSuggestedNamePrefix}_$ts$suffix.${format.extension}';
}

/// Build the suggested **outer** ZIP file name for a Web grid export.
///
/// Returns `flpicraft_<yyyyMMdd_HHmmss>.zip` — the file the browser
/// downloads. The inner folder name (used as ZIP entries' top-level
/// subdirectory) is produced by [suggestedZipFolderName] for the same
/// timestamp.
///
/// Pure: takes the timestamp as an argument so unit tests are
/// deterministic. Callers in production should pass `DateTime.now()`.
String suggestedZipName({DateTime? at}) {
  final ts = _formatTimestamp(at ?? DateTime.now());
  return '${kSuggestedNamePrefix}_$ts.zip';
}

/// Build the suggested **inner** folder name embedded as the top-level
/// subdirectory inside a Web grid export ZIP. No trailing slash —
/// the ZIP composer appends `/` when joining entry names.
///
/// Example: `flpicraft_20260521_120607` (which becomes
/// `flpicraft_20260521_120607/flpicraft_20260521_120607_3.jpg` inside
/// the archive).
///
/// Pure: takes the timestamp as an argument so unit tests are
/// deterministic. Callers in production should pass `DateTime.now()`.
String suggestedZipFolderName({DateTime? at}) {
  final ts = _formatTimestamp(at ?? DateTime.now());
  return '${kSuggestedNamePrefix}_$ts';
}

/// Format [t] as `yyyyMMdd_HHmmss` (no separators except the
/// date/time underscore). Filename-safe across all target platforms.
String _formatTimestamp(DateTime t) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${p(t.month)}${p(t.day)}_'
      '${p(t.hour)}${p(t.minute)}${p(t.second)}';
}
