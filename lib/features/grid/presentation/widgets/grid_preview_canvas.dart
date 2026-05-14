import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/grid_layout.dart';
import '../providers/grid_editor_provider.dart';
import 'center_cell_overlay.dart';

/// Index of the center cell inside [GridLayout.rects] for a 3x3 grid
/// (row-major, 0-based). Kept here so the preview-side branching reads
/// intentional — matches `kCenterCellIndex` in the renderer.
const int _kCenterCellIndex = 4;

/// Live preview matching the central canvas in `_3_宫格切图/code.html`
/// lines 119–141.
///
/// Renders the source image at square aspect ratio (the design mock
/// uses `aspect-square`) with a grid overlay drawn at the active
/// [GridType]. Updates instantly when the user adjusts spacing / type
/// because the layout math is pure-Dart and runs on the UI isolate.
class GridPreviewCanvas extends ConsumerWidget {
  const GridPreviewCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: state.hasSource
            ? _PreviewSurface(state: state)
            : _EmptyState(textTheme: textTheme, colorScheme: colorScheme),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.textTheme, required this.colorScheme});

  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '导入图片以预览宫格效果',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.state});

  final GridEditorState state;

  @override
  Widget build(BuildContext context) {
    final source = state.source!;
    final isSocial =
        state.nineGridSocialMode && state.gridType == GridType.g3x3;

    // PRD §4.2 step 1: when the social mode is on, the renderer centre-
    // crops the source to its shortest-side square before splitting.
    // Mirror that here so the grid overlay reads in the same coordinate
    // space as the export. For the regular grid mode we keep the full
    // source dimensions (matching the renderer's untouched path).
    final shortSide = math.min(source.width, source.height);
    final effectiveWidth = isSocial ? shortSide : source.width;
    final effectiveHeight = isSocial ? shortSide : source.height;

    // Compute the layout in (effective) source coordinates so the
    // overlay matches what the renderer will produce exactly.
    final layout = computeGridLayout(
      sourceWidth: effectiveWidth,
      sourceHeight: effectiveHeight,
      type: state.gridType,
      spacing: state.spacing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final scaleX = effectiveWidth == 0 ? 0.0 : size.width / effectiveWidth;
        final scaleY = effectiveHeight == 0
            ? 0.0
            : size.height / effectiveHeight;

        final showCenterOverlay =
            isSocial && layout.rects.length > _kCenterCellIndex;

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              source.bytes,
              // BoxFit.cover on a square canvas centre-crops a non-
              // square source to the shortest-side square — which
              // matches the renderer's social-mode crop. For non-social
              // (free-aspect) the overlay computes against the full
              // source so cells map back to the visible region the
              // user already sees via cover.
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            // Translucent grid lines, mirroring the design mock's
            // `border-r border-b border-white/40` overlay (line 122–
            // 140) but driven by the layout rectangles so spacing /
            // type changes reflect immediately.
            IgnorePointer(
              child: CustomPaint(
                painter: _GridOverlayPainter(
                  rects: layout.rects,
                  cornerRadius: state.cornerRadius,
                  scaleX: scaleX,
                  scaleY: scaleY,
                ),
              ),
            ),
            if (showCenterOverlay)
              _PositionedCenterOverlay(
                cellRect: layout.rects[_kCenterCellIndex],
                scaleX: scaleX,
                scaleY: scaleY,
              ),
          ],
        );
      },
    );
  }
}

/// Anchors the interactive [CenterCellOverlay] to the 5th cell's
/// rendered position in the preview canvas (after the BoxFit.cover
/// scaling).
class _PositionedCenterOverlay extends StatelessWidget {
  const _PositionedCenterOverlay({
    required this.cellRect,
    required this.scaleX,
    required this.scaleY,
  });

  final GridRect cellRect;
  final double scaleX;
  final double scaleY;

  @override
  Widget build(BuildContext context) {
    final left = cellRect.x * scaleX;
    final top = cellRect.y * scaleY;
    final width = cellRect.width * scaleX;
    final height = cellRect.height * scaleY;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      // Pass both the rendered (widget-pixel) and the underlying
      // source-pixel cell dimensions so the overlay's gesture handler
      // can convert widget-pixel drag deltas into the source-pixel
      // offset units that the controller and renderer both speak.
      child: CenterCellOverlay(
        cellWidth: width,
        cellHeight: height,
        sourceCellWidth: cellRect.width.toDouble(),
        sourceCellHeight: cellRect.height.toDouble(),
      ),
    );
  }
}

class _GridOverlayPainter extends CustomPainter {
  _GridOverlayPainter({
    required this.rects,
    required this.cornerRadius,
    required this.scaleX,
    required this.scaleY,
  });

  final List<GridRect> rects;
  final double cornerRadius;
  final double scaleX;
  final double scaleY;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || scaleX == 0 || scaleY == 0) return;

    // Outline stroke around every cell, plus a translucent inner
    // shadow at the corners so the radius visualization reads at a
    // glance even on busy source images.
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Average scale for radius mapping — keeps the rendered radius
    // proportional even when the preview slightly distorts the
    // aspect ratio (BoxFit.cover may letterbox).
    final radiusScale = (scaleX + scaleY) / 2;
    final scaledRadius = (cornerRadius * radiusScale).clamp(0.0, 64.0);

    for (final r in rects) {
      final rect = Rect.fromLTWH(
        r.x * scaleX,
        r.y * scaleY,
        r.width * scaleX,
        r.height * scaleY,
      );
      if (scaledRadius > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(scaledRadius)),
          stroke,
        );
      } else {
        canvas.drawRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_GridOverlayPainter old) {
    return old.rects != rects ||
        old.cornerRadius != cornerRadius ||
        old.scaleX != scaleX ||
        old.scaleY != scaleY;
  }
}
