import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/usecases/stitch_layout.dart';
import '../providers/stitch_editor_provider.dart';

/// Live preview matching the central canvas in `_2_长图拼接/code.html`.
///
/// Uses native Flutter widgets (no isolate / image-package work) so the
/// slider response stays well under the 100ms budget the PRD calls for.
/// The actual export pipeline goes through [StitchImageRenderer] when
/// the user taps "导出".
class StitchPreviewCanvas extends ConsumerWidget {
  const StitchPreviewCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
      padding: const EdgeInsets.all(16),
      child: state.hasImages
          ? Center(child: _PreviewSurface(state: state))
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '导入图片以预览拼接效果',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.state});

  final StitchEditorState state;

  @override
  Widget build(BuildContext context) {
    final layout = computeStitchLayout(
      sizes: [
        for (final i in state.images)
          StitchImageSize(width: i.width, height: i.height),
      ],
      mode: state.mode,
      spacing: state.spacing,
      borderWidth: state.border.width,
    );
    if (layout.canvasWidth == 0 || layout.canvasHeight == 0) {
      return const SizedBox.shrink();
    }

    final hasBorder = state.border.isVisible;
    final hasRadius = state.cornerRadius > 0;

    final canvasWidth = layout.canvasWidth.toDouble();
    final canvasHeight = layout.canvasHeight.toDouble();

    // Build the assembled image at its natural pixel size, then let
    // FittedBox scale the whole thing to fit the available preview
    // area. This keeps the layout math identical to the export
    // pipeline.
    final assembled = SizedBox(
      width: canvasWidth,
      height: canvasHeight,
      child: Stack(
        children: [
          // Border background fills the canvas; gets covered by images
          // and the inner white fill.
          if (hasBorder)
            Positioned.fill(child: ColoredBox(color: state.border.color)),
          // Inner background (white) so spacing gaps render opaquely
          // matching the export.
          Positioned(
            left: state.border.width,
            top: state.border.width,
            width: canvasWidth - 2 * state.border.width,
            height: canvasHeight - 2 * state.border.width,
            child: const ColoredBox(color: Colors.white),
          ),
          for (var i = 0; i < state.images.length; i++)
            Positioned(
              left: layout.imageRects[i].x.toDouble(),
              top: layout.imageRects[i].y.toDouble(),
              width: layout.imageRects[i].width.toDouble(),
              height: layout.imageRects[i].height.toDouble(),
              child: Image.memory(
                state.images[i].bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
        ],
      ),
    );

    final clipped = hasRadius
        ? ClipRRect(
            borderRadius: BorderRadius.circular(state.cornerRadius),
            child: assembled,
          )
        : assembled;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
      child: AspectRatio(
        aspectRatio: canvasWidth / canvasHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: hasRadius
                ? BorderRadius.circular(state.cornerRadius)
                : null,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: FittedBox(fit: BoxFit.contain, child: clipped),
        ),
      ),
    );
  }
}
