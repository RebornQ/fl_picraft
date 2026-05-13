/// The 9 anchor points a watermark can snap to on the export canvas.
///
/// Naming follows vertical-horizontal: e.g. [topLeft] = top edge,
/// left edge. [middleCenter] is geometric center. The export UI lays
/// these out as a 3x3 grid where row index corresponds to the vertical
/// alignment (top/middle/bottom) and column index to the horizontal
/// alignment (left/center/right).
enum WatermarkAnchor {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleCenter,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  /// Row index 0..2 (top → bottom).
  int get row => index ~/ 3;

  /// Column index 0..2 (left → right).
  int get column => index % 3;
}
