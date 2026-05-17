import 'package:flutter/material.dart';

/// Show a destructive-confirmation dialog before overwriting the grid
/// editor's current source image.
///
/// The grid editor consumes a single source image — re-importing
/// replaces it. To prevent an accidental tap from destroying user
/// work (cropped offsets, applied scale, etc.), this dialog gates the
/// import action whenever a source already exists.
///
/// Returns `true` if the user picked **替换** (confirm overwrite),
/// `false` if they tapped **取消** or dismissed the dialog by tapping
/// outside / using the system back button. Callers should treat any
/// non-`true` outcome as cancel.
///
/// The dialog uses a `TextButton` for cancel and a `FilledButton.tonal`
/// for confirm so the destructive action stays visually distinct from
/// the safe one without escalating to a high-emphasis filled button —
/// matching the Material 3 destructive-confirm pattern in
/// `component-guidelines.md`.
Future<bool> showOverwriteConfirmDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('替换现有图片？'),
      content: const Text('替换后，当前的裁剪位置与缩放会重置。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('替换'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
