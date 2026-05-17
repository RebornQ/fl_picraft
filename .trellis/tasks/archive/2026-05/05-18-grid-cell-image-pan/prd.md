# 宫格替换后支持拖拽平移替换图

## Goal

修复"宫格模式替换图片后，单指拖动无效（图片原地不动）"的 bug，使替换后的图片可以在 cover-fit clamp
范围内自然拖拽平移。

## Root Cause

`lib/features/grid/presentation/providers/grid_editor_provider.dart:182-225` 的
`setCellScale` / `setCellOffset` 在调用 `clampCellOffset` 时，使用**替换图自身的 width/height**
作为 `cellWidth/cellHeight` 参数（注释解释为 "cell-shape proxy"）：

```dart
clampCellOffset(
  imageWidth: current.image.width,
  imageHeight: current.image.height,
  cellWidth: current.image.width,    // ← 错误：用 image 自己当 cell 形状
  cellHeight: current.image.height,  // ← 错误
  userScale: current.scale,
);
```

当 `cellWidth == imageWidth` 时：

```
coverScaleFactor = max(cellW/imageW, cellH/imageH) = max(1, 1) = 1.0
effective = 1.0 × userScale
scaledW = imageW × userScale
maxDx = (imageW × userScale - imageW) / 2 = imageW × (userScale - 1) / 2
```

因此 **userScale = 1.0 时 maxDx = maxDy = 0**，任何 offset 都被 clamp 到零——用户拖动看不到效果。
`setCellScale` 内部对 offset 的 re-clamp 也有同样 bug。

注释声称 "the widget additionally clamps against its on-screen extent"，但 widget
(`cell_overlay.dart:233-262 _onScaleUpdate`) 并没有额外 clamp，只是把 widget-pixel delta
换算到 source-pixel 后直接喂给 provider。这是 05-17 任务遗留的 incomplete refactoring。

既有 `test/features/grid/presentation/grid_editor_drag_isolation_test.dart:60-63` 仅用
`scale=2.0` 测试 offset (5,5)，所以默认 scale=1.0 的拖动锁死从未被测试覆盖。

## Requirements

* **R1**: `setCellOffset` 接受 `cellWidth` / `cellHeight`（source-pixel 单位）参数，
  用于 `clampCellOffset` 调用，替代当前用 image 自身宽高作为 cell-shape proxy 的逻辑。
* **R2**: `setCellScale` 接受同样的 `cellWidth` / `cellHeight` 参数，用于 re-clamp offset。
* **R3**: `_ReplacedCell._onScaleUpdate` 调用 provider 时传入 `widget.sourceCellWidth` /
  `widget.sourceCellHeight`（已存在于 `CellOverlay` 构造函数）。
* **R4**: 保持 "cover-fit 内有限拖动" 语义——cell 永远不出空白，clamp 边界由真实 cell
  尺寸 + image 尺寸 + userScale 共同决定。
* **R5**: 既有 API 行为差异需在测试层显式标注；API 签名变化是 breaking change，所有
  test 调用方需要同步更新。

## Acceptance Criteria

* [ ] **AC1**: `flutter analyze` clean
* [ ] **AC2**: `dart format .` clean
* [ ] **AC3**: `flutter test` clean
* [ ] **AC4**: 既有 `grid_editor_drag_isolation_test.dart` 全部通过（按新 API 签名更新调用）
* [ ] **AC5**: 既有 `cell_overlay_test.dart` 全部通过（如有需要按新签名更新）
* [ ] **AC6**: 新增 widget test：构造非同 aspect 替换图（如 horizontal 400×200 image 配
  square cell），在 `_ReplacedCell` 上模拟单指拖动 → 断言
  `state.cellReplacements[index].offset` 非零（即 clamp 不再把 offset 压成零）
* [ ] **AC7**: 新增 widget test 或 unit test：双指放大（scale > 1.0）后，offset 在两轴
  均可非零，验证 re-clamp 正确

## Definition of Done

* Tests 全部通过（unit + widget）
* lint / format / analyze 全部 clean
* 既有功能不退化（特别是 05-17 的 multi-replace、05-18-A 的 grid lines fade）

## Out of Scope

* "拖动可发现性" UI 提示（即"双指放大后才能拖"的 onboarding hint）
* 同 aspect 替换图的特殊处理（cover-fit 自然语义即两轴皆 0，不再额外提示用户）
* long_stitch 等其它 feature 的同类 clamp 检查（若存在视作独立任务）
* 支持 cell 外露空白（即放弃 cover-fit / "Instagram 式自由 pan"）
* 默认 scale 提升到 buffer 值（保持 1.0）

## Technical Approach

### 改动定位

**Provider 层** (`lib/features/grid/presentation/providers/grid_editor_provider.dart`)

* `setCellOffset(int cellIndex, CellOffset offset, {required int cellWidth, required int cellHeight})`
* `setCellScale(int cellIndex, double scale, {required int cellWidth, required int cellHeight})`
* `cellWidth/cellHeight` 是 source-pixel 单位（与 `GridRenderRequest` 渲染时使用的 cell
  尺寸一致），由 widget 通过 `sourceCellWidth/sourceCellHeight` 提供
* 内部 `clampCellOffset` / `clampCellTransform` 调用换成接受的参数

**Widget 层** (`lib/features/grid/presentation/widgets/cell_overlay.dart`)

* `_ReplacedCell._onScaleUpdate` 调用：

  ```dart
  notifier.setCellScale(
    widget.cellIndex,
    newScale,
    cellWidth: widget.sourceCellWidth.round(),
    cellHeight: widget.sourceCellHeight.round(),
  );
  notifier.setCellOffset(
    widget.cellIndex,
    newOffset,
    cellWidth: widget.sourceCellWidth.round(),
    cellHeight: widget.sourceCellHeight.round(),
  );
  ```
* 长按菜单的 reset 路径（"重置缩放与位置"）同样需要传入 cellWidth/Height

### 测试改动

* `test/features/grid/presentation/grid_editor_drag_isolation_test.dart`：补 cellWidth/Height
  参数；保留语义
* 新增 widget test 文件（如 `test/features/grid/presentation/grid_cell_image_pan_test.dart`）
  覆盖 AC6 / AC7

### 风险评估

* **Breaking change**：`setCellOffset` / `setCellScale` 签名变化——只有
  `_ReplacedCell._onScaleUpdate` 和测试是 caller，影响面可控
* **行为差异**：修复后默认 scale=1.0 下，**非同 aspect** 的替换图会因 clamp 真实生效
  而呈现 cover-fit 居中状态；用户拖动可看到被裁部分。这是修 bug 而非新行为，**符合
  05-17 PRD 的 R-DRAG-05 通用化精神**

## Decision (ADR-lite)

**Context**: 替换图的 clamp 用 image 自身宽高作为 cell-shape proxy 是 05-17 任务遗留的
incomplete refactoring；旧设计可能受 legacy center-cell-only 的单一形状语义影响。

**Decision**: 把 cell 尺寸（source-pixel 单位）作为 provider API 显式入参，由 widget
透传 `sourceCellWidth/Height`。Domain 层 `clampCellOffset` / `clampCellTransform` 签名
本身不变（已经接受 cellW/H），仅修 provider 调用。

**Consequences**:
* ✅ 拖动行为正确（cover-fit clamp 用真实 cell 几何计算）
* ✅ Domain 层无改动，concept 边界保持
* ⚠️ Provider API 变 breaking——`_ReplacedCell` 和测试需同步更新
* ⚠️ 同 aspect 替换图仍无法在 scale=1.0 拖动（cover-fit 自然语义），属预期行为

## Technical Notes

### 涉及文件

* `lib/features/grid/presentation/providers/grid_editor_provider.dart`
  （`setCellOffset`、`setCellScale`）
* `lib/features/grid/presentation/widgets/cell_overlay.dart`
  （`_ReplacedCell._onScaleUpdate`、长按菜单 reset 路径）
* `test/features/grid/presentation/grid_editor_drag_isolation_test.dart`
* `test/features/grid/presentation/grid_cell_image_pan_test.dart`（新增）

### 既有约束

* `compute_cell_transform.dart` 的 `clampCellOffset` / `clampCellTransform` 已经支持
  cellWidth/Height 参数，**无需改 domain 层**
* `CellOverlay` 已经接收 `sourceCellWidth` / `sourceCellHeight`，链路畅通
* `grid_preview_canvas.dart:241-249` 的 `CellOverlay` 实例化已经传入 source cell 尺寸

### 参考

* 05-17 grid-per-cell-replacement PRD（per-cell 重构起点）
* 05-17 cell-replace-multiple-times PRD（手势竞技场分工说明）
* `compute_cell_transform.dart:107-129`（clamp 公式）
* `frontend/component-guidelines.md`（手势 / opacity / hit-test 规范）

## Research References

（无 — 决策完全通过代码库检查 + 与用户的 Q&A 完成。）
