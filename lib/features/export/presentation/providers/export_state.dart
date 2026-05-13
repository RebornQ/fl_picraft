import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_quality.dart';

/// UI-facing snapshot of the export screen's format / quality pickers
/// plus the save-in-flight flag.
///
/// Save *results* (success / cancel / failure) are surfaced as the
/// return value of [ExportController.save] and rendered transiently
/// via a snackbar — they don't belong in this persistent state.
class ExportState {
  const ExportState({
    required this.format,
    required this.quality,
    required this.isSaving,
  });

  /// Initial state matches the mockup defaults: JPG selected, 85%
  /// quality, idle.
  factory ExportState.initial() => const ExportState(
    format: ExportFormat.jpg,
    quality: kDefaultExportQuality,
    isSaving: false,
  );

  final ExportFormat format;

  /// Slider value 1–100. Always within
  /// [kMinExportQuality]–[kMaxExportQuality]; the notifier clamps.
  final int quality;

  /// `true` while a save is in flight — disables the CTA so the user
  /// can't queue duplicate saves.
  final bool isSaving;

  ExportState copyWith({ExportFormat? format, int? quality, bool? isSaving}) {
    return ExportState(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExportState &&
        other.format == format &&
        other.quality == quality &&
        other.isSaving == isSaving;
  }

  @override
  int get hashCode => Object.hash(format, quality, isSaving);
}
