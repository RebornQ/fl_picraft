import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../../grid/presentation/providers/grid_editor_provider.dart';
import '../../../long_stitch/presentation/providers/stitch_editor_provider.dart';
import '../../data/repositories/export_repository_impl.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_quality.dart';
import '../../domain/entities/export_request.dart';
import '../../domain/entities/export_source.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/repositories/export_repository.dart';
import 'export_dispatch.dart';
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
/// State read from other providers: the watermark config, the
/// long-stitch editor's render output, the grid editor's cell render
/// output, and [currentExportSourceKindProvider] to pick which path
/// runs. Cross-feature reads go through public providers per
/// `.trellis/spec/frontend/directory-structure.md` →
/// "Cross-feature Dependencies".
///
/// Dispatch contract: the calling editor screen is responsible for
/// updating [currentExportSourceKindProvider] **before** navigating
/// to `/export`. The result snackbar's cell-aware copy (e.g. "已保存
/// 8/9 张") is produced by the repository's [SaveSuccess.count]; the
/// controller itself only forwards the result.
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
  /// Reads [currentExportSourceKindProvider] to decide which editor
  /// owns the export session and dispatches to its renderer. The
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
      return const SaveFailure('正在保存中，请稍候');
    }

    state = state.copyWith(isSaving: true);
    try {
      final source = await _buildSource();
      if (source == null) {
        return const SaveFailure('没有可导出的图片');
      }
      final request = ExportRequest(
        source: source,
        format: state.format,
        quality: state.quality,
        watermark: ref.read(watermarkConfigProvider),
      );
      return await ref.read(exportRepositoryProvider).exportAndSave(request);
    } catch (e) {
      return SaveFailure(exportFailureMessage(e));
    } finally {
      // If the notifier was disposed while a save was in flight (user
      // navigated away), the assignment is silently ignored by
      // Riverpod — no `mounted` guard needed.
      state = state.copyWith(isSaving: false);
    }
  }

  /// Build the [ExportSource] for the active editor. Returns `null`
  /// when the editor has nothing to render so [save] can surface a
  /// uniform "没有可导出的图片" failure regardless of which kind
  /// is active.
  Future<ExportSource?> _buildSource() async {
    final kind = ref.read(currentExportSourceKindProvider);
    switch (kind) {
      case ExportSourceKind.stitch:
        final editor = ref.read(stitchEditorControllerProvider);
        if (!editor.hasImages) return null;
        final composite = await ref
            .read(stitchEditorControllerProvider.notifier)
            .render();
        return StitchExportSource(composite);
      case ExportSourceKind.grid:
        final editor = ref.read(gridEditorControllerProvider);
        if (!editor.hasSource) return null;
        final cells = await ref
            .read(gridEditorControllerProvider.notifier)
            .renderCells();
        return GridExportSource(cells);
    }
  }
}

/// Public provider — read this from the export screen.
final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
