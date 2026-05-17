/// Grid-split shapes supported by the editor (Subtask A — 05-17 revamp).
///
/// Modeled as a regular enum (not sealed) because the matrix shape can
/// be looked up via the [rows] / [cols] extension getters — there is no
/// per-variant logic that needs exhaustive switching at call sites.
/// Members are named with `g<rows>x<cols>` for sort-friendly listing.
///
/// The domain entity is deliberately Flutter-free; widgets render
/// [displayTitle] / [displayDescription] directly.
enum GridType { g1x2, g1x3, g2x2, g2x3, g3x3 }

/// Matrix dimensions + display metadata for [GridType]. Centralizing
/// these here keeps the cell-rect math and the type-selector widget in
/// agreement.
extension GridTypeInfo on GridType {
  int get rows {
    switch (this) {
      case GridType.g1x2:
      case GridType.g1x3:
        return 1;
      case GridType.g2x2:
      case GridType.g2x3:
        return 2;
      case GridType.g3x3:
        return 3;
    }
  }

  int get cols {
    switch (this) {
      case GridType.g1x2:
      case GridType.g2x2:
        return 2;
      case GridType.g1x3:
      case GridType.g2x3:
      case GridType.g3x3:
        return 3;
    }
  }

  int get cellCount => rows * cols;

  /// Human-readable label (e.g. `1x2`, `3x3`) used by debug helpers and
  /// existing tests. Kept stable across the 05-17 revamp.
  String get displayLabel => '${rows}x$cols';

  /// 中文主标题（卡片第一行）。文案与 PRD 05-17 表格保持一致。
  String get displayTitle {
    switch (this) {
      case GridType.g1x2:
        return '二宫格';
      case GridType.g1x3:
        return '三宫格';
      case GridType.g2x2:
        return '四宫格';
      case GridType.g2x3:
        return '六宫格';
      case GridType.g3x3:
        return '九宫格';
    }
  }

  /// 中文描述（卡片第二行）。文案与 PRD 05-17 表格保持一致。
  String get displayDescription {
    switch (this) {
      case GridType.g1x2:
        return '横向两格，左右对照';
      case GridType.g1x3:
        return '横向三格，长卷分屏';
      case GridType.g2x2:
        return '方正四格，万能切片';
      case GridType.g2x3:
        return '横向六格，时间轴友好';
      case GridType.g3x3:
        return '朋友圈经典';
    }
  }
}

/// Iteration order shown in the type selector — Subtask A keeps only
/// the five shapes from the 05-17 PRD.
const List<GridType> kGridTypeSelectorOrder = <GridType>[
  GridType.g1x2,
  GridType.g1x3,
  GridType.g2x2,
  GridType.g2x3,
  GridType.g3x3,
];
