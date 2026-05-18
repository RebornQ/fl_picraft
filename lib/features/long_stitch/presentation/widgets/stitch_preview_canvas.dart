import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/entities/stitch_mode.dart';
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
/// extent supplied by the surrounding [Expanded] (no dead band beside
/// the canvas when the assembled image is short), and the scroll axis
/// follows the active [StitchMode]:
///
/// * vertical mode → outer scroll runs on [Axis.vertical]; a tall-aspect
///   canvas overflows the viewport upward.
/// * horizontal mode → outer scroll runs on [Axis.horizontal]; the
///   canvas fills the viewport height and a wide-aspect canvas
///   overflows the viewport rightward. When the canvas is narrower than
///   the viewport it stays horizontally centered.
///
/// Callers MUST NOT wrap this widget in another [SingleChildScrollView]
/// on either axis.
class StitchPreviewCanvas extends ConsumerWidget {
  const StitchPreviewCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Drive the outer scroll axis off the active mode so horizontal
    // mode gets a horizontal scroll surface for wide-aspect canvases
    // and vertical mode keeps the existing upward-overflow behavior.
    // Exhaustive switch (no default) so a future StitchMode variant
    // compile-errors here instead of silently falling through.
    final scrollAxis = switch (state.mode) {
      StitchMode.vertical => Axis.vertical,
      StitchMode.horizontal => Axis.horizontal,
    };
    final isHorizontal = scrollAxis == Axis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The grey surface MUST fill the full extent that the parent
        // Expanded gives us on the cross axis — without the matching
        // `min*` constraint, short canvases collapse the Container to
        // the assembled image's intrinsic size and leave dead space
        // beside it. The SingleChildScrollView wraps the
        // ConstrainedBox so the surface still scrolls when the canvas
        // grows past the viewport on the active axis.
        return SingleChildScrollView(
          scrollDirection: scrollAxis,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: isHorizontal ? constraints.maxWidth : 0,
              minHeight: isHorizontal ? 0 : constraints.maxHeight,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
              ),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: state.hasImages
                    ? _PreviewSurface(
                        state: state,
                        fillAxis: isHorizontal ? Axis.vertical : null,
                      )
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
  const _PreviewSurface({required this.state, this.fillAxis});

  final StitchEditorState state;

  /// When non-null, the surface sizes itself by **filling** the given
  /// axis and deriving the other axis from the canvas aspect ratio.
  ///
  /// * `Axis.vertical` → height-driven sizing (used by horizontal
  ///   stitch mode so the canvas fills the viewport height and a
  ///   wide-aspect canvas overflows the viewport rightward).
  /// * `null` → legacy contain behavior (used by vertical stitch mode
  ///   where the canvas fits inside the available area and a
  ///   tall-aspect canvas overflows upward via the outer
  ///   [SingleChildScrollView]).
  final Axis? fillAxis;

  @override
  Widget build(BuildContext context) {
    // Convert the percent-based subtitle band height into the absolute
    // scaled pixels the layout consumes. Mirrors the math in
    // [StitchRenderRequest.fromState] so the preview and the exported
    // image agree.
    final firstScaledHeight = state.images.isEmpty
        ? 0
        : state.images.first.height;
    final bandPx = firstScaledHeight <= 0
        ? 1.0
        : (firstScaledHeight * state.subtitleBandHeightPercent)
              .clamp(1.0, double.infinity)
              .toDouble();
    final layout = computeStitchLayout(
      sizes: [
        for (final i in state.images)
          StitchImageSize(width: i.width, height: i.height),
      ],
      mode: state.mode,
      spacing: state.spacing,
      borderWidth: state.border.width,
      subtitleOnlyMode: state.subtitleOnlyMode,
      subtitleBandHeight: bandPx,
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
        // preserving aspect ratio. Two sizing modes:
        //
        // * fillAxis == Axis.vertical (horizontal stitch mode) →
        //   height-driven. The canvas fills the viewport height and
        //   derives its width from the aspect ratio; a wide canvas
        //   then overflows the outer SingleChildScrollView's
        //   horizontal extent.
        // * fillAxis == null (vertical stitch mode) → contain. Mirrors
        //   the previous behavior: fit the canvas inside the available
        //   area while preserving aspect. When the parent is
        //   unbounded on either axis (the outer canvas owns its own
        //   SingleChildScrollView, so this _PreviewSurface receives a
        //   maxHeight of infinity when vertical mode scrolls
        //   vertically), fall back to the cross-axis bound so the
        //   canvas still has a well-defined size — and tall-aspect
        //   canvases overflow the viewport upward, scrolling via the
        //   outer canvas widget's SingleChildScrollView.
        final aspect = canvasWidth / canvasHeight;
        final double displayWidth;
        final double displayHeight;
        if (fillAxis == Axis.vertical) {
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : canvasHeight;
          displayHeight = maxH;
          displayWidth = displayHeight * aspect;
        } else {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : canvasWidth;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : maxWidth / aspect;
          var w = maxWidth;
          var h = w / aspect;
          if (h > maxHeight) {
            h = maxHeight;
            w = h * aspect;
          }
          displayWidth = w;
          displayHeight = h;
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
