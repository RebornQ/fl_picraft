# 移动端控制栏紧凑化（长图拼接 + 宫格切图）

## Goal

在 **compact / medium**（< 840 dp）窗口下，**压低**长图拼接 `StitchControlsSheet` 与
宫格切图 `_buildControlsPanelChrome` slot 的高度上限，把更多垂直空间还给预览画布。
expanded / large 的侧边面板布局**不动**。

## Subtasks

| Subtask | What it covers |
|---------|----------------|
| [`05-20-stitch-controls-sheet-cap`](../05-20-stitch-controls-sheet-cap/prd.md) | `StitchControlsSheet` 上限：`min(0.28h, 360)` → `min(0.22h, 320)`，floor 维持 200 |
| [`05-20-grid-controls-chrome-cap`](../05-20-grid-controls-chrome-cap/prd.md) | 宫格切图 compact 单列骨架：canvas/chrome 改为 `Expanded(flex: 3) + Expanded(flex: 2)`（revised — 原 `Flexible(loose) + ConstrainedBox` 方案因 chrome 收缩到内容 intrinsic 高度暴露页面背景已废弃；详见子任务 PRD `Decision (ADR-lite, revised)`） |

## Requirements

* compact / medium 下，长图拼接控制栏高度上限收紧（具体见 sheet-cap subtask）
* compact / medium 下，宫格切图控制栏不再无脑与画布平分剩余高度（具体见 chrome-cap subtask）
* expanded / large 不动
* 不破坏：滚动行为、48×48 swatch 命中区、80 dp FAB 净空

## Acceptance Criteria (parent-level)

* [ ] compact (约 360×800 dp) 下长图拼接预览画布高度比当前多 **≥ 48 dp**
* [ ] compact 下宫格切图预览画布高度比当前多 **≥ 60 dp**
* [ ] medium (约 720×412 横屏) 不出现控制栏内部滚动条之外的渲染溢出
* [ ] expanded / large 视觉无变化
* [ ] `flutter analyze` 干净；现有 widget 测试不破
* [ ] 两个 subtask 全部完成

## Definition of Done

* 两个 subtask 各自 DoD 完成
* Tests 补/改；lint / typecheck 干净
* 历史决策 ADR-lite（见下方）已写入 PRD

## Technical Approach

**策略**：Approach A —— 仅调整外层上限，最小侵入。控件本身的 padding / SizedBox /
Divider **不动**，避免触动可达性与视觉返工成本。两个 feature 分别在各自的外层包装
（sheet / chrome slot）做一次小切口。

## Decision (ADR-lite)

**Context**:
* 用户反馈：compact 窗口下长图拼接 + 宫格切图的控制栏「偏大」，挤压了画布可视区。
* 长图拼接已在 05-18 把 sheet 上限从 0.4 → 0.28（参见
  `archive/2026-05/05-18-long-image-stitch-toolbar-and-subtitle-mode/prd.md`），但仍偏大。
* 宫格切图问题更严重：compact 路径用 `Expanded` 让 chrome 与画布平分剩余高度，导致控
  制栏吃掉 ~50% 垂直空间。

**Decision**:
* 选择 Approach A（仅调外层上限），不动控件内边距 / SizedBox / Divider。
* 长图拼接：`StitchControlsSheet` 上限 `min(0.28h, 360)` → `min(0.22h, 320)`，floor 200 不变。
* 宫格切图：compact 单列骨架的 canvas / chrome 改为 `Expanded(flex: 3) + Expanded(flex: 2)`（revised；
  原 Decision 选择 `Flexible(fit: FlexFit.loose) + ConstrainedBox(maxHeight: min(0.36h, 380))`，
  实机验证发现 chrome 收缩到内容 intrinsic 高度暴露页面背景，已废弃 —— 详见
  `05-20-grid-controls-chrome-cap` PRD 的 `Decision (ADR-lite, revised)`）。同时轻量压缩
  `_BentoCard.height` 128→104 与 `GridTypeSelector` strip 104→92 缓解 chrome 拥挤感。
* expanded / large 路径**不动**。
* 拆为 2 个 subtask，按 feature 分别落地。

**Consequences**:
* 优点：实现风险低，回归面小（每个文件 < 20 行），不破坏 a11y / 滚动 / FAB 净空。
* 缺点：极小屏（≤ 360×640 dp）依旧可能略显紧凑，但相比当前已有可观改善；若用户后续仍
  觉不够，再升级到 Approach B（控件内边距压缩）或 C（size-class 差异化）。
* 风险：medium (720×412) 横屏下 sheet 可能更频繁触发内部滚动；已由 sheet 内部
  `SingleChildScrollView` 兜底，无溢出风险。

## Out of Scope

* expanded / large 侧边面板高度
* 控件本身的功能删减 / 重排
* 字号 / 主题色变更
* `StitchImageStrip` 自身高度
* `_SliderRow` / `Padding` / `Divider` 内边距压缩（保留给未来 Approach B/C）

## Technical Notes

* Spec 引用：
  * `.trellis/spec/frontend/responsive-layout.md` — Sheet → Panel dual-form extraction 模式
  * `.trellis/spec/frontend/component-guidelines.md` — Widget 结构约定
  * `.trellis/spec/frontend/quality-guidelines.md` — Lint / 测试基线
* 历史参考：`archive/2026-05/05-18-long-image-stitch-toolbar-and-subtitle-mode/prd.md`
* 关键文件：
  * `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart`
  * `lib/features/grid/presentation/screens/grid_editor_screen.dart`（line 393–424 周边）
