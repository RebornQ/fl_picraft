import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_source_crop.dart';
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
/// Renders the source image with a grid overlay drawn at the active
/// [GridType]. Updates instantly when the user adjusts spacing / type
/// because the layout math is pure-Dart and runs on the UI isolate.
///
/// **Sizing contract**: this widget paints whatever rectangle the
/// caller hands it — it does NOT enforce a 1:1 (square) aspect ratio
/// itself. The design mock uses `aspect-square`, but we keep the
/// square-shape decision at the call site so the same height-first
/// idiom can be reused across size classes:
///
/// * compact / medium screens — canvas occupies the `Expanded` slot of
///   a single-column `Column`, wrapped in `Center` + `AspectRatio(1)`
///   so the square is sized `min(columnWidth, remainingHeight)` and
///   the controls panel keeps its scroll inside the same screen (no
///   page-level scroll). See `grid_editor_screen.dart` compact branch.
/// * expanded / large screens — same idiom, applied to the **left
///   column** of a `Row(crossAxisAlignment: stretch)`: an inner
///   `Column(stretch) > Expanded(Center(AspectRatio(1, canvas)))`
///   gives the canvas a bounded height inherited from the Row, so the
///   square is `min(leftColWidth, rowHeight)` — never taller than the
///   container. See `grid_editor_screen.dart` expanded / large branch.
///
/// In every case the canvas size is `min(availableWidth,
/// availableHeight)` — the caller's `Center + AspectRatio(1)` wrapper
/// is the **only** place that picks the aspect; this widget must stay
/// chrome-only so it can be reused across both single-column and
/// side-panel skeletons.
///
/// Either way the overlay math (see `_PreviewSurface`) reads
/// `constraints.biggest` and scales the layout rectangles into the
/// painted rectangle, so it works for any caller-imposed shape.
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
  // lock-step with the scale (mirrors the convention in
  // `center_cell_overlay.dart`).
  SourceOffset? _gestureStartOffset;
  double? _gestureStartScale;
  Offset? _gestureStartFocal;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final source = state.source!;
    final isSocial =
        state.nineGridSocialMode && state.gridType == GridType.g3x3;

    // PRD ST-C D2: the renderer carves a user-selected square crop out
    // of the source before splitting. Mirror that here so the preview's
    // grid overlay and image rendering both read against the same
    // coordinate system the renderer uses.
    final shortSide = math.min(source.width, source.height);
    final clampedScale = clampSourceScale(state.sourceScale);
    final aspect = source.height <= 0 ? 1.0 : source.width / source.height;
    final clampedOffset = clampSourceOffset(
      offset: state.sourceOffset,
      scale: clampedScale,
      sourceAspect: aspect,
    );
    final cropSideSource = shortSide / clampedScale;
    final cropCenterX = clampedOffset.dx * source.width;
    final cropCenterY = clampedOffset.dy * source.height;
    final cropXSource = cropCenterX - cropSideSource / 2;
    final cropYSource = cropCenterY - cropSideSource / 2;
    final cropSideInt = math.max(1, cropSideSource.round());

    // Compute the layout against the cropped square (square × square)
    // so the overlay rectangles map straight onto the cells the
    // renderer will produce.
    final layout = computeGridLayout(
      sourceWidth: cropSideInt,
      sourceHeight: cropSideInt,
      type: state.gridType,
      spacing: state.spacing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final viewportSide = math.min(size.width, size.height);
        if (viewportSide <= 0 || cropSideSource <= 0) {
          return const SizedBox.shrink();
        }
        final widgetPerSource = viewportSide / cropSideSource;
        final scaleX = widgetPerSource;
        final scaleY = widgetPerSource;

        final showCenterOverlay =
            isSocial && layout.rects.length > _kCenterCellIndex;

        return Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.expand,
          children: [
            // Render the full source positioned/sized so the
            // user-selected square crop fills the viewport. Using
            // explicit `Positioned` (rather than `BoxFit.cover`)
            // keeps preview and export byte-for-byte aligned at any
            // (offset, scale) combination.
            Positioned(
              left: -cropXSource * widgetPerSource,
              top: -cropYSource * widgetPerSource,
              width: source.width * widgetPerSource,
              height: source.height * widgetPerSource,
              child: Image.memory(
                source.bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            // Canvas-level pan/pinch detector. Sits below
            // [CenterCellOverlay] in z-order so the overlay's
            // `HitTestBehavior.opaque` recognizer blocks the canvas
            // drag inside the center cell (R-DRAG-05). When social
            // mode is off (or no center image is picked) the overlay
            // isn't mounted and this detector covers the entire
            // canvas.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _gestureStartOffset = state.sourceOffset;
                  _gestureStartScale = clampedScale;
                  _gestureStartFocal = details.localFocalPoint;
                  setState(() => _isGesturing = true);
                },
                onScaleUpdate: (details) => _onScaleUpdate(details),
                onScaleEnd: (_) {
                  _gestureStartOffset = null;
                  _gestureStartScale = null;
                  _gestureStartFocal = null;
                  setState(() => _isGesturing = false);
                },
              ),
            ),
            // Translucent grid lines, mirroring the design mock's
            // `border-r border-b border-white/40` overlay. Fades out
            // during active gestures (R-DRAG-04) so the user can see
            // the crop region without grid clutter. `IgnorePointer`
            // keeps the painter from claiming hits.
            //
            // When `state.spacing > 0`, the painter also fills the gap
            // bands between cells with `colorScheme.surfaceContainer`
            // so the preview visualizes the spacing instead of letting
            // the source image bleed through. This makes the preview
            // visually equivalent to the exported per-cell PNGs (whose
            // gap region is *omitted* — i.e. the canvas backdrop shows
            // through). See task `05-17-grid-spacing-color-fix`.
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

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final src = widget.state.source;
    if (src == null) return;
    final startScale =
        _gestureStartScale ?? clampSourceScale(widget.state.sourceScale);
    final startOffset = _gestureStartOffset ?? widget.state.sourceOffset;
    final startFocal = _gestureStartFocal ?? details.localFocalPoint;

    // Apply the new scale first so the offset clamp uses the right
    // cropSide. `details.scale` is cumulative since gesture start.
    final newScale = clampSourceScale(startScale * details.scale);

    // Translate the widget-pixel focal delta back into normalized
    // source coordinates. Moving the finger right by `dxWidget` should
    // make the image follow visually (right), which means the crop
    // window moves **left** in source coords — so we subtract.
    final dxWidget = details.localFocalPoint.dx - startFocal.dx;
    final dyWidget = details.localFocalPoint.dy - startFocal.dy;
    final viewportSide = _viewportSide() ?? 1.0;
    final shortSide = math.min(src.width, src.height);
    final startCropSide = shortSide / startScale;
    final startWidgetPerSource = startCropSide <= 0
        ? 0.0
        : viewportSide / startCropSide;
    final dxSource = startWidgetPerSource <= 0
        ? 0.0
        : dxWidget / startWidgetPerSource;
    final dySource = startWidgetPerSource <= 0
        ? 0.0
        : dyWidget / startWidgetPerSource;
    final newOffset = SourceOffset(
      startOffset.dx - dxSource / math.max(1, src.width),
      startOffset.dy - dySource / math.max(1, src.height),
    );

    final notifier = ref.read(gridEditorControllerProvider.notifier);
    notifier.setSourceScale(newScale);
    notifier.setSourceOffset(newOffset);
  }

  double? _viewportSide() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return math.min(box.size.width, box.size.height);
  }
}

/// Anchors the interactive [CenterCellOverlay] to the 5th cell's
/// rendered position in the preview canvas (after the user-selected
/// square crop is mapped into the viewport).
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
    // proportional even when the canvas aspect deviates from the
    // cropped-source aspect (cropped source is always square, so scaleX
    // and scaleY agree in practice — but average is the safe form).
    final radiusScale = (scaleX + scaleY) / 2;
    final scaledRadius = (cornerRadius * radiusScale).clamp(0.0, 64.0);

    // ── Gap fill (only when spacing > 0) ─────────────────────────
    // Mask the source image's bleed-through in the inter-cell bands
    // by (1) saveLayer-fill the whole viewport with [gapColor], then
    // (2) cut out every cell's RRect with `BlendMode.clear`. This
    // single saveLayer is O(rects) and pays one composite cost per
    // frame — far cheaper than `Path.combine(difference, …)` on
    // large grids, and it lets BlendMode.clear honor the cell
    // corner radius automatically.
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
    // Outline stroke around every cell, plus a translucent inner
    // shadow at the corners so the radius visualization reads at a
    // glance even on busy source images.
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
