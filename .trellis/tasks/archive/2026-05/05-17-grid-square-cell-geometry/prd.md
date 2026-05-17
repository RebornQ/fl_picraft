# Subtask B — 正方形 cell 几何 + canvas aspect=cols:rows

> Parent: `05-17-grid-slice-revamp`
> Depends on: Subtask A（GridType 已精简至 5 种）

## Goal

把宫格切图的几何模型从「画布固定 1:1、cells 继承源图比例」改为「画布 = `cols:rows`、cells 始终正方形且等大」。同时彻底删除 9-grid-social 模式相关字段与逻辑，为 Subtask C 的 per-cell 替换提供干净的几何契约。

## Requirements

### R1 Canvas aspect 改为 cols:rows
* `GridEditorScreen` 三处 `AspectRatio(aspectRatio: 1, child: GridPreviewCanvas())` 改为 `AspectRatio(aspectRatio: cols/rows, child: GridPreviewCanvas())`，其中 cols/rows 来自当前 `state.gridType`
* 三处指：compact 单列 / medium 单列 / expanded+large 双列布局
* `_kGridControlsPanelMinWidth` / `_kGridControlsPanelMaxWidth` 与外层 layout 逻辑保持不变
* 画布最大尺寸仍按「height-first」原则，宽度自适应 aspect

### R2 computeGridLayout 输出等大正方形
* 输入由 `(sourceWidth, sourceHeight, type, spacing)` 改为 `(canvasSide, type, spacing)`：以 `canvasSide`（短边像素）作为单位 cell 的边长，输出 N×M 个 `canvasSide × canvasSide` 的正方形矩形
* 实际签名：`computeGridLayout({required int cellSide, required GridType type, double spacing = 0})`，每格 `width = height = cellSide`，`x = c * (cellSide + spacing)`，`y = r * (cellSide + spacing)`
* `GridLayout` 数据结构保持不变（rows / cols / rects）

### R3 ST-C 源图 pan/zoom 适配 cols:rows
* `compute_source_crop.dart` 中现有 `clampSourceScale` / `clampSourceOffset` 假设目标是 1:1 正方形；扩展为接收 `targetAspect`（= `cols/rows`）参数
* 默认值保留 `1.0` 以最小化调用方迁移
* `sourceTooSmall` 计算同步根据 `cols × cellSide` 和 `rows × cellSide` 判断

### R4 Renderer 输出正方形 cells
* `grid_image_renderer.dart` 的 `_renderInIsolate` 把 `img.copyCrop` 的目标坐标从源图比例改为「先 crop 源图到 `cols:rows` 区域，再按 `computeGridLayout` 切等大正方形」
* 输出 PNG 张数仍 = `cellCount`；每张为正方形像素图
* 圆角 / spacing 行为保留

### R5 删除 9-grid-social 字段与逻辑
* `GridEditorState`：删除 `nineGridSocialMode`、`centerImage`、`centerScale`、`centerOffset`、`clearCenterImage` 相关字段（per-cell 字段由 Subtask C 引入，本 subtask 只删旧）
* `GridEditorController`：删除 `pickCenterImage` / `setCenterImage` / `setCenterScale` / `setCenterOffset` / `toggleNineGridSocialMode` 等接口
* `GridRenderRequest`：删除 `nineGridSocialMode` / `centerImageBytes` / `centerScale` / `centerOffset` / `hasCenterReplacement`
* `kCenterCellIndex` 特例分支整体移除
* `CenterCellOverlay` 临时降级为「无功能」占位（由 Subtask C 重命名为 `CellOverlay` 并接管所有 cells；本 subtask 保留但仅渲染源图切片）

### R6 GridControlsPanel 清理
* 删除 9-grid-social toggle 相关 widget（Subtask A 已隐藏，本 subtask 删 code）
* `GridTypeSelector` 的 `lockedTo` 参数可删除

### R7 GridPreviewCanvas 重渲染
* `_PreviewSurface` 内的源图 `Image.memory` 走新的 `cols:rows` crop 计算
* 网格线绘制按 `computeGridLayout` 的 rects 渲染（不变）
* 临时不挂 `CenterCellOverlay`（由 Subtask C 接管为通用 `CellOverlay`）

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format .` clean
* [ ] `flutter test` clean（含改写后的 grid layout / renderer 测试）
* [ ] 切换 1×2 / 1×3 / 2×3 时，preview canvas 实际比例匹配（widget test 断言 `RenderAspectRatio` 的 `aspectRatio` 属性）
* [ ] `GridEditorState` 不再持有 `nineGridSocialMode` / `centerImage` 等字段
* [ ] `GridRenderRequest` 不再持有 9-grid-social 相关字段
* [ ] 导出张数 = `cellCount`，每张正方形 PNG（renderer 单元测试断言）
* [ ] `computeGridLayout` 单元测试覆盖：每个保留的 GridType + spacing 边界
* [ ] ST-C `clampSourceScale` / `clampSourceOffset` 测试新增 `targetAspect != 1` 的 case
* [ ] 既有 `05-08-nine-grid-social` 测试根据新模型重写或删除

## Out of Scope

* per-cell 替换 state / Map / UI → Subtask C
* `CellOverlay` 通用化 → Subtask C
* selector 文字卡片 → Subtask A

## Technical Notes

* 关键文件：
  * `lib/features/grid/domain/usecases/grid_layout.dart` — 算法签名 / 实现
  * `lib/features/grid/domain/usecases/compute_source_crop.dart` — 扩展 targetAspect
  * `lib/features/grid/domain/entities/grid_editor_state.dart` — 删 9-grid-social 字段
  * `lib/features/grid/domain/usecases/grid_render_request.dart` — 删字段
  * `lib/features/grid/data/renderers/grid_image_renderer.dart` — 删 `_composeCenterCell` / `kCenterCellIndex` / 改 crop 模型
  * `lib/features/grid/presentation/providers/grid_editor_provider.dart` — 删 center-* 接口
  * `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` — 新几何
  * `lib/features/grid/presentation/widgets/grid_controls_panel.dart` — 删 toggle code
  * `lib/features/grid/presentation/screens/grid_editor_screen.dart` — `AspectRatio` 三处
  * 测试：`test/features/grid/**` 全部 review
* 注意 `directory-structure.md` 的「Pattern: Isolate-safe rasterizer」描述保留有效；删除的是 grid_type_icons 段（A 已处理）
* `sourceTooSmall` 阈值参考保留 (`canvas 边长 < ?`)：维持现有「子图过小则警示」语义，量纲改成 `cellSide` × `min(rows, cols)`
