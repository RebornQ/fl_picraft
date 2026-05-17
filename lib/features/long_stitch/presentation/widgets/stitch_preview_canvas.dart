import 'dart:typed_data';

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
///
/// Owns its own scroll behavior — the grey surface always fills the
/// height supplied by the surrounding [Expanded] (no dead band below
/// the canvas when the assembled image is short), and a tall-aspect
/// canvas overflows the viewport upward via the inner
/// [SingleChildScrollView]. Callers MUST NOT wrap this widget in
/// another [SingleChildScrollView].
class StitchPreviewCanvas extends ConsumerWidget {
  const StitchPreviewCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The grey surface MUST fill the full height that the parent
        // Expanded gives us — without `minHeight: constraints.maxHeight`
        // short-aspect canvases collapse the Container to the assembled
        // image's intrinsic height and leave dead space below it. The
        // SingleChildScrollView wraps the ConstrainedBox so the surface
        // still scrolls when the (long-aspect) canvas grows past the
        // viewport.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
              ),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: state.hasImages
                    ? _PreviewSurface(state: state)
                    : _EmptyHint(
                        textTheme: textTheme,
                        colorScheme: colorScheme,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.textTheme, required this.colorScheme});

  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
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
      subtitleOnlyMode: state.subtitleOnlyMode,
      subtitleBandHeight: state.subtitleBandHeight,
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
              child: _maybeCropBottomBand(
                bytes: state.images[i].bytes,
                srcCrop: layout.srcCrops?[i],
                sourceWidth: state.images[i].width,
                sourceHeight: state.images[i].height,
                placementWidth: layout.imageRects[i].width,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute the displayed size by fitting the natural canvas
        // (canvasWidth × canvasHeight) inside the available area while
        // preserving aspect ratio. Mirrors the previous `FittedBox` +
        // fixed `ConstrainedBox(maxWidth: 360, maxHeight: 480)` look
        // but lets the preview scale up with the surrounding panel
        // (tablet / desktop / 4K). When constraints are unbounded on
        // either axis (the outer canvas now owns its own
        // SingleChildScrollView, so this _PreviewSurface receives a
        // maxHeight of infinity), we fall back to the cross-axis bound
        // so the canvas still has a well-defined size — and tall-aspect
        // canvases overflow the viewport upward, scrolling via the
        // outer canvas widget's SingleChildScrollView.
        final aspect = canvasWidth / canvasHeight;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : canvasWidth;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : maxWidth / aspect;

        var displayWidth = maxWidth;
        var displayHeight = displayWidth / aspect;
        if (displayHeight > maxHeight) {
          displayHeight = maxHeight;
          displayWidth = displayHeight * aspect;
        }

        return SizedBox(
          width: displayWidth,
          height: displayHeight,
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
        );
      },
    );
  }
}

/// Renders [bytes] into a tile of the assembled canvas. When [srcCrop]
/// is `null`, the full image is stretched to the placement rect (plain
/// vertical / horizontal). When supplied (movie-subtitle mode), only
/// the bottom band of the source is drawn — implemented by sizing the
/// `Image.memory` to the **un-cropped** scaled height and clipping it
/// inside the placement rect, anchored to the bottom via
/// [OverflowBox].
Widget _maybeCropBottomBand({
  required Uint8List bytes,
  required StitchRect? srcCrop,
  required int sourceWidth,
  required int sourceHeight,
  required int placementWidth,
}) {
  if (srcCrop == null || srcCrop.width <= 0 || srcCrop.height <= 0) {
    return Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
  }
  if (sourceWidth <= 0 || sourceHeight <= 0 || placementWidth <= 0) {
    return const SizedBox.shrink();
  }
  // Width-normalize the source to the placement width; the resulting
  // height usually exceeds the band height — OverflowBox lets it
  // overflow upward while ClipRect crops the overflow.
  final scaledHeight = sourceHeight * placementWidth / sourceWidth;
  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.bottomCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      minWidth: 0,
      maxWidth: double.infinity,
      child: SizedBox(
        width: placementWidth.toDouble(),
        height: scaledHeight,
        child: Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
      ),
    ),
  );
}
