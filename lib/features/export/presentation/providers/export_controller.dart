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
import 'processed_bytes_cache.dart';
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
  /// Optimization: before invoking the full compose+encode+save
  /// pipeline, looks up the [processedBytesCacheProvider]. If the
  /// preview controller has already rendered identical bytes for the
  /// same input tuple, calls [ExportRepository.persistOnly] directly
  /// — skipping the 1~2 s isolate hop. Cache misses still flow
  /// through the original `exportAndSave` path.
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
      final kind = ref.read(currentExportSourceKindProvider);
      final editorHash = _activeEditorStateHash(kind);
      final watermark = ref.read(watermarkConfigProvider);
      final format = state.format;
      final quality = state.quality;

      // Cache hit shortcut: if the preview pipeline has already
      // processed identical bytes, skip the watermark+encode pass
      // entirely and go straight to persist.
      if (editorHash != null) {
        final key = computeProcessedBytesCacheKey(
          kind: kind,
          editorStateHash: editorHash,
          watermark: watermark,
          format: format,
          quality: quality,
        );
        final cached = ref.read(processedBytesCacheProvider.notifier).read(key);
        if (cached != null) {
          return await ref
              .read(exportRepositoryProvider)
              .persistOnly(cached, format);
        }
      }

      final source = await _buildSource(kind);
      if (source == null) {
        return const SaveFailure('没有可导出的图片');
      }
      final request = ExportRequest(
        source: source,
        format: format,
        quality: quality,
        watermark: watermark,
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
  Future<ExportSource?> _buildSource(ExportSourceKind kind) async {
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

  /// Snapshot the active editor's state hash for cache lookup, or
  /// `null` when the editor has no content. Mirrors the
  /// [PreviewController]'s same-named helper so the two share the key
  /// derivation exactly.
  int? _activeEditorStateHash(ExportSourceKind kind) {
    switch (kind) {
      case ExportSourceKind.stitch:
        final editor = ref.read(stitchEditorControllerProvider);
        if (!editor.hasImages) return null;
        return editor.hashCode;
      case ExportSourceKind.grid:
        final editor = ref.read(gridEditorControllerProvider);
        if (!editor.hasSource) return null;
        return editor.hashCode;
    }
  }
}

/// Public provider — read this from the export screen.
final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
