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
class StitchImageStrip extends ConsumerWidget {
  const StitchImageStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
              TextButton.icon(
                onPressed: () => ref
                    .read(stitchEditorControllerProvider.notifier)
                    .addFromGallery(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
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
          else
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
            ),
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
