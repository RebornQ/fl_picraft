# Regular Grid Split

> Subtask of [`05-08-grid-split`](../05-08-grid-split/prd.md)

## Goal

Implement 11 grid types that split a single source image into a matrix of sub-images. Provides a live grid-line overlay on the preview, generates per-cell PNG outputs, and supports spacing and corner radius.

## Supported grid types (Total PRD §4.1)

| Type | Rows × Cols | Cell count |
|------|-------------|------------|
| 1x2 | 1 × 2 | 2 |
| 2x1 | 2 × 1 | 2 |
| 1x3 | 1 × 3 | 3 |
| 3x1 | 3 × 1 | 3 |
| 1x4 | 1 × 4 | 4 |
| 4x1 | 4 × 1 | 4 |
| 2x2 | 2 × 2 | 4 |
| 2x3 | 2 × 3 | 6 |
| 3x2 | 3 × 2 | 6 |
| 3x3 | 3 × 3 | 9 |
| 4x4 | 4 × 4 | 16 |

## Algorithm

```dart
final cellW = (sourceWidth  - spacing * (cols - 1)) / cols;
final cellH = (sourceHeight - spacing * (rows - 1)) / rows;

for (var r = 0; r < rows; r++) {
  for (var c = 0; c < cols; c++) {
    final x = c * (cellW + spacing);
    final y = r * (cellH + spacing);
    final cellImage = source.copyCrop(x, y, cellW, cellH);
    if (radius > 0) cellImage.applyRoundedCorners(radius);
    output.add(cellImage);
  }
}
```

Order convention: row-major (left-to-right, top-to-bottom).

## UI surface

UI ref: `_3_宫格切图/code.html`

- **Preview canvas** (aspect-square, lines 119–141): source image fills canvas, grid overlay drawn with `border-r border-b border-white/40` per cell
- **Mode toggle card** (lines 144–153): 九宫格朋友圈模式 — when **off**, this subtask owns the experience; when **on**, delegates to `nine-grid-social`
- **Grid type selector** (lines 156–202): horizontal scroll, 80x80 cards with material symbol previews. Active card uses `bg-primary-container border-primary shadow-md`
- **Bento parameter cards** (lines 204–220): 宫格间距 0px (tertiary container), 圆角大小 12px (secondary container)
- **FAB** (lines 242–247): floating export with `output` icon

## State

```dart
@riverpod
class GridEditor extends _$GridEditor {
  GridEditorState build() => GridEditorState.initial(); // type=3x3, spacing=0, radius=12

  void setGridType(GridType t) { ... }
  void setSpacing(double px) { ... }
  void setRadius(double px) { ... }
  Future<List<Uint8List>> renderCells() async { ... }
}

enum GridType { x1_2, x2_1, x1_3, x3_1, x1_4, x4_1, x2_2, x2_3, x3_2, x3_3, x4_4 }
```

## Edge cases

| Case | Behavior |
|------|----------|
| Source not square but grid expects square cells (e.g. 3x3 social) | Crop to center square first (only for the social subtask) |
| `cellW * cols + spacing * (cols-1) > sourceWidth` due to rounding | Distribute residual pixels to last column |
| Source smaller than minimum cell size (e.g. 100px) | Show inline warning "图片过小，子图可能模糊" |

## Acceptance Criteria

- [ ] All 11 grid types selectable; preview overlay updates instantly
- [ ] Cell count matches expectation per type
- [ ] Spacing slider visibly adjusts gaps in preview
- [ ] Radius slider rounds the corners of each cell
- [ ] Export produces N PNG files (N = cell count) in row-major order

## Definition of Done

- Unit tests for cell-rect math across all 11 grid types
- Widget test for grid type selector
- `flutter analyze` clean

## Out of Scope

- Custom grid (e.g. 5x5, irregular) — only the 11 fixed types
- Per-cell text overlay
- Center cell replacement (handled by `nine-grid-social`)

## Dependencies

- Requires: `05-08-image-import`, `05-08-base-architecture`
- Sibling: `05-08-nine-grid-social`

## References

- Total PRD §4.1 普通宫格切图
- UI: `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_3_宫格切图/code.html`
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/component-guidelines.md`
