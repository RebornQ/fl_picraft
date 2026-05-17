import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_source_crop.dart';
import '../../domain/usecases/grid_layout.dart';
import '../providers/grid_editor_provider.dart';
import 'cell_overlay.dart';

/// Live preview matching the central canvas in `_3_宫格切图/code.html`
/// lines 119–141.
///
/// Renders the source image with a grid overlay drawn at the active
/// [GridType]. Updates instantly when the user adjusts spacing / type
/// because the layout math is pure-Dart and runs on the UI isolate.
///
/// **Sizing contract**: this widget paints whatever rectangle the
/// caller hands it — it does NOT enforce an aspect ratio itself. The
/// 05-17 Subtask B revamp picks `cols / rows` (e.g. `2.0` for 1×2,
/// `1.5` for 2×3, `1.0` for 3×3) at the call site so the same
/// height-first idiom can be reused across size classes:
///
/// * compact / medium screens — canvas occupies the `Expanded` slot of
///   a single-column `Column`, wrapped in `Center` +
///   `AspectRatio(cols / rows)` so the canvas is sized
///   `min(columnWidth, remainingHeight * aspect)` and the controls
///   panel keeps its scroll inside the same screen (no page-level
///   scroll). See `grid_editor_screen.dart` compact branch.
/// * expanded / large screens — same idiom, applied to the **left
///   column** of a `Row(crossAxisAlignment: stretch)`: an inner
///   `Column(stretch) > Expanded(Center(AspectRatio(cols / rows,
///   canvas)))` gives the canvas a bounded height inherited from the
///   Row.
///
/// The caller's `Center + AspectRatio(...)` wrapper is the **only**
/// place that picks the aspect; this widget must stay chrome-only so
/// it can be reused across both single-column and side-panel
/// skeletons.
///
/// The overlay math (see `_PreviewSurface`) reads `constraints.biggest`
/// and scales the layout rectangles into the painted rectangle, so it
/// works for any caller-imposed shape.
class GridPreviewCanvas extends ConsumerWidget {
  const GridPreviewCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.zero,
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

class _PreviewSurface extends ConsumerStatefulWidget {
  const _PreviewSurface({required this.state});

  final GridEditorState state;

  @override
  ConsumerState<_PreviewSurface> createState() => _PreviewSurfaceState();
}

class _PreviewSurfaceState extends ConsumerState<_PreviewSurface> {
  /// `true` while the user is actively dragging / pinching the canvas.
  /// Drives the grid-overlay fade-out (R-DRAG-04).
  bool _isGesturing = false;

  // Live state captured at gesture start so [_onScaleUpdate] can
  // compute "since-start" deltas. `details.scale` is cumulative since
  // start, but `focalPointDelta` is per-event — we use
  // `localFocalPoint - startLocalFocalPoint` to keep pan additive in
  // lock-step with the scale.
  SourceOffset? _gestureStartOffset;
  double? _gestureStartScale;
  Offset? _gestureStartFocal;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final source = state.source!;

    final cols = state.gridType.cols;
    final rows = state.gridType.rows;
    final targetAspect = rows <= 0 ? 1.0 : cols / rows;

    // 05-17 Subtask B: the renderer carves a user-selected rectangle
    // (aspect = cols/rows) out of the source before splitting. Mirror
    // that here so the preview's grid overlay and image rendering both
    // read against the same coordinate system the renderer uses.
    final clampedScale = clampSourceScale(state.sourceScale);
    final sourceAspect = source.height <= 0
        ? 1.0
        : source.width / source.height;
    final clampedOffset = clampSourceOffset(
      offset: state.sourceOffset,
      scale: clampedScale,
      sourceAspect: sourceAspect,
      targetAspect: targetAspect,
    );
    final cropRect = computeSourceCropRect(
      sourceWidth: source.width,
      sourceHeight: source.height,
      offset: clampedOffset,
      scale: clampedScale,
      targetAspect: targetAspect,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.width <= 0 || size.height <= 0 || cropRect == null) {
          return const SizedBox.shrink();
        }

        // Build the layout in cropped-source-space (the same coordinate
        // system the renderer uses), then map into viewport pixels via
        // independent x/y scales. cropWidth/cropHeight follow the
        // canvas's cols:rows aspect, so the painter's per-axis scales
        // agree to within sub-pixel rounding.
        final gap = math.max(0, state.spacing.round());
        final usableW = math.max(0, cropRect.width - gap * (cols - 1));
        final cellSide = cols == 0 ? 0 : usableW ~/ cols;
        final layout = computeGridLayout(
          cellSide: cellSide,
          type: state.gridType,
          spacing: state.spacing,
        );

        final scaleX = size.width / cropRect.width;
        final scaleY = size.height / cropRect.height;

        // Position the full source so the picked crop fills the viewport.
        final left = -cropRect.x * scaleX;
        final top = -cropRect.y * scaleY;
        final imgWidth = source.width * scaleX;
        final imgHeight = source.height * scaleY;

        return Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.expand,
          children: [
            // Render the full source positioned/sized so the
            // user-selected crop fills the viewport. Using explicit
            // `Positioned` (rather than `BoxFit.cover`) keeps preview
            // and export byte-for-byte aligned at any (offset, scale)
            // combination.
            Positioned(
              left: left,
              top: top,
              width: imgWidth,
              height: imgHeight,
              child: Image.memory(
                source.bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            // Canvas-level pan/pinch detector.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _gestureStartOffset = clampedOffset;
                  _gestureStartScale = clampedScale;
                  _gestureStartFocal = details.localFocalPoint;
                  setState(() => _isGesturing = true);
                },
                onScaleUpdate: (details) => _onScaleUpdate(details, cropRect),
                onScaleEnd: (_) {
                  _gestureStartOffset = null;
                  _gestureStartScale = null;
                  _gestureStartFocal = null;
                  setState(() => _isGesturing = false);
                },
              ),
            ),
            // Per-cell overlays — siblings above the canvas-level
            // detector so an opaque tap / pinch / longpress inside a
            // cell rect wins the gesture arena (z-order rules in
            // `component-guidelines.md`: stack hit-test runs top-down,
            // an opaque hit stops propagation). Mounted for every
            // cell, even empty ones, so the user can tap any cell to
            // invoke the picker.
            for (var i = 0; i < layout.rects.length; i++)
              Positioned(
                left: layout.rects[i].x * scaleX,
                top: layout.rects[i].y * scaleY,
                width: layout.rects[i].width * scaleX,
                height: layout.rects[i].height * scaleY,
                child: CellOverlay(
                  cellIndex: i,
                  rows: state.gridType.rows,
                  cols: state.gridType.cols,
                  cellWidth: layout.rects[i].width * scaleX,
                  cellHeight: layout.rects[i].height * scaleY,
                  sourceCellWidth: layout.rects[i].width.toDouble(),
                  sourceCellHeight: layout.rects[i].height.toDouble(),
                  isGesturing: _isGesturing,
                ),
              ),
            // Translucent grid lines, mirroring the design mock's
            // `border-r border-b border-white/40` overlay. Fades out
            // during active gestures (R-DRAG-04) so the user can see
            // the crop region without grid clutter.
            //
            // When `state.spacing > 0`, the painter also fills the gap
            // bands between cells with `colorScheme.surfaceContainer`
            // so the preview visualizes the spacing instead of letting
            // the source image bleed through.
            AnimatedOpacity(
              opacity: _isGesturing ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GridOverlayPainter(
                    rects: layout.rects,
                    cornerRadius: state.cornerRadius,
                    scaleX: scaleX,
                    scaleY: scaleY,
                    spacing: state.spacing,
                    gapColor: Theme.of(context).colorScheme.surfaceContainer,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details, SourceCropRect crop) {
    final src = widget.state.source;
    if (src == null) return;
    final startScale =
        _gestureStartScale ?? clampSourceScale(widget.state.sourceScale);
    final startOffset = _gestureStartOffset ?? widget.state.sourceOffset;
    final startFocal = _gestureStartFocal ?? details.localFocalPoint;

    // Apply the new scale first so the offset clamp uses the right
    // crop size. `details.scale` is cumulative since gesture start.
    final newScale = clampSourceScale(startScale * details.scale);

    // Translate the widget-pixel focal delta back into normalized
    // source coordinates. Moving the finger right by `dxWidget` should
    // make the image follow visually (right), which means the crop
    // window moves **left** in source coords — so we subtract.
    final dxWidget = details.localFocalPoint.dx - startFocal.dx;
    final dyWidget = details.localFocalPoint.dy - startFocal.dy;
    final viewport = _viewportSize();
    if (viewport == null) return;
    final widgetPerSourceX = crop.width <= 0
        ? 0.0
        : viewport.width / crop.width;
    final widgetPerSourceY = crop.height <= 0
        ? 0.0
        : viewport.height / crop.height;
    final dxSource = widgetPerSourceX <= 0 ? 0.0 : dxWidget / widgetPerSourceX;
    final dySource = widgetPerSourceY <= 0 ? 0.0 : dyWidget / widgetPerSourceY;
    final newOffset = SourceOffset(
      startOffset.dx - dxSource / math.max(1, src.width),
      startOffset.dy - dySource / math.max(1, src.height),
    );

    final notifier = ref.read(gridEditorControllerProvider.notifier);
    notifier.setSourceScale(newScale);
    notifier.setSourceOffset(newOffset);
  }

  Size? _viewportSize() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.size;
  }
}

class _GridOverlayPainter extends CustomPainter {
  _GridOverlayPainter({
    required this.rects,
    required this.cornerRadius,
    required this.scaleX,
    required this.scaleY,
    required this.spacing,
    required this.gapColor,
  });

  final List<GridRect> rects;
  final double cornerRadius;
  final double scaleX;
  final double scaleY;

  /// Logical spacing (in source pixels) between adjacent cells. Used
  /// only as a gate — the geometry of the gap bands is implicit in
  /// the difference between [rects] and the painter's `size`, so we
  /// don't need to multiply this by `scaleX/Y` ourselves.
  final double spacing;

  /// Fill color for the gap bands between cells. Sourced from
  /// `Theme.of(context).colorScheme.surfaceContainer` at the call
  /// site so the gap visually matches the canvas backdrop (and the
  /// "no-pixel" region of the exported per-cell PNGs).
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty || scaleX == 0 || scaleY == 0) return;

    // Average scale for radius mapping — keeps the rendered radius
    // proportional even when the canvas's per-axis scales drift by a
    // sub-pixel.
    final radiusScale = (scaleX + scaleY) / 2;
    final scaledRadius = (cornerRadius * radiusScale).clamp(0.0, 64.0);

    // ── Gap fill (only when spacing > 0) ─────────────────────────
    if (spacing > 0) {
      final layerBounds = Offset.zero & size;
      canvas.saveLayer(layerBounds, Paint());
      canvas.drawRect(layerBounds, Paint()..color = gapColor);
      final clearPaint = Paint()..blendMode = BlendMode.clear;
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
            clearPaint,
          );
        } else {
          canvas.drawRect(rect, clearPaint);
        }
      }
      canvas.restore();
    }

    // ── Cell outline stroke ──────────────────────────────────────
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

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
        old.scaleY != scaleY ||
        old.spacing != spacing ||
        old.gapColor != gapColor;
  }
}
