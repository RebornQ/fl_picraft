import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderables/reorderables.dart';

import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/domain/repositories/image_import_repository.dart'
    show kMaxImportSessionImages;
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../providers/stitch_editor_provider.dart';
import 'stitch_clear_confirm.dart';

/// Vertical "selected images" list for the long-stitch editor's
/// side panel on **wide screens only** (`WindowSizeClass.expanded` /
/// `WindowSizeClass.large`).
///
/// Provides the same affordances as the compact-screen
/// [StitchImageStrip] — header + count, append, clear, per-item
/// remove, long-press reorder — except:
///
/// * Layout is vertical (rows stacked top-to-bottom instead of cards
///   laid side-by-side). Uses [ReorderableColumn] from `reorderables`
///   to stay API-symmetric with [StitchImageStrip]'s [ReorderableRow].
/// * Single-row form: leading `Icons.drag_indicator` + 56×56 thumbnail
///   + size text + × button. The drag gesture itself still requires a
///   long-press anywhere on the row (`needsLongPressDraggable: true`);
///   the icon is decorative — tapping it doesn't initiate a separate
///   short-press drag, keeping the gesture consistent across the row.
/// * No collapse / expand toggle — the list lives inside a
///   half-height slot of the side panel and is itself an
///   internal-scroll surface, so collapsing it would be redundant.
///
/// Pairs with [StitchControlsPanel] under a [Column] in
/// `stitch_editor_screen.dart`'s side-panel branch (each gets
/// `Expanded(flex: 1)`). Both halves carry their own internal
/// `SingleChildScrollView`.
class StitchVerticalImageList extends ConsumerWidget {
  const StitchVerticalImageList({super.key});

  Future<void> _onClearPressed(
    BuildContext context,
    WidgetRef ref,
    int imageCount,
  ) async {
    final confirmed = await confirmStitchClear(context, imageCount);
    if (!context.mounted) return;
    if (confirmed) {
      ref.read(stitchEditorControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final isSessionFull = ref.watch(
      imageImportSessionFullProvider(ImageImportSessionKind.stitch),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasImages = state.images.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            count: state.imageCount,
            hasImages: hasImages,
            isSessionFull: isSessionFull,
            onAdd: () => notifier.addFromGallery(),
            onClear: () => _onClearPressed(context, ref, state.imageCount),
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: hasImages
                // ReorderableColumn is NOT wrapped in an outer
                // SingleChildScrollView, and it deliberately receives
                // `ignorePrimaryScrollController: true`:
                //
                // 1. reorderables 0.6.0 already wraps its own content
                //    in a SingleChildScrollView when no explicit
                //    `scrollController` is passed (see the package's
                //    `reorderable_flex.dart` build logic, lines
                //    884-897) — an outer SingleChildScrollView is
                //    therefore redundant and the source of the bug.
                // 2. `ignorePrimaryScrollController: true` injects a
                //    `PrimaryScrollController.none` above the
                //    reorderable subtree (package's
                //    `reorderable_flex.dart` lines 172-174), so the
                //    reorderable falls back to a fresh private
                //    `ScrollController()` instead of latching onto
                //    any ancestor PrimaryScrollController.
                //
                // Why both halves matter: with the previous outer
                // `SingleChildScrollView(primary: true by default)`
                // there was an ancestor PrimaryScrollController whose
                // position was already attached; reorderables resolved
                // the same controller via
                // `PrimaryScrollController.maybeOf(context)` and tried
                // to attach the very same position a second time,
                // tripping the "one position per controller" assertion
                // (`_positions.length == 1`). This was the crash users
                // saw the first time they long-press-dragged after
                // stretching from narrow to wide window width.
                ? ReorderableColumn(
                    needsLongPressDraggable: true,
                    ignorePrimaryScrollController: true,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    onReorder: notifier.reorder,
                    children: [
                      for (var i = 0; i < state.images.length; i++)
                        Padding(
                          // Identity-based key — the image instance
                          // moves to a new index on reorder but
                          // keeps its identity, so the reorder
                          // tracker can follow it (see frontend
                          // component-guidelines.md → "Reorderable
                          // list keys must be stable across position
                          // changes").
                          key: ObjectKey(state.images[i]),
                          padding: const EdgeInsets.all(4),
                          child: _VerticalImageRow(
                            image: state.images[i],
                            onRemove: () => notifier.removeImage(i),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: _EmptyHint(
                      onPickGallery: () => notifier.addFromGallery(),
                      onPasteClipboard: () => notifier.pasteFromClipboard(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.hasImages,
    required this.isSessionFull,
    required this.onAdd,
    required this.onClear,
    required this.colorScheme,
    required this.textTheme,
  });

  final int count;
  final bool hasImages;
  final bool isSessionFull;
  final VoidCallback onAdd;
  final VoidCallback onClear;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '已选图片 ($count/$kMaxImportSessionImages)',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: isSessionFull
                  ? '已达上限 $kMaxImportSessionImages 张'
                  : '添加图片',
              child: TextButton.icon(
                onPressed: isSessionFull ? null : onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            if (hasImages)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _VerticalImageRow extends StatelessWidget {
  const _VerticalImageRow({required this.image, required this.onRemove});

  final ImportedImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Row(
        children: [
          // Decorative drag handle — long-press anywhere on the row
          // triggers reorder; this icon just signals "I can be dragged"
          // visually. Marked as a non-interactive semantics node so
          // screen-readers don't announce a phantom button. Placed at
          // the leading edge so the handle reads as a "grip" before the
          // row content (matches list affordance conventions where the
          // handle precedes the item).
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ExcludeSemantics(
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: colorScheme.outline,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                semanticLabel: '已选图片缩略图',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${image.width}×${image.height}',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '移除',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.onPickGallery,
    required this.onPasteClipboard,
  });

  final VoidCallback onPickGallery;
  final VoidCallback onPasteClipboard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
        color: colorScheme.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            '尚未导入图片',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.photo_outlined, size: 16),
                label: const Text('从相册'),
              ),
              OutlinedButton.icon(
                onPressed: onPasteClipboard,
                icon: const Icon(Icons.paste, size: 16),
                label: const Text('剪贴板'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
