import 'export_format.dart';
import 'export_quality.dart';
import 'export_source.dart';
import 'watermark_config.dart';

/// Bundles everything the export pipeline needs to compose + persist
/// the user's work into platform-native storage.
///
/// Lives in `domain/` so the repository can take it without any
/// plugin / Flutter imports leaking up.
class ExportRequest {
  const ExportRequest({
    required this.source,
    required this.format,
    required this.quality,
    required this.watermark,
  });

  /// What we're exporting — a single composite or grid cells.
  final ExportSource source;

  /// User-selected output container format.
  final ExportFormat format;

  /// JPG quality (1–100). Ignored when [format] is PNG. The value is
  /// clamped to [kMinExportQuality]–[kMaxExportQuality] by the
  /// encoder, but callers SHOULD pass an already-valid value.
  final int quality;

  /// Optional watermark overlay applied before encoding. Pass the
  /// disabled default ([WatermarkConfig.initial]) to skip the
  /// composite step.
  final WatermarkConfig watermark;
}
