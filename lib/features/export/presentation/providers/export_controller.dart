import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../long_stitch/presentation/providers/stitch_editor_provider.dart';
import '../../data/repositories/export_repository_impl.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_quality.dart';
import '../../domain/entities/export_request.dart';
import '../../domain/entities/export_source.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/repositories/export_repository.dart';
import 'export_state.dart';
import 'watermark_config_provider.dart';

/// DI seam so widget tests can inject a fake repository without
/// touching `gal` / `file_picker` / `package:web`.
final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepositoryImpl();
});

/// Controller for the export screen.
///
/// State owned here: format + quality + isSaving (see [ExportState]).
/// State read from other providers: the watermark config and the
/// long-stitch editor's current image list / render output. Cross-
/// feature reads go through public providers per
/// `.trellis/spec/frontend/directory-structure.md` →
/// "Cross-feature Dependencies".
class ExportController extends Notifier<ExportState> {
  @override
  ExportState build() => ExportState.initial();

  // ---- mutations --------------------------------------------------------

  void setFormat(ExportFormat format) {
    if (state.format == format) return;
    state = state.copyWith(format: format);
  }

  /// Set the JPG quality slider value (clamped to 1–100). No-op when
  /// the current format is PNG — the UI hides the slider in that
  /// case but we still guard here in case of a programmatic call.
  void setQuality(int quality) {
    final clamped = clampExportQuality(quality);
    if (state.quality == clamped) return;
    state = state.copyWith(quality: clamped);
  }

  // ---- save action ------------------------------------------------------

  /// Trigger the export pipeline and persist the result.
  ///
  /// Pulls the current source from the long-stitch editor (the grid
  /// editor's hook-in will land with `05-08-grid-split`). The
  /// [WatermarkConfig] is read at call time so the user's most recent
  /// toggle is honored even if they didn't pump the editor.
  ///
  /// Returns the [SaveResult] for the caller (the save button widget)
  /// to render as a snackbar. The notifier itself only flips
  /// [ExportState.isSaving] on the way in and out.
  Future<SaveResult> save() async {
    if (state.isSaving) {
      // Defensive: the button disables itself, but a programmatic
      // re-entrant call shouldn't double-fire the pipeline.
      return const SaveFailure('A save is already in progress');
    }

    final stitchEditor = ref.read(stitchEditorControllerProvider);
    if (!stitchEditor.hasImages) {
      return const SaveFailure('No images to export');
    }

    state = state.copyWith(isSaving: true);
    try {
      final composite = await ref
          .read(stitchEditorControllerProvider.notifier)
          .render();
      final request = ExportRequest(
        source: StitchExportSource(composite),
        format: state.format,
        quality: state.quality,
        watermark: ref.read(watermarkConfigProvider),
      );
      return await ref.read(exportRepositoryProvider).exportAndSave(request);
    } catch (e) {
      return SaveFailure('Export failed: $e');
    } finally {
      // If the notifier was disposed while a save was in flight (user
      // navigated away), the assignment is silently ignored by
      // Riverpod — no `mounted` guard needed.
      state = state.copyWith(isSaving: false);
    }
  }
}

/// Public provider — read this from the export screen.
final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
