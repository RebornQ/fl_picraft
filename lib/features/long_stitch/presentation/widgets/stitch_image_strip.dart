import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderables/reorderables.dart';

import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/domain/repositories/image_import_repository.dart'
    show kMaxImportSessionImages;
import '../providers/stitch_editor_provider.dart';

/// Horizontal scrollable strip of imported images, supporting drag
/// reorder (via `reorderables`) and a per-card remove button.
///
/// Mirrors the "已选图片" panel in the design mock
/// (`_2_长图拼接/code.html` lines ~80–155).
///
/// Header trailing affordances appear only when `imageCount > 0`:
/// * 「清空」 — opens a confirmation dialog before calling
///   [StitchEditorController.clear].
/// * Collapse / expand toggle — purely local UI state (no controller
///   field) that hides the [ReorderableRow] card row while keeping the
///   header + count visible. Default state is expanded.
class StitchImageStrip extends ConsumerStatefulWidget {
  const StitchImageStrip({super.key});

  @override
  ConsumerState<StitchImageStrip> createState() => _StitchImageStripState();
}

class _StitchImageStripState extends ConsumerState<StitchImageStrip> {
  /// Whether the card row is currently expanded. Local to the widget —
  /// the collapse state is **not** part of [StitchEditorState] (see
  /// task PRD: "状态归属：`StatefulWidget` 内的 `bool _expanded`").
  bool _expanded = true;

  Future<void> _confirmClear(BuildContext context, int imageCount) async {
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
    if (confirmed == true) {
      ref.read(stitchEditorControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasImages = state.images.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '已选图片 (${state.imageCount}/$kMaxImportSessionImages)',
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => ref
                        .read(stitchEditorControllerProvider.notifier)
                        .addFromGallery(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (hasImages) ...[
                    TextButton.icon(
                      onPressed: () => _confirmClear(context, state.imageCount),
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
                    IconButton(
                      tooltip: _expanded ? '收起' : '展开',
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.images.isEmpty)
            _EmptyHint(
              onPickGallery: () => ref
                  .read(stitchEditorControllerProvider.notifier)
                  .addFromGallery(),
              onPasteClipboard: () => ref
                  .read(stitchEditorControllerProvider.notifier)
                  .pasteFromClipboard(),
            )
          else if (_expanded)
            SizedBox(
              height: 140,
              child: ReorderableRow(
                needsLongPressDraggable: true,
                onReorder: (oldIndex, newIndex) {
                  ref
                      .read(stitchEditorControllerProvider.notifier)
                      .reorder(oldIndex, newIndex);
                },
                children: [
                  for (var i = 0; i < state.images.length; i++)
                    Padding(
                      // Use the image instance's identity as the key
                      // so the reorderable framework can track each
                      // card across position changes — encoding the
                      // index here would invalidate the key on every
                      // reorder and break the drag animation.
                      key: ObjectKey(state.images[i]),
                      padding: const EdgeInsets.only(right: 8),
                      child: _ImageCard(
                        index: i,
                        image: state.images[i],
                        onRemove: () => ref
                            .read(stitchEditorControllerProvider.notifier)
                            .removeImage(i),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.index,
    required this.image,
    required this.onRemove,
  });

  final int index;
  final ImportedImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 110,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      image.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${image.width}×${image.height}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.9),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: '移除',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                onPressed: onRemove,
              ),
            ),
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
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
        color: colorScheme.surface,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
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
      ),
    );
  }
}
