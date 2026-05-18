import 'package:flutter/material.dart';

/// Shows the "clear all selected images" confirmation dialog used by
/// both [StitchImageStrip] (compact / medium) and
/// [StitchVerticalImageList] (expanded / large).
///
/// Returns `true` when the user confirms; `false` (or `null` via
/// dismiss) otherwise. The caller is responsible for actually invoking
/// `clear()` on the controller — keeping this helper UI-only avoids
/// coupling it to any Riverpod provider, so it stays widget-agnostic
/// and easy to test in isolation.
Future<bool> confirmStitchClear(BuildContext context, int imageCount) async {
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('清空已选图片'),
        content: Text('将移除当前 $imageCount 张图片，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('清空'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
