/// All 11 grid types supported by the grid-split editor (PRD §4.1).
///
/// Modeled as a regular enum (not sealed) because the matrix shape can
/// be looked up via the [rows] / [cols] extension getters — there is no
/// per-variant logic that needs exhaustive switching at call sites.
/// Members are named with `g<rows>x<cols>` for sort-friendly listing.
///
/// The domain entity is deliberately Flutter-free; the icon mapping
/// used by the selector lives in
/// `presentation/widgets/grid_type_icons.dart` so the UI dependency
/// never leaks past `presentation/`.
enum GridType {
  g1x2,
  g2x1,
  g1x3,
  g3x1,
  g1x4,
  g4x1,
  g2x2,
  g2x3,
  g3x2,
  g3x3,
  g4x4,
}

/// Matrix dimensions + display metadata for [GridType]. Centralizing
/// these here keeps the cell-rect math and the type-selector widget in
/// agreement.
extension GridTypeInfo on GridType {
  int get rows {
    switch (this) {
      case GridType.g1x2:
      case GridType.g1x3:
      case GridType.g1x4:
        return 1;
      case GridType.g2x1:
      case GridType.g2x2:
      case GridType.g2x3:
        return 2;
      case GridType.g3x1:
      case GridType.g3x2:
      case GridType.g3x3:
        return 3;
      case GridType.g4x1:
      case GridType.g4x4:
        return 4;
    }
  }

  int get cols {
    switch (this) {
      case GridType.g2x1:
      case GridType.g3x1:
      case GridType.g4x1:
        return 1;
      case GridType.g1x2:
      case GridType.g2x2:
      case GridType.g3x2:
        return 2;
      case GridType.g1x3:
      case GridType.g2x3:
      case GridType.g3x3:
        return 3;
      case GridType.g1x4:
      case GridType.g4x4:
        return 4;
    }
  }

  int get cellCount => rows * cols;

  /// Human-readable label (e.g. `1x2`, `3x3`) used by the selector
  /// cards.
  String get displayLabel => '${rows}x$cols';
}

/// Iteration order shown in the type selector — matches the order in
/// the design mock (`_3_宫格切图/code.html` lines 158–201).
const List<GridType> kGridTypeSelectorOrder = <GridType>[
  GridType.g1x2,
  GridType.g2x1,
  GridType.g1x3,
  GridType.g3x1,
  GridType.g1x4,
  GridType.g4x1,
  GridType.g2x2,
  GridType.g2x3,
  GridType.g3x2,
  GridType.g3x3,
  GridType.g4x4,
];
