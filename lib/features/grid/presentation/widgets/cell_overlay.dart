import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/cell_replacement.dart';
import '../../domain/usecases/compute_cell_transform.dart';
import '../providers/grid_editor_provider.dart';

/// Interactive overlay mounted on every cell in [GridPreviewCanvas].
///
/// Two modes, both driven by the controller's per-cell APIs:
///
/// * **Empty** — tapping invokes [GridEditorController.pickCellImage]
///   so the user can drop a replacement image into this cell.
/// * **Replaced** — the cell's [CellReplacement] is rendered on top of
///   the source slice. Pinch updates `scale`, pan updates `offset`,
///   long-press opens a popup menu with "替换 / 重置 / 移除" actions.
///
/// Unit contract:
/// * [cellWidth] / [cellHeight] — on-screen size of the cell in widget
///   pixels (used for hit-test extent and for scaling the rendered
///   image preview).
/// * [sourceCellWidth] / [sourceCellHeight] — source-pixel size of the
///   cell (the renderer's cellSide). Used by the gesture handlers to
///   convert widget-pixel pan deltas into the source-pixel offset
///   units stored on [CellReplacement.offset]. The renderer reads
///   those same units back when composing the replacement cell.
class CellOverlay extends ConsumerWidget {
  const CellOverlay({
    super.key,
    required this.cellIndex,
    required this.rows,
    required this.cols,
    required this.cellWidth,
    required this.cellHeight,
    required this.sourceCellWidth,
    required this.sourceCellHeight,
  });

  /// Row-major index of this cell within the current grid.
  final int cellIndex;

  /// Active grid row / column count. Used only for the accessibility
  /// label so the screen reader can announce "第 2 行 第 3 列" instead
  /// of a bare flat index.
  final int rows;
  final int cols;

  /// On-screen widget-pixel size of the cell.
  final double cellWidth;
  final double cellHeight;

  /// Source-pixel size of the cell (the renderer's `cellSide`).
  final double sourceCellWidth;
  final double sourceCellHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replacement = ref.watch(
      gridEditorControllerProvider.select((s) => s.cellReplacements[cellIndex]),
    );
    final semanticsLabel = replacement == null
        ? '替换第${cellIndex + 1}格图片'
        : _cellLabel(cellIndex, rows: rows, cols: cols);

    return Semantics(
      label: semanticsLabel,
      hint: replacement == null ? '点按选择替换图片' : '双指缩放或拖动可调整；长按打开菜单',
      button: replacement == null,
      child: SizedBox(
        width: cellWidth,
        height: cellHeight,
        child: replacement == null
            ? _EmptyCellTarget(
                onTap: () => ref
                    .read(gridEditorControllerProvider.notifier)
                    .pickCellImage(cellIndex),
              )
            : _ReplacedCell(
                cellIndex: cellIndex,
                replacement: replacement,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                sourceCellWidth: sourceCellWidth,
                sourceCellHeight: sourceCellHeight,
              ),
      ),
    );
  }
}

/// Empty-state hit target. Uses `HitTestBehavior.translucent` rather
/// than `opaque` so the canvas-level pan/pinch detector mounted BELOW
/// in the Stack still receives pointer events — only a discrete tap
/// (the user picking a replacement image) wins the gesture arena from
/// this layer. A drag inside an empty cell continues to drive the
/// crop-pan on the source image.
class _EmptyCellTarget extends StatelessWidget {
  const _EmptyCellTarget({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}

/// Replaced-state cell — composites the replacement image on top of the
/// source slice, handles pinch / pan, and routes longpress to the
/// action menu.
class _ReplacedCell extends ConsumerStatefulWidget {
  const _ReplacedCell({
    required this.cellIndex,
    required this.replacement,
    required this.cellWidth,
    required this.cellHeight,
    required this.sourceCellWidth,
    required this.sourceCellHeight,
  });

  final int cellIndex;
  final CellReplacement replacement;
  final double cellWidth;
  final double cellHeight;
  final double sourceCellWidth;
  final double sourceCellHeight;

  @override
  ConsumerState<_ReplacedCell> createState() => _ReplacedCellState();
}

class _ReplacedCellState extends ConsumerState<_ReplacedCell> {
  double? _gestureStartScale;
  CellOffset? _gestureStartOffset;
  Offset? _gestureStartFocal;

  @override
  Widget build(BuildContext context) {
    final replacement = widget.replacement;
    final image = replacement.image;
    // Convert source-pixel offset → widget-pixel offset for preview.
    final widgetPerSourceX = widget.sourceCellWidth <= 0
        ? 0.0
        : widget.cellWidth / widget.sourceCellWidth;
    final widgetPerSourceY = widget.sourceCellHeight <= 0
        ? 0.0
        : widget.cellHeight / widget.sourceCellHeight;
    final widgetDx = replacement.offset.dx * widgetPerSourceX;
    final widgetDy = replacement.offset.dy * widgetPerSourceY;

    // Cover-fit sizing for the preview — match the renderer's geometry
    // exactly so what the user sees matches the exported PNG.
    final cover = coverScaleFactor(
      imageWidth: image.width,
      imageHeight: image.height,
      cellWidth: widget.cellWidth.round(),
      cellHeight: widget.cellHeight.round(),
    );
    final effective = cover * replacement.scale;
    final renderedW = image.width * effective;
    final renderedH = image.height * effective;
    final left = (widget.cellWidth - renderedW) / 2 + widgetDx;
    final top = (widget.cellHeight - renderedH) / 2 + widgetDy;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => _showMenu(context, details.globalPosition),
      onScaleStart: (details) {
        _gestureStartScale = replacement.scale;
        _gestureStartOffset = replacement.offset;
        _gestureStartFocal = details.localFocalPoint;
      },
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: (_) {
        _gestureStartScale = null;
        _gestureStartOffset = null;
        _gestureStartFocal = null;
      },
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: left,
              top: top,
              width: renderedW,
              height: renderedH,
              child: Image.memory(
                image.bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final startScale = _gestureStartScale;
    final startOffset = _gestureStartOffset;
    final startFocal = _gestureStartFocal;
    if (startScale == null || startOffset == null || startFocal == null) {
      return;
    }
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    final newScale = clampUserScale(startScale * details.scale);

    // Translate widget-pixel focal delta into source-pixel offset
    // units (the canonical units stored on CellReplacement.offset).
    final widgetPerSourceX = widget.sourceCellWidth <= 0
        ? 0.0
        : widget.cellWidth / widget.sourceCellWidth;
    final widgetPerSourceY = widget.sourceCellHeight <= 0
        ? 0.0
        : widget.cellHeight / widget.sourceCellHeight;
    final dxWidget = details.localFocalPoint.dx - startFocal.dx;
    final dyWidget = details.localFocalPoint.dy - startFocal.dy;
    final dxSource = widgetPerSourceX <= 0 ? 0.0 : dxWidget / widgetPerSourceX;
    final dySource = widgetPerSourceY <= 0 ? 0.0 : dyWidget / widgetPerSourceY;
    final newOffset = CellOffset(
      startOffset.dx + dxSource,
      startOffset.dy + dySource,
    );

    notifier.setCellScale(widget.cellIndex, newScale);
    notifier.setCellOffset(widget.cellIndex, newOffset);
  }

  Future<void> _showMenu(BuildContext context, Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<_CellMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      items: const [
        PopupMenuItem(value: _CellMenuAction.replace, child: Text('替换图片')),
        PopupMenuItem(value: _CellMenuAction.reset, child: Text('重置缩放与位置')),
        PopupMenuItem(value: _CellMenuAction.remove, child: Text('移除替换')),
      ],
    );
    if (selected == null) return;
    if (!mounted) return;
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    switch (selected) {
      case _CellMenuAction.replace:
        await notifier.pickCellImage(widget.cellIndex);
      case _CellMenuAction.reset:
        notifier.setCellScale(widget.cellIndex, kDefaultCellScale);
        notifier.setCellOffset(widget.cellIndex, kCellOffsetZero);
      case _CellMenuAction.remove:
        notifier.resetCell(widget.cellIndex);
    }
  }
}

enum _CellMenuAction { replace, reset, remove }

/// Build the accessibility label for a replaced cell.
///
/// Pattern: "第N格（第R行 第C列）图片，双指缩放或拖动调整".
String _cellLabel(int index, {required int rows, required int cols}) {
  final r = cols > 0 ? index ~/ cols : 0;
  final c = cols > 0 ? index % cols : 0;
  return '第${index + 1}格（第${r + 1}行 第${c + 1}列）图片，双指缩放或拖动调整';
}
