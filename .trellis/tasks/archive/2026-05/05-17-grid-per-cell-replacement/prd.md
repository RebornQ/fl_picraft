# Subtask C — per-cell 图片替换 + 泛化 CellOverlay

> Parent: `05-17-grid-slice-revamp`
> Depends on: Subtask B（几何模型已切成正方形，9-grid-social 字段已清理）

## Goal

把「中心格替换」泛化为「任意格替换」。state 用 `Map<int, CellReplacement>` 承载 per-cell 图片 + scale + offset；UI 把 `CenterCellOverlay` 重命名为 `CellOverlay` 并挂到所有 cells；renderer 按 index 决定每格走源图切片还是合成替换图。

## Requirements

### R1 State shape：per-cell replacement map
* 新增 domain value type `CellReplacement`，字段：
  ```dart
  class CellReplacement {
    final ImportedImage image;
    final double scale;       // cover-relative
    final CellOffset offset;  // source-pixel units
  }
  ```
* `CellOffset` 沿用 `CenterOffset` 的 dx/dy 模型（建议直接重命名 `CenterOffset` → `CellOffset`）
* `GridEditorState` 新增 `Map<int, CellReplacement> cellReplacements`（不可变，copyWith 时整 Map 替换）
* 默认值：空 Map

### R2 切换 GridType 清空替换（PRD R7）
* `GridEditorController.setGridType` 中：当新 type ≠ 当前 type 时，`cellReplacements = const {}`
* 保持 `spacing` / `cornerRadius` / source 图片不变

### R3 CellOverlay 通用化
* 把 `center_cell_overlay.dart` 重命名为 `cell_overlay.dart`
* `CenterCellOverlay` widget 重命名为 `CellOverlay`，构造新增 `final int cellIndex`
* widget 内部用 `state.cellReplacements[cellIndex]` 取/写当前格的替换
* 行为不变：空态 tap 触发 picker；已替换态 pinch / pan / longpress 菜单（替换 / 重置 / 移除）
* 单位换算契约保持：widget-pixel ↔ source-pixel，使用每格独立的 `sourceCellWidth/Height`

### R4 GridPreviewCanvas 挂载所有 cells
* `_PreviewSurface` 内遍历 `computeGridLayout(...).rects`，每个 rect 挂一个 `CellOverlay(cellIndex: i, …)`
* 透明 hit target 覆盖整格，确保未替换格也能 tap 唤起 picker
* IgnorePointer 的网格线层放在 CellOverlay 之上时需让 hit-test 穿透（沿用现有方案）

### R5 GridEditorController per-cell 接口
* `pickCellImage(int cellIndex)` — 调 picker，结果写入 `cellReplacements[cellIndex]`
* `setCellImage(int cellIndex, ImportedImage? image)` — null 时移除该 cell 的替换
* `setCellScale(int cellIndex, double scale)`
* `setCellOffset(int cellIndex, CellOffset offset)`
* `resetCell(int cellIndex)` — 等同 `setCellImage(cellIndex, null)`

### R6 Renderer 接收 per-cell map
* `GridRenderRequest` 新增 `Map<int, CellReplacementBytes>`，其中 `CellReplacementBytes { Uint8List bytes; int width; int height; double scale; CellOffset offset; }`
* `_renderInIsolate` 遍历 layout rects 时：
  * `cellReplacements[i] != null` → 用 `_composeReplacementCell`（沿用 `_composeCenterCell` 的合成逻辑，重命名）
  * 否则 → 现有 `img.copyCrop` 切源图
* `GridRenderRequest.fromState` 把 state 的 `cellReplacements` 序列化为 `Map<int, CellReplacementBytes>`

### R7 重命名 / 通用化收尾
* `compute_center_transform.dart` → `compute_cell_transform.dart`；导出 `kDefaultCellScale` / `kCellOffsetZero` 等常量
* 所有 `center*` 命名替换为 `cell*`（grep 检查）
* 测试夹具同步更新

### R8 hit-test 与无障碍
* `CellOverlay` 的 `Semantics` label 模板：`第${index+1}格（${rowName}${colName}）图片，双指缩放或拖动`
* 已替换态保留 longpress hint「打开图片菜单」
* 行优先 index → 「行 r 列 c」的中文翻译辅助函数放在 `cell_overlay.dart` 内部

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format .` clean
* [ ] `flutter test` clean
* [ ] `GridEditorState.cellReplacements` 单元测试：copyWith 不变性、切类型清空、setCell* 接口语义
* [ ] `CellOverlay` widget test：空态 tap → picker；已替换态 pinch/pan/longpress 菜单
* [ ] Renderer 单元测试：mixed map（部分格替换 + 部分格走源切片）输出张数正确、被替换格像素 ≠ 源图切片
* [ ] 切换 GridType 后所有 `cellReplacements` 被清空（provider 测试）
* [ ] 既有 9-grid-social 中心格替换测试改写为「3×3 + 第 5 格替换」并通过
* [ ] 无 `center` / `nineGrid` 残留命名（grep 通过）

## Out of Scope

* 拖拽换序
* 一次性批量替换多格
* 替换图自带 picker UI 改造
* 视图侧默认动效 / 转场（保持现状）

## Technical Notes

* 关键文件：
  * `lib/features/grid/domain/entities/grid_editor_state.dart` — 新增 `cellReplacements` map
  * `lib/features/grid/domain/usecases/compute_cell_transform.dart` — 改名 + 常量
  * `lib/features/grid/domain/usecases/grid_render_request.dart` — per-cell map 字段
  * `lib/features/grid/data/renderers/grid_image_renderer.dart` — `_composeReplacementCell` 分发
  * `lib/features/grid/presentation/providers/grid_editor_provider.dart` — 新增 5 个 per-cell 接口
  * `lib/features/grid/presentation/widgets/cell_overlay.dart` — 改名 + 通用化
  * `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` — 每个 rect 挂 CellOverlay
* 性能：N 张替换图 + 源图 → 渲染时复用 isolate；CellReplacementBytes 用 `Uint8List`，避免 Flutter widget 越过 isolate 边界
* 内存：CellReplacement 持有 `ImportedImage`（已含 bytes），切类型清空 = GC 友好
* hit-test：现有 `IgnorePointer` 网格线层位于 CellOverlay 之上时，`IgnorePointer(ignoring: true)` 已让 hit-test 穿透——保持现状
