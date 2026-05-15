import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/imported_image.dart';
import '../../domain/usecases/compute_center_transform.dart';
import '../providers/grid_editor_provider.dart';

/// Interactive overlay sitting on top of the 5th cell when nine-grid-
/// social mode is on.
///
/// States:
/// * **Empty**: shows an `add_a_photo` icon + "替换图片" CTA (mirrors
///   `_3_宫格切图/code.html` lines 132–135). Tapping invokes the
///   gallery picker via [GridEditorController.pickCenterImage].
/// * **Replaced**: renders the user-picked image with a
///   [GestureDetector] driving scale + pan (PRD: "pinch-to-zoom +
///   pan").
///
/// The widget operates in **cell-local** pixel coordinates. The parent
/// (`GridPreviewCanvas`) positions / sizes it to match the 5th rect in
/// the active grid layout.
///
/// **Unit convention**: the controller and renderer both treat
/// [GridEditorState.centerOffset] as **source-pixel** units (i.e. the
/// 5th cell's source coordinate space — see
/// `_currentCenterCellExtent` in `grid_editor_provider.dart`). This
/// widget receives the cell's **widget-pixel** size via [cellWidth] /
/// [cellHeight] and the matching **source-pixel** size via
/// [sourceCellWidth] / [sourceCellHeight]; the constructor computes
/// the ratio so the gesture handler converts widget-pixel deltas into
/// source-pixel deltas before storing them and the renderer converts
/// the stored source-pixel offset back into widget pixels for
/// `Positioned`. Keeping the unit aligned end-to-end is what makes the
/// preview match the export.
class CenterCellOverlay extends ConsumerStatefulWidget {
  const CenterCellOverlay({
    super.key,
    required this.cellWidth,
    required this.cellHeight,
    required this.sourceCellWidth,
    required this.sourceCellHeight,
  });

  /// Cell side length in **rendered (UI) pixels** — used to size the
  /// gesture surface and lay out the [_CenterImageRender] inside the
  /// parent `Positioned`.
  final double cellWidth;
  final double cellHeight;

  /// Cell side length in **source-image pixels** (i.e. one of the 9
  /// cells produced by splitting the editor's source image into 3×3).
  /// Used to convert widget-pixel gesture deltas to / from the
  /// source-pixel offset that the controller and renderer both speak.
  final double sourceCellWidth;
  final double sourceCellHeight;

  @override
  ConsumerState<CenterCellOverlay> createState() => _CenterCellOverlayState();
}

class _CenterCellOverlayState extends ConsumerState<CenterCellOverlay> {
  // Live scale / offset / focal point captured at gesture start so we
  // can compute "since-start" deltas — `ScaleUpdateDetails.scale` is
  // cumulative since start, but `focalPointDelta` is per-event, so we
  // use `localFocalPoint - startLocalFocalPoint` instead to keep the
  // pan additive in lock-step with the scale.
  double? _gestureStartScale;
  CenterOffset? _gestureStartOffset;
  Offset? _gestureStartFocalPoint;

  /// Multiplier converting **widget-pixel** lengths into **source-pixel**
  /// lengths. The controller's offset clamp and the renderer both
  /// reason in source-pixel space, so we convert widget-pixel gesture
  /// deltas through this factor before storing the result.
  double get _sourcePerWidget {
    if (widget.cellWidth <= 0) return 1;
    return widget.sourceCellWidth / widget.cellWidth;
  }

  /// Multiplier converting **source-pixel** lengths into **widget-pixel**
  /// lengths — the inverse of [_sourcePerWidget]. Used when the
  /// preview reads back the stored offset to position the image.
  double get _widgetPerSource {
    if (widget.sourceCellWidth <= 0) return 1;
    return widget.cellWidth / widget.sourceCellWidth;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    final centerImage = state.centerImage;

    if (centerImage == null) {
      return _CenterCtaButton(onTap: notifier.pickCenterImage);
    }

    return Semantics(
      label: '中心格图片，双指缩放或拖动调整',
      hint: '长按以打开图片操作菜单',
      onLongPressHint: '打开图片菜单',
      onLongPress: () => _showImageMenu(context, notifier),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _gestureStartScale = state.centerScale;
          _gestureStartOffset = state.centerOffset;
          _gestureStartFocalPoint = details.localFocalPoint;
        },
        onScaleUpdate: (details) => _onScaleUpdate(details, centerImage),
        onScaleEnd: (_) {
          _gestureStartScale = null;
          _gestureStartOffset = null;
          _gestureStartFocalPoint = null;
        },
        onLongPress: () => _showImageMenu(context, notifier),
        child: ClipRect(
          child: _CenterImageRender(
            image: centerImage,
            cellWidth: widget.cellWidth,
            cellHeight: widget.cellHeight,
            widgetPerSource: _widgetPerSource,
            userScale: state.centerScale,
            offset: state.centerOffset,
          ),
        ),
      ),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details, ImportedImage centerImage) {
    final startScale =
        _gestureStartScale ??
        ref.read(gridEditorControllerProvider).centerScale;
    final startOffset =
        _gestureStartOffset ??
        ref.read(gridEditorControllerProvider).centerOffset;
    final startFocal = _gestureStartFocalPoint ?? details.localFocalPoint;
    final newScale = startScale * details.scale;
    // `details.scale` is "since gesture start"; we use the same
    // since-start convention for pan by deriving the cumulative
    // focal-point delta ourselves (gesture detector's `focalPointDelta`
    // is per-event, which would only apply the most recent frame's
    // movement onto `startOffset`). Multiplying by `_sourcePerWidget`
    // converts widget-local pixels into the source-pixel units the
    // controller and renderer both speak.
    final perWidget = _sourcePerWidget;
    final dxWidget = details.localFocalPoint.dx - startFocal.dx;
    final dyWidget = details.localFocalPoint.dy - startFocal.dy;
    final newOffset = CenterOffset(
      startOffset.dx + dxWidget * perWidget,
      startOffset.dy + dyWidget * perWidget,
    );
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    // Apply scale first (so the offset clamp uses the right scale).
    notifier.setCenterScale(newScale);
    notifier.setCenterOffset(newOffset);
  }

  Future<void> _showImageMenu(
    BuildContext context,
    GridEditorController notifier,
  ) async {
    final action = await showModalBottomSheet<_CenterImageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('更换图片'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CenterImageAction.replace),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('恢复默认位置'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CenterImageAction.reset),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除图片'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_CenterImageAction.remove),
              ),
            ],
          ),
        );
      },
    );
    switch (action) {
      case _CenterImageAction.replace:
        await notifier.pickCenterImage();
      case _CenterImageAction.reset:
        notifier.setCenterScale(kDefaultCenterScale);
        notifier.setCenterOffset(kCenterOffsetZero);
      case _CenterImageAction.remove:
        notifier.setCenterImage(null);
      case null:
        break;
    }
  }
}

enum _CenterImageAction { replace, reset, remove }

class _CenterCtaButton extends StatelessWidget {
  const _CenterCtaButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '替换中心格图片',
      child: Material(
        color: Colors.black.withValues(alpha: 0.2),
        child: InkWell(
          onTap: onTap,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_a_photo, color: Colors.white, size: 32),
                SizedBox(height: 6),
                Text(
                  '替换图片',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure rendering of the scaled/translated center image. Lives in its
/// own widget so the gesture handler doesn't rebuild the
/// [Image.memory] decoder on every drag event.
class _CenterImageRender extends StatelessWidget {
  const _CenterImageRender({
    required this.image,
    required this.cellWidth,
    required this.cellHeight,
    required this.widgetPerSource,
    required this.userScale,
    required this.offset,
  });

  final ImportedImage image;
  final double cellWidth;
  final double cellHeight;

  /// Multiplier converting **source-pixel** lengths into **widget-pixel**
  /// lengths. Used to render the stored [offset] (which lives in
  /// source-pixel space, matching the controller and renderer) as a
  /// widget-pixel shift on top of the cell.
  final double widgetPerSource;

  /// Cover-relative scale, `1.0` = image just covers the cell.
  final double userScale;
  final CenterOffset offset;

  @override
  Widget build(BuildContext context) {
    // `userScale` is cover-relative, so the rendered pixel size is the
    // image's natural size times (coverScale × userScale).
    final cover = coverScaleFactor(
      imageWidth: image.width,
      imageHeight: image.height,
      cellWidth: cellWidth.round(),
      cellHeight: cellHeight.round(),
    );
    final effectiveScale = cover * userScale;
    final renderedWidth = image.width * effectiveScale;
    final renderedHeight = image.height * effectiveScale;

    // Convert the stored source-pixel offset back into widget-pixel
    // shift so the visible composition matches what the renderer will
    // produce on export (see `_composeCenterCell` in
    // `grid_image_renderer.dart`).
    final offsetWidgetX = offset.dx * widgetPerSource;
    final offsetWidgetY = offset.dy * widgetPerSource;

    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: (cellWidth - renderedWidth) / 2 + offsetWidgetX,
            top: (cellHeight - renderedHeight) / 2 + offsetWidgetY,
            width: renderedWidth,
            height: renderedHeight,
            child: Image.memory(
              image.bytes,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );
  }
}
