import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/grid_layout.dart';
import '../providers/grid_editor_provider.dart';

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

    // Compute the layout in source coordinates so the overlay
    // matches what the renderer will produce exactly.
    final layout = computeGridLayout(
      sourceWidth: source.width,
      sourceHeight: source.height,
      type: state.gridType,
      spacing: state.spacing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final scaleX = source.width == 0 ? 0.0 : size.width / source.width;
        final scaleY = source.height == 0 ? 0.0 : size.height / source.height;

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              source.bytes,
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
          ],
        );
      },
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
