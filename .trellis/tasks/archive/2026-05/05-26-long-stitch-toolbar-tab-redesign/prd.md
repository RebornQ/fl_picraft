# 长图拼接工具栏 Tab 化改造

## Goal

把长图拼接编辑器底部 / 右侧 `StitchControlsPanel` 的"扁平一列控件"工具栏，重构为
"4 个 Tab + 横向滚动卡片"的分层结构，让方向、模式、边框、圆角/间距各自占据独立
Tab。降低视觉密度、降低用户找参数的认知成本，同时把"普通拼接 / 电影台词"
从隐藏式开关（仅保留字幕）显式化成卡片选择项。

## Requirements

### Tab 结构

* `StitchControlsPanel` 顶层引入 `TabBar` + `TabBarView`
* Tab 顺序（动态）：
  1. **基础**（始终显示）
  2. **电影台词**（仅当 `subtitleOnlyMode == true` 时动态插入；用户取消选择后移除）
  3. **边框**
  4. **圆角 / 间距**
* 默认停在"基础"Tab；切换状态不持久化（每次进入编辑器都从基础开始）
* TabBarView 禁用水平 swipe（`physics: NeverScrollableScrollPhysics()`），
  避免与基础 Tab 内横向卡片列表的滚动冲突
* TabBar 使用 MD3 `TabBar`（primary）+ surface 背景；颜色走主题 token

### 基础 Tab — 横向卡片列表

* 单行 `ListView`（`scrollDirection: Axis.horizontal`），卡片宽 92dp、高 100dp（草图规格）
* 3 个卡片：
  * **卡片 A — 方向**（竖向 ⇄ 横向）
    * 单 item，单击切换当前 `mode`
    * 显示当前方向的图标 + caption（"竖向" / "横向"）
    * 不参与"选中态"高亮（与 B/C 是不同语义：状态切换 vs 模式互斥）
  * **卡片 B — 普通拼接**
    * 互斥单选；选中等价于 `subtitleOnlyMode = false`
    * 当前默认状态
  * **卡片 C — 电影台词**
    * 互斥单选；选中等价于 `subtitleOnlyMode = true` + 强制 `mode = vertical`
* 卡片视觉照搬草图（含拼接示意图，用纯 Flutter 形状绘制，**不引入新 asset**）

### 方向 × 模式联动（原子 setter）

* 在 `StitchEditorController`（`presentation/providers/stitch_editor_provider.dart`）
  暴露 / 复用以下原子操作：
  * `selectMovieSubtitleMode()` → `subtitleOnlyMode = true` + `mode = vertical`（一次 emit）
  * `selectNormalMode()` → `subtitleOnlyMode = false`
  * `toggleOrientation()` → 当前 vertical 则切 horizontal 且同时关闭 `subtitleOnlyMode`；
    horizontal 则切回 vertical（`subtitleOnlyMode` 保持原值）
* 保证 single emit，避免 preview canvas 闪一帧错误布局

### 电影台词 Tab 内容

* 字幕高度 Slider（`subtitleBandHeightPercent` × 100 显示百分比）
* 自动剪裁黑边 Switch
* 复用现有 `_onToggleSubtitle` 中的 SnackBar 警告逻辑（图片高度 < 字幕条高度）

### 边框 Tab 内容

* 边框宽度 Slider（0 ~ `kMaxStitchBorderWidth`）
* 边框颜色 6 色 Wrap（同现有 `_borderSwatches`）

### 圆角 / 间距 Tab 内容

* 圆角 Slider（0 ~ `kMaxStitchCornerRadius`）
* 图片间距 Slider（0 ~ `kMaxStitchSpacing`）
  * 注：原来"subtitle 模式下隐藏间距"的逻辑此处自然失效（subtitle 模式下用户
    切到这个 Tab 仍可拖动 — 但因为 layout 算法忽略 spacing，无视觉效果）。
    解决：subtitle 模式下 Slider 整体禁用并显示提示文本"字幕模式下间距由算法控制"。

### 响应式行为

* Compact / Medium → 底部 sheet（`StitchControlsSheet`）承载 TabBar + TabBarView；
  重新评估 maxHeight cap：估计需要从 `200~320` 提升到 `260~400` 以容纳 TabBar + 内容
* Expanded / Large → 右侧 dock 也直接放入相同 Tab 布局

## Acceptance Criteria

* [ ] `StitchControlsPanel` 改造为 4 Tab 布局，原 8 项控件按规范分组迁移
* [ ] 基础 Tab 横向卡片列表实现：方向 / 普通拼接 / 电影台词，B/C 互斥
* [ ] 选电影台词卡片，`mode` 与 `subtitleOnlyMode` 在同一帧切换为 vertical+true
* [ ] 处于电影台词模式时点方向卡片切横向，自动关闭电影台词（B 卡片回到选中态）
* [ ] "电影台词" Tab 仅在 `subtitleOnlyMode == true` 时存在；取消后回到基础 Tab
* [ ] TabBarView 禁用水平 swipe，基础 Tab 横向滚动无冲突
* [ ] Compact / Medium / Expanded 三个 size class 均工作正常；右侧 dock 同 Tab 结构
* [ ] 字幕高度 Slider、自动剪裁 Switch 在电影台词 Tab，行为/SnackBar 与现有一致
* [ ] 圆角/间距 Tab 中：subtitle 模式时间距 Slider 禁用 + 显示算法控制提示
* [ ] `flutter analyze` clean、`dart format .` 已应用、`flutter test` 通过
* [ ] 新增覆盖测试：
  * Tab 切换 + 电影台词 Tab 动态显隐
  * 方向卡片切横向时 subtitleOnlyMode 强制 false
  * 选电影台词卡片时 mode 强制 vertical（即便之前是 horizontal）

## Definition of Done

* `flutter analyze` clean
* `dart format .` applied
* `flutter test` green
* 调用点 (`stitch_editor_screen.dart`、`StitchControlsSheet`) 已对齐
* 若发现遗留的 `stitch_mode_segmented.dart` 不再被任何处使用，删除并更新引用
* Spec 文档（若 `.trellis/spec/frontend/long_stitch/*` 存在相关约定）已同步

## Out of Scope

* 不改 `StitchEditorState` 字段语义（只增 / 改 setter）
* 不改字幕渲染算法 / 黑边检测算法
* 不改 `StitchImageStrip` / `StitchPreviewCanvas`
* 不动方向 / 模式以外的图片列表行为
* 不引入新静态 asset（卡片示意图用 Flutter shape 绘制）

## Decision Log (ADR-lite)

| ID | Context | Decision | Consequences |
| --- | --- | --- | --- |
| D1 | 电影台词模式下用户切横向 | 静默切横向 + 自动关电影台词 | 流畅；与现有"horizontal 时 subtitleOnlyMode 失效"语义一致；要求原子 setter |
| D2 | 电影台词 Tab 显隐 | 动态插入 / 移除（按需） | TabBar 项数会变化（小动画抖动）；语义最严格 |
| D3 | Tab 切换持久化 | 不持久化，每次默认基础 | UI 层最干净，state 不变 |
| D4 | 自动剪裁黑边归属 | 放入电影台词 Tab | 与 subtitleEffective 语义一致 |
| D5 | 基础 Tab 卡片视觉 | 完全照草图 92×100，含示意图 | 信息密度最高；示意图用 Flutter shape 实现（无新 asset） |
| D6 | TabBarView swipe | 禁用水平 swipe | 避免与基础 Tab 横向卡片列表冲突 |

## Technical Approach

* 新增 widget：
  * `StitchControlsTabbedPanel`（替换 `StitchControlsPanel` 内容；保留旧 widget 名做调用兼容
    或直接重构现有类，依实现简洁度选择）
  * `StitchBasicTabCards`（基础 Tab 横向卡片列表）
  * `StitchOrientationCard` / `StitchModeCard`（卡片实现，含 shape 示意图）
* `StitchEditorController` 新增 / 调整：
  * `selectMovieSubtitleMode()` — 一次性 emit 设置 `subtitleOnlyMode=true + mode=vertical`
  * `selectNormalMode()` — `subtitleOnlyMode=false`
  * `toggleOrientation()` — 包含"切横向时关闭 subtitleOnlyMode"的副作用
* 原有 `setMode(StitchMode)` / `setSubtitleOnlyMode(bool)` 公开 API 保留（向后兼容、单元测试可用），
  新行为通过新方法组合实现
* `StitchControlsSheet.maxHeight` cap 提升到 `260 ~ 400` 区间，按实测微调
* 删除 / 改造 `stitch_mode_segmented.dart`（若新方案下被基础 Tab 卡片完全替代）

## Files Touched (估计)

* **修改**：
  * `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart`
  * `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart`
  * `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
  * `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
* **新增**：
  * `lib/features/long_stitch/presentation/widgets/stitch_basic_tab_cards.dart`
  * `lib/features/long_stitch/presentation/widgets/stitch_orientation_card.dart`
  * `lib/features/long_stitch/presentation/widgets/stitch_mode_card.dart`
* **可能删除**：
  * `lib/features/long_stitch/presentation/widgets/stitch_mode_segmented.dart`（若不再使用）
* **测试新增 / 修改**：
  * `test/features/long_stitch/stitch_controls_panel_tab_test.dart`（或追加到已有同名文件）

## Implementation Plan (单 PR)

任务复杂度 = Moderate。整体约 8~12 个文件改动，无外部依赖、无后端协作，
**不拆 subtask**，单 PR 完成。提交粒度内部拆 commit：

1. **Commit 1 — Controller 原子 setter**：扩展 `StitchEditorController`，加单测
2. **Commit 2 — Tab 骨架**：`StitchControlsPanel` Tab 化，把现有控件按 Tab 分组迁入
3. **Commit 3 — 基础 Tab 卡片**：方向 / 普通拼接 / 电影台词三个卡片 + 横向 list
4. **Commit 4 — Sheet maxHeight / Expanded right-dock 校准**
5. **Commit 5 — 测试 + 清理**：widget test 覆盖、删除 `stitch_mode_segmented.dart`（如可删）

## Risks

* TabBar 项数动态变化导致 `TabController.length` 不一致 → 用 `DefaultTabController` 时需要
  通过 key 重建，或手动管理 `TabController`
* 基础 Tab 卡片示意图用 Flutter shape 绘制可能与设计稿有视觉差异 → 用 placeholder
  几何形状（矩形 / 黄色字幕条）足以传达语义
* maxHeight 提升后 compact 屏幕下预览区可能被挤压 → 实测调整

## Technical Notes

* 草图：`docs/long-stitch-screen-wireframe.excalidraw`
* 关键代码入口：
  * `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` (当前实现)
  * `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` (controller / setter)
  * `lib/features/long_stitch/domain/entities/stitch_editor_state.dart` (state schema，不动)
