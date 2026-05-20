import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/save_result.dart';
import '../providers/export_controller.dart';
import '../providers/export_dispatch.dart';

/// Primary save CTA for the export screen, rendered as a Material 3
/// [FloatingActionButton.extended]. Previously this was an inline
/// full-width [FilledButton] anchored at the bottom of the panel; the
/// FAB form gives the primary action a stronger visual weight per MD3
/// and keeps it reachable even when the user scrolls long settings.
///
/// Mirrors the mockup's "保存至相册" copy
/// (`_4_导出页面/code.html` line 207). The idle label is sourced from
/// [exportSaveButtonLabelProvider] so it adapts to the active source
/// (e.g. "保存 9 张至相册" when grid mode has 9 cells lined up).
///
/// State contract:
/// * Disabled (`onPressed: null`) while a save is in flight
/// ([ExportState.isSaving]).
/// * Disabled when the active editor has nothing to export
/// (see [canExportProvider]).
/// * In-flight icon is replaced by a [CircularProgressIndicator] and
/// the label flips to "保存中…".
/// * Calls [ExportController.save] and renders the returned
/// [SaveResult] as a snackbar (success → "已保存 …",
/// cancel → silent, failure → error snackbar).
///
/// **heroTag** is explicitly set to `'export-save-fab'`. Per
/// `.trellis/spec/frontend/component-guidelines.md` →
/// "FloatingActionButton 默认 heroTag 在多 screen 同时存活时冲突",
/// every FAB in the project must declare a unique tag. This sits in a
/// namespace alongside `stitch-export-fab` / `grid-export-fab`.
class SaveActionButton extends ConsumerWidget {
  const SaveActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(
      exportControllerProvider.select((s) => s.isSaving),
    );
    final canExport = ref.watch(canExportProvider);
    final idleLabel = ref.watch(exportSaveButtonLabelProvider);

    final enabled = !isSaving && canExport;

    return FloatingActionButton.extended(
      // Namespaced hero tag — see class doc-comment. Without an
      // explicit tag the default `_kDefaultHeroTag` would collide with
      // the editor-side export FABs the moment the user navigates
      // back to a long-stitch / grid editor screen that's still alive
      // in the navigator stack.
      heroTag: 'export-save-fab',
      onPressed: enabled ? () => _onSavePressed(context, ref) : null,
      tooltip: '保存至相册',
      icon: isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              // Default `valueColor` lets the FAB foreground theme drive
              // the spinner color, which keeps disabled / enabled
              // contrast correct without hard-coding `onPrimary`.
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined),
      label: Text(isSaving ? '保存中…' : idleLabel),
    );
  }

  Future<void> _onSavePressed(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(exportControllerProvider.notifier).save();
    if (!context.mounted) return;
    final snackBar = _snackBarFor(result, context);
    if (snackBar != null) {
      messenger.showSnackBar(snackBar);
    }
  }

  /// Returns `null` for [SaveCancelled] so cancelling the dialog
  /// doesn't pop a spurious snackbar.
  SnackBar? _snackBarFor(SaveResult result, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (result) {
      case SaveSuccess(:final location, :final count):
        final where = location ?? '本地';
        final copy = count > 1 ? '已保存 $count 张到 $where' : '已保存到 $where';
        return SnackBar(
          content: Text(copy),
          behavior: SnackBarBehavior.floating,
        );
      case SaveCancelled():
        return null;
      case SaveFailure(:final message):
        return SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.errorContainer,
        );
    }
  }
}
