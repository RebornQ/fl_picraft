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

/// Format [t] as `yyyyMMdd_HHmmss` (no separators except the
/// date/time underscore). Filename-safe across all target platforms.
String _formatTimestamp(DateTime t) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${p(t.month)}${p(t.day)}_'
      '${p(t.hour)}${p(t.minute)}${p(t.second)}';
}
