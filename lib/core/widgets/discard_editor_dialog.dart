import 'package:flutter/material.dart';

/// Shared "exit editor without saving?" confirmation dialog used by the
/// compact secondary-page entry points of the long-stitch and grid
/// editors (since `05-26-mobile-stitch-secondary-page`).
///
/// **Why this lives in `core/widgets/`**: both the stitch and grid
/// editors need an identical confirm-then-clear flow on compact pop.
/// Per `.trellis/spec/guides/code-reuse-thinking-guide.md`, duplicating
/// the dialog + button layout in two places would drift in months —
/// keep one canonical helper here.
///
/// **What this helper does NOT do**: it does NOT call
/// `Navigator.pop` and does NOT touch any editor state. It is a pure
/// `Future<bool>` returning function. The caller is responsible for:
///
/// 1. Deciding when to invoke this (typically the editor's `PopScope`
///    `onPopInvokedWithResult` callback, fired by AppBar back arrow /
///    Android system back / iOS edge swipe).
/// 2. Acting on `true` → call its own `controller.clear()` then
///    `Navigator.pop()`.
/// 3. Acting on `false` → do nothing; the user stays in the editor.
///
/// Returns `true` when the user confirms exit, `false` when the user
/// cancels (or dismisses by tapping the scrim). Never returns `null` —
/// dismissals are coerced to `false` so callers can treat the result as
/// a non-nullable bool.
Future<bool> showDiscardEditorDialog(BuildContext context) async {
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    // Block scrim-dismiss from leaving the user uncertain whether their
    // tap counted. `barrierDismissible: false` forces an explicit
    // cancel / exit choice; combined with the `?? false` fallback below
    // this means the helper *can* still return false from a stray
    // back-button or system event but never from accidental scrim taps.
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('退出编辑器？'),
        content: const Text('未导出的拼图将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          // The destructive action uses error-colored text per Material 3
          // guidance for "destructive option in a confirmation dialog".
          // Keeps the affordance visually distinct from the safe cancel
          // path so users notice before they tap.
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('退出'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
