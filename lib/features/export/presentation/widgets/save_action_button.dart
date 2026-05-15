import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/save_result.dart';
import '../providers/export_controller.dart';
import '../providers/export_dispatch.dart';

/// Full-width primary save CTA at the bottom of the export panel.
///
/// Mirrors the mockup's "保存至相册" button
/// (`_4_导出页面/code.html` line 207). The idle copy is sourced from
/// [exportSaveButtonLabelProvider] so it adapts to the active source
/// (e.g. "保存 9 张至相册" when grid mode has 9 cells lined up).
///
/// The button:
/// * Disables itself while a save is in flight
/// ([ExportState.isSaving]).
/// * Disables itself when the active editor has nothing to export
/// (see [canExportProvider]).
/// * Calls [ExportController.save] and renders the returned
/// [SaveResult] as a snackbar (success → "已保存 …",
/// cancel → silent, failure → error snackbar).
class SaveActionButton extends ConsumerWidget {
  const SaveActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaving = ref.watch(
      exportControllerProvider.select((s) => s.isSaving),
    );
    final canExport = ref.watch(canExportProvider);
    final idleLabel = ref.watch(exportSaveButtonLabelProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final enabled = !isSaving && canExport;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? () => _onSavePressed(context, ref) : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        icon: isSaving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(colorScheme.onPrimary),
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(isSaving ? '保存中…' : idleLabel),
      ),
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
