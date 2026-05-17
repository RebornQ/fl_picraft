# Subtask A — GridType 精简 + 文字卡片 selector

> Parent: `05-17-grid-slice-revamp`

## Goal

把 `GridType` enum 从 11 个收敛到 5 个，并把 `GridTypeSelector` 的图标卡片改为「中文标题 + 描述」的文字卡片。这是改造的第一步：影响最小、可独立合并；为后续 Subtask B（几何）/ C（per-cell 替换）扫清结构性障碍。

## Requirements

### R1 GridType 精简
* 删除 `g2x1 / g3x1 / g1x4 / g4x1 / g3x2 / g4x4` 共 6 个变体
* 保留 `g1x2 / g1x3 / g2x2 / g2x3 / g3x3`
* `kGridTypeSelectorOrder` 按 `[g1x2, g1x3, g2x2, g2x3, g3x3]` 排列
* `displayLabel` 实现不变（`"${rows}x$cols"`）
* 默认 `GridType` 仍是 `g3x3`（`GridEditorState.initial`）

### R2 删除图标依赖
* 删除 `lib/features/grid/presentation/widgets/grid_type_icons.dart`
* 删除 `GridTypeSelector` / `_GridTypeCard` 对 `type.icon` 的引用
* 同步更新 `.trellis/spec/frontend/directory-structure.md` 关于 `grid_type_icons` 的描述（删除整段或改为「已废弃」）

### R3 新文字卡片视觉
* 卡片尺寸：宽度跟随内容（≈ 120–140 dp 自适应）、高度 ≥ 80 dp，padding 16/12
* 内容：第一行中文主标题（`titleMedium`、`FontWeight.bold`、选中态 `onPrimaryContainer`），第二行简短描述（`bodySmall`、`onSurfaceVariant` 弱化色）
* 选中态：背景 `primaryContainer` + 2 px `primary` border + elevation 2；未选中：`surfaceContainerHigh` + 透明 border + elevation 0
* 文案表（一字不漏）：

| GridType | 标题 | 描述 |
|----------|------|------|
| g1x2 | 二宫格 | 横向两格，左右对照 |
| g1x3 | 三宫格 | 横向三格，长卷分屏 |
| g2x2 | 四宫格 | 方正四格，万能切片 |
| g2x3 | 六宫格 | 横向六格，时间轴友好 |
| g3x3 | 九宫格 | 朋友圈经典 |

* 文案放在 `GridType` 的 `displayTitle` / `displayDescription` getter 上（与 `displayLabel` 同源），便于 selector 调用

### R4 9-grid-social toggle UI 入口先行隐藏
* `GridControlsPanel` 中 toggle 控件**只在 UI 层移除**，state 字段 `nineGridSocialMode` 暂时保留
* 完整字段删除留给 Subtask B（避免本 subtask 引入 renderer 回归）
* `GridTypeSelector` 的 `lockedTo` 参数保留 API 不变，但 caller 一律传 `null`

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format .` clean
* [ ] `flutter test` clean
* [ ] `GridType` 仅剩 5 个变体（编译期保证）
* [ ] `grid_type_icons.dart` 已删除，无残留 import
* [ ] Selector 卡片渲染中文标题 + 描述，无 Icon
* [ ] 选中态视觉对比仍清晰可辨
* [ ] `.trellis/spec/frontend/directory-structure.md` 中 grid_type_icons 段落已同步更新
* [ ] `GridControlsPanel` 中 9-grid-social toggle 已不可见
* [ ] 既有的 grid type / selector 测试已迁移到新文案

## Out of Scope

* 几何模型变更（cells 仍跟随源图比例）→ Subtask B
* per-cell 替换 / state shape 改动 → Subtask C
* 删除 `nineGridSocialMode` 字段本身 → Subtask B

## Technical Notes

* 关键文件：
  * `lib/features/grid/domain/entities/grid_type.dart` — enum 精简 + 新增 `displayTitle` / `displayDescription`
  * `lib/features/grid/presentation/widgets/grid_type_selector.dart` — 文字卡片重写
  * `lib/features/grid/presentation/widgets/grid_type_icons.dart` — 整个文件删除
  * `lib/features/grid/presentation/widgets/grid_controls_panel.dart` — 隐藏 9-grid-social toggle UI
  * `.trellis/spec/frontend/directory-structure.md` — 同步删除 grid_type_icons 描述
  * 任何依赖被删除 GridType 变体的测试 / fixture
