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

  /// Initial state defaults to PNG (lossless) so both stitch and grid
  /// exports preserve maximum fidelity unless the user explicitly opts
  /// into JPG for smaller file size. Quality stays at
  /// [kMaxExportQuality] so a one-tap switch to JPG immediately
  /// produces the best-fidelity JPG — the slider is hidden for PNG
  /// anyway.
  factory ExportState.initial() => const ExportState(
    format: ExportFormat.png,
    quality: kMaxExportQuality,
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
