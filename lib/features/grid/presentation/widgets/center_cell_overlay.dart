import 'package:flutter/material.dart';

/// Placeholder widget retained between 05-17 Subtask B and Subtask C.
///
/// Subtask B removed the 9-grid-social mode (and the controller methods
/// this overlay depended on — `pickCenterImage`, `setCenterImage`,
/// `setCenterScale`, `setCenterOffset`). The file itself is preserved
/// because Subtask C will reintroduce a generalized `CellOverlay` widget
/// that takes over per-cell replacement for every cell index, and the
/// shape / location of this file makes the migration obvious.
///
/// No live call site mounts this widget today — [GridPreviewCanvas] no
/// longer composes a center overlay since every grid mode operates on a
/// `cols / rows` crop with uniform square cells. Subtask C will replace
/// this stub.
class CenterCellOverlay extends StatelessWidget {
  const CenterCellOverlay({
    super.key,
    required this.cellWidth,
    required this.cellHeight,
    required this.sourceCellWidth,
    required this.sourceCellHeight,
  });

  final double cellWidth;
  final double cellHeight;
  final double sourceCellWidth;
  final double sourceCellHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: cellWidth, height: cellHeight);
  }
}
