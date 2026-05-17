# ST-B · Grid overwrite-import with confirm dialog

> Parent: [`05-17-grid-canvas-drag-overwrite`](../05-17-grid-canvas-drag-overwrite/prd.md)

## Goal

Make the grid editor's AppBar import action **replace** the current source instead of silently appending into the import session. Show an `AlertDialog` first so a tap can't destroy work — confirmation is mandatory whenever `state.hasSource`.

## Scope

* `lib/features/grid/presentation/screens/grid_editor_screen.dart` — AppBar import action gains a `_confirmOverwriteIfNeeded()` step.
* `lib/features/grid/presentation/providers/grid_editor_provider.dart` — `addFromGallery()` evolves into `addFromGallery({bool replace = false})`, where `replace=true` calls `clear()` first.
* Maybe a small dialog widget at `lib/features/grid/presentation/widgets/overwrite_confirm_dialog.dart` — depends on whether the existing component-guidelines patterns prefer in-file `showDialog` or extracted widgets (TBR during impl).
* No changes to the import controller or repository — overwrite is a grid-feature concern only.

## Requirements

* **R-IMPORT-01** When the AppBar import action is tapped and `state.hasSource` is true, show a confirm dialog before the picker opens.
* **R-IMPORT-02** Confirm path: clear the grid-kind import session (`imageImportControllerProvider(.grid).notifier.clear()`), then call `pickFromGallery()`. Drag offset / scale (introduced by ST-C) reset.
* **R-IMPORT-03** Cancel path: no picker, no clear, no state mutation. Dialog dismisses on outside-tap (cancel).
* **R-IMPORT-04** When `state.hasSource` is false, the action skips the dialog and goes straight to the picker (no friction for first import).

## Acceptance Criteria

* [ ] **AC2** Importing when source exists shows a confirm dialog.
* [ ] **AC2.1** Confirm replaces the source; cancel preserves it. No partial state leaks (e.g. cleared session but no new image).
* [ ] **AC2.2** First import (no existing source) skips the dialog — single tap → picker opens.
* [ ] **AC2.3** Dialog copy: title "替换现有图片？", body explains the offset/scale reset, actions "取消" / "替换" (destructive style on confirm).
* [ ] **AC10** `flutter analyze`, `dart format .`, `flutter test` clean.

## Definition of Done

* New widget test: `grid_editor_screen_overwrite_import_test.dart` covering both branches (confirm + cancel) and the no-source skip path.
* Existing snackbar test for import failures still passes (the dialog wraps but does not replace the existing failure surface).
* No spec update unless `component-guidelines.md` lacks a destructive-confirm dialog pattern — in that case capture a 1-liner under "Destructive confirmations".

## Out of Scope

* Camera / clipboard import flows (`addFromCamera` / `pasteFromClipboard`) — left untouched; can be migrated in a follow-up if desired.
* "Undo overwrite" — not in scope.
* Multi-image import for grid kind — the editor only consumes `next.first` by design.

## Technical Notes

### Dialog signature

```dart
Future<bool> showOverwriteConfirmDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('替换现有图片？'),
      content: const Text('替换后，当前的裁剪位置与缩放会重置。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('替换'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
```

### Controller change

```dart
// grid_editor_provider.dart
Future<void> addFromGallery({bool replace = false}) async {
  if (replace) {
    final importNotifier = ref.read(
      imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
    );
    importNotifier.clear();
    state = state.copyWith(
      sourceOffset: kDefaultSourceOffset,  // wired by ST-C
      sourceScale: kDefaultSourceScale,
    );
  }
  await ref
      .read(imageImportControllerProvider(ImageImportSessionKind.grid).notifier)
      .pickFromGallery();
}
```

> NOTE: the `sourceOffset` / `sourceScale` reset code path **lands in ST-C**. In ST-B the `replace` branch only clears the session; ST-C extends this to also reset crop state once those fields exist. To avoid coupling the two PRs, ST-B can ship without the reset lines (they're a no-op until ST-C adds the fields).

### Screen change

```dart
// grid_editor_screen.dart AppBar action
IconButton(
  icon: const Icon(Icons.add_photo_alternate_outlined),
  tooltip: '导入图片',
  onPressed: () async {
    final hasSource = ref.read(gridEditorControllerProvider).hasSource;
    final go = !hasSource || await showOverwriteConfirmDialog(context);
    if (!go || !context.mounted) return;
    await notifier.addFromGallery(replace: hasSource);
  },
),
```

### Why session-clear (not direct repository call)?

Path 1 (clear session → pick) keeps the export pipeline's `next.first` reader untouched. Path 2 (bypass session) would require a parallel write into `state.source` and break the single-source-of-truth invariant. Path 1 wins.
