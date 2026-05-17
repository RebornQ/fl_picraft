# 宫格切图三项改动：每格可替换 + 正方形 + 精简列表

## Goal

把宫格切图编辑器从「单源整图切分 + 仅 3×3 中心格可替换」演进为：
1. **任意宫格类型的任意宫格都可替换**为独立图片（每格独立 pinch/pan/longpress 菜单）
2. **每一格都是正方形**（画布形状 = `cols : rows`，cells 满铺）
3. **宫格类型列表精简**为 5 种主流配比（1×2 / 1×3 / 2×2 / 2×3 / 3×3），去掉图标、改为「中文标题 + 简短描述」的文字卡片

## Requirements

### R1 GridType 精简
* `GridType` enum 仅保留 `g1x2 / g1x3 / g2x2 / g2x3 / g3x3` 五个变体
* `kGridTypeSelectorOrder` 按 `[g1x2, g1x3, g2x2, g2x3, g3x3]` 排序（从少到多）
* 默认值仍为 `g3x3`

### R2 文字卡片
* `GridTypeSelector` 卡片去掉 `Icon(type.icon)`，改为「中文主标题 + 简短描述」两行文字
* 文案：

| GridType | 标题 | 简短描述 |
|----------|------|----------|
| g1x2 | 二宫格 | 横向两格，左右对照 |
| g1x3 | 三宫格 | 横向三格，长卷分屏 |
| g2x2 | 四宫格 | 方正四格，万能切片 |
| g2x3 | 六宫格 | 横向六格，时间轴友好 |
| g3x3 | 九宫格 | 朋友圈经典 |

* 标题 + 描述的双行版式同样放在 80–96 dp 高的卡片里；视觉上仍要保留「选中态高亮」对比

### R3 几何模型：每格正方形
* Preview canvas 的 aspect ratio 改为 `cols / rows`（1×2 → 2:1，1×3 → 3:1，2×2 → 1:1，2×3 → 3:2，3×3 → 1:1）
* `computeGridLayout` 输出每格宽高一致的正方形（与画布尺寸成等比例）
* 源图通过现有 ST-C `sourceScale` / `sourceOffset` pan/zoom 至 `cols:rows` 的裁剪区，**ST-C 的目标 aspect 从硬编码 1:1 改为 `cols/rows`**
* 导出的每张 PNG 仍是正方形像素图，张数 = `cellCount`

### R4 单源切分 + per-cell 覆盖
* 默认路径：导入一张源图，自动按选定 GridType 切成 N 个正方形（覆盖率 100%）
* 任意宫格可通过 tap 触发图片替换；替换后的图独立保存 `(image, scale, offset)`
* 未替换的格子保持显示源图切片
* 同一编辑会话中可替换 0–N 格

### R5 复用 CenterCellOverlay 交互
* 将 `CenterCellOverlay` 泛化为 `CellOverlay`，挂载到 layout 中**每一个** cell rect
* 行为：
  * 空态（未替换）：源图切片透出 + 透明 hit target → tap 触发 picker；hover/long-press 显示 CTA「替换图片」
  * 已替换态：渲染替换图 + pinch / pan / longpress 菜单（替换 / 重置 / 移除）
* 单元换算约定（widget-pixel ↔ source-pixel）沿用现有，按每格各自的 `sourceCellWidth/Height` 实例化

### R6 移除 9-grid-social toggle
* `nineGridSocialMode` 字段、相关 toggle UI、`lockedTo` 锁定逻辑、`kCenterCellIndex` 特例分支全部删除
* 现有 `05-08-nine-grid-social` 测试根据新模型重写（不再使用 toggle，直接选 3×3 + 替换中心格）

### R7 切换宫格类型重置 per-cell 覆盖
* 用户切换 GridType 时，**清空所有 per-cell 替换**（image / scale / offset）
* 防止 cell index 错位与坐标系不一致

### R8 spacing / cornerRadius 仍作用于全部格子（含被替换格）

### R9 导出顺序为行优先，覆盖 cells 输出真实替换图像

## Acceptance Criteria

* [ ] `flutter analyze` / `dart format` / `flutter test` 全部 clean
* [ ] `GridType` 仅剩 5 个变体；所有引用（layout / renderer / icon ext / 测试）已同步
* [ ] 删除 `grid_type_icons.dart`（或仅保留无图标的元数据 helper）
* [ ] Selector 卡片显示中文标题 + 描述，无 Icon；选中态有视觉对比
* [ ] 1×2 / 1×3 / 2×3 切换时，preview canvas 实际宽高比对应变化；每格肉眼正方形
* [ ] 任意宫格 tap 弹出替换 CTA；替换后该格独立 pinch/pan；longpress 菜单完整
* [ ] 切换 GridType 后所有 per-cell 替换被清空
* [ ] 导出张数 = `cellCount`，每张正方形 PNG，未替换格 = 源图切片，被替换格 = 用户图
* [ ] 9-grid-social toggle / `nineGridSocialMode` / `lockedTo` 完全移除，相关测试迁移或重写

## Definition of Done

* 单元/widget 测试覆盖：layout 算法（正方形 cells）、provider state shape（per-cell map）、selector 文案、CellOverlay 行为、grid-type 切换重置
* `.trellis/spec/frontend/directory-structure.md` 关于 `grid_type_icons` 的描述同步删除/更新
* 设计稿偏离点记录在 PRD `Technical Notes`
* 9-grid-social 相关 PRD 段落与测试一并清理

## Out of Scope

* 拖拽换序（reorder cells）
* 一次性批量替换多格
* 自定义非整数比例（1×5 / 4×5 等）
* 长图拼接（stitch）功能改动
* 切换宫格类型时智能保留替换（已明确选「全部重置」）

## Technical Approach

**架构高层**：三层改动同时落地，按依赖顺序拆三个 subtask：

1. **Subtask A — selector & enum 精简**（影响最小，独立可发）
   * 精简 `GridType` 至 5 个变体
   * 删除 `grid_type_icons.dart` 依赖
   * 重写 `GridTypeSelector` 卡片为「中文标题 + 描述」文字版
   * 顺手移除 `9-grid-social toggle` UI 入口（state 字段保留待 B 删除以避免回归）
2. **Subtask B — square cell geometry**（架构核心）
   * `computeGridLayout` 输出等大正方形 cells（依赖 canvas 尺寸的等比例）
   * `GridPreviewCanvas` 调用方将 `AspectRatio(1)` 改为 `AspectRatio(cols/rows)`（影响 `grid_editor_screen.dart` 三个 layout 分支）
   * `sourceScale` / `sourceOffset` clamp 函数扩展为接收 `targetAspect` 参数
   * Renderer 输出正方形 cells（替换 `img.copyCrop` 的目标坐标系）
   * 移除 `nineGridSocialMode` 字段、`kCenterCellIndex` 特例、`sourceTooSmall` 计算更新
3. **Subtask C — per-cell image replacement**（依赖 B 的几何契约）
   * `GridEditorState` 新增 `Map<int, CellReplacement>`（image / scale / offset）
   * `CenterCellOverlay` → `CellOverlay`，按 cell index 读写 state
   * 切换 GridType 时 controller 清空 replacement map（R7）
   * Renderer 接收 `Map<int, Uint8List>`，按 index 决定每格走 copyCrop 还是 compose
   * 删除 `centerImage` / `centerScale` / `centerOffset` 这组单值字段

## Decision (ADR-lite)

**Context**: 需求 #1 (per-cell 替换) + #2 (每格正方形) + #3 (5 种类型) 共同动了 domain、layout、renderer、UI 全链路。

**Decisions**:
* D1 画布形状 = `cols:rows`（拒绝固定 1:1 留白方案）
* D2 默认仍单源自动切分，per-cell 替换是覆盖（拒绝 N 格独立空白模式）
* D3 单格 UX 完整复用 CenterCellOverlay（拒绝 cover-fit-only 退化）
* D4 移除 9-grid-social toggle（拒绝快捷预设保留）
* D5 切换类型清空 per-cell 替换（拒绝智能映射 / 弹确认框）

**Consequences**:
* 优点：state shape 干净（`Map<int, …>`）、canvas 几何统一、UX 不再有「中心格特例」
* 风险：现有 `05-08-nine-grid-social` 测试需要重写；ST-C pan/zoom clamp 需扩展接收 aspect 参数；用户切类型会丢失替换工作量（已确认接受）

## Technical Notes

* 设计稿 `_3_宫格切图/code.html` 是图标版，本次实现偏离设计稿；新版样式属于 PRD-driven，**不需要新设计稿**
* `GridType` 名称沿用 `gRxC`（行先列后）保持稳定
* 关键文件清单：
  * Domain：`grid_type.dart`、`grid_editor_state.dart`、`grid_layout.dart`、`grid_render_request.dart`、`compute_center_transform.dart`（重命名为 `compute_cell_transform.dart`）、`compute_source_crop.dart`（扩展 aspect 参数）
  * Data：`grid_image_renderer.dart`
  * Presentation：`grid_editor_provider.dart`、`grid_type_selector.dart`、`grid_type_icons.dart`（删除）、`center_cell_overlay.dart`（重命名为 `cell_overlay.dart`）、`grid_preview_canvas.dart`、`grid_editor_screen.dart`
* `.trellis/spec/frontend/directory-structure.md` 中关于 `grid_type_icons` 的章节需同步更新
* 既有架构沿用：Riverpod Notifier、Clean Architecture、ImportedImage、ST-C pan/zoom 单位换算契约

## Implementation Plan (subtasks)

* **Subtask A** — `05-17-grid-type-prune-and-text-selector`（最小、可独立合）
* **Subtask B** — `05-17-grid-square-cell-geometry`（依赖 A，可同 A 一起评审）
* **Subtask C** — `05-17-grid-per-cell-replacement`（依赖 B）
