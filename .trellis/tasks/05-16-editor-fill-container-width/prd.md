# Editor + All Screens Fill Container Width

> Parent: [`05-16-editor-layout-and-import-isolation`](../05-16-editor-layout-and-import-isolation/prd.md)

## Goal

把当前「拉宽窗口，内容被锁在 1200 dp 居中」的体验改为「内容随窗口宽度铺满」。具体含义（继承父任务 D1-D3 决策）：

- 删除 `Breakpoints.maxContentWidth = 1200` 常量（或保留常量但取消所有 screen 的使用）。
- 移除 Home / Stitch Editor / Grid Editor / Export Screen 的「`Center + ConstrainedBox(maxWidth: maxContentWidth)`」模板。
- 编辑器侧边面板由固定 `380 dp` 改为 `min 380 / max 480` 的弹性宽度，剩余宽度全部留给画布。
- 解除 `stitch_preview_canvas.dart` 内部的 `maxWidth: 360 / maxHeight: 480` 限制，让预览随容器响应。
- 同步更新 spec `frontend/responsive-layout.md`。

## What I already know

### 当前布局规律

| Screen | 现状 | 关键文件 |
|---|---|---|
| Home | `Center + ConstrainedBox(1200) + ListView` 主体；feature cards 在 medium+ 用 `Row(Expanded, Expanded)` | `lib/features/home/presentation/screens/home_screen.dart:36-46` |
| Stitch Editor | 同样的 1200 帽；expanded/large 下 2 列 `Row(Expanded(canvas), SizedBox(380, panel))` | `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart:101-113, 131-156` |
| Grid Editor | 同样的 1200 帽；expanded/large 下 2 列同样模式 | `lib/features/grid/presentation/screens/grid_editor_screen.dart:102-114, 142-178` |
| Export Screen | 待确认（PRD Technical Notes 列在内）；如有相同帽，同步处理 | `lib/features/export/presentation/screens/export_screen.dart` |
| Settings | 当前简单实现，无 1200 帽（确认中） | `lib/features/settings/presentation/screens/` |
| Preview Canvas | 内部锁 `maxWidth: 360 / maxHeight: 480` | `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart:128-148` |

### Spec 约束（必须同步改）

- `.trellis/spec/frontend/responsive-layout.md` 第 47-67 行：「Cap content with `Breakpoints.maxContentWidth`」必须改为「不再设置 max content cap；编辑器画布利用整个容器宽度」的新约定。
- 同文件第 143-145 行：「side panel is 380 dp wide」需要改为「[380, 480] 弹性宽度」。
- 同文件第 175-183 行的「Responsive behavior table」需要更新所有 screen 的 large 列。

### 测试基线

- `test/features/long_stitch/presentation/stitch_editor_responsive_test.dart` — viewport-based 测试，要新增 1920 / 2560 dp 用例确认面板不超过 480 dp、画布拿到剩余。
- 其他 widget 测试在 700/800 dp 的紧凑视口下都会受影响最小，但仍要回归确认无 overflow 警告。

## Requirements

- **R1.1** 删除（或停用）`Breakpoints.maxContentWidth` 常量与所有调用点。
- **R1.2** 编辑器侧边面板宽度：`width = clamp(380, container * 0.25, 480)`（具体实现可用 `LayoutBuilder` 或 `ConstrainedBox(minWidth: 380, maxWidth: 480) + Flexible`）。剩余宽度给画布。
- **R1.3** 编辑器画布在 expanded / large 下铺满 `Expanded` 列；没有任何外层 / 内层固定 max 帽。
- **R1.4** `stitch_preview_canvas.dart` 内部解除 360/480 锁；用 `LayoutBuilder` 按可用区域 + 画布原始 aspect ratio 居中铺满。
- **R1.5** Home / Export Screen 同步去掉 `ConstrainedBox(maxWidth: 1200)`；内部子元素（feature cards / 最近作品 grid）保留现有的 `Expanded(flex:1)` 自适应。
- **R1.6** Spec `responsive-layout.md` 改三处：移除 maxContentWidth 约定 + 改 380 → [380, 480] + 更新表格的 large 列。
- **R1.7** 单元 / widget tests 在 1280 / 1600 / 1920 / 2560 dp 视口下回归通过；新增至少 1 个用例验证面板上限 480 dp。

## Acceptance Criteria

- [ ] AC1.1 拖宽窗口到 1600 / 1920 / 2560 dp 时，所有 screen 内容跟随窗口拉伸（无 1200 dp 上限留白）。
- [ ] AC1.2 Stitch / Grid 编辑器在 large 下：侧边面板宽度 ∈ [380, 480] dp；剩余宽度全部给画布。
- [ ] AC1.3 Stitch 预览画布按可用区域铺满（无 360/480 锁限），保持 aspect ratio 不变。
- [ ] AC1.4 现有 compact / medium 下的布局（手机竖屏 / 横屏）行为不变 — 测试通过即认为不变。
- [ ] AC1.5 `flutter analyze` 干净（无新增 warning）。
- [ ] AC1.6 `dart format .` 干净。
- [ ] AC1.7 `flutter test` 全绿，新增宽窗口测试用例通过。
- [ ] AC1.8 `.trellis/spec/frontend/responsive-layout.md` 同步更新。

## Definition of Done

- 所有 AC 勾选完成。
- spec 文档更新含 Why（为什么不再 cap） + How to apply（弹性面板的实现方式）。
- 新增 widget 测试以宽窗口（≥1920 dp）覆盖弹性面板上限。

## Technical Approach

### 改造步骤

1. **删除常量 / 改名**：`Breakpoints.maxContentWidth` 标 `@Deprecated` 或直接删除。其他常量（compact/medium/expanded/large）保留。
2. **改三个 screen**：home / stitch_editor / grid_editor 删除 `Center + ConstrainedBox`，body 直接挂 `SafeArea`。
3. **改 export screen**：同样删除（如果存在）。
4. **改侧边面板宽度**：把 `SizedBox(width: 380)` 改为 `ConstrainedBox(constraints: BoxConstraints(minWidth: 380, maxWidth: 480))` 并配合 `Flexible(flex: 0)` 或 `LayoutBuilder` 让画布拿到剩余宽度。
5. **改 preview canvas**：用 `LayoutBuilder` + `FittedBox` 重写，画布按 `aspectRatio` 居中铺满 available space。
6. **更新 spec**。
7. **回归 + 新增测试**。

### 风险点

- **超宽屏 home 的 feature cards 视觉**：用户已确认接受 Expanded 拉伸。如果实际效果太扁，可以在 home_screen.dart 单独再加 max 宽度（独立小改）。
- **panel 弹性宽度的 SizedBox 替代方案**：`ConstrainedBox + Flexible` 在 `Row` 里要小心 — 错误用法会让面板被画布挤压。推荐用 `LayoutBuilder` 在外层算好 panel 宽度，再用 `SizedBox(width: computed)`。
- **preview canvas 移除 maxHeight: 480 后**：在很高的窗口下预览可能拉得很大，要保证 `FittedBox(fit: BoxFit.contain)` + aspectRatio 仍然包裹合理。

## Decision (ADR-lite)

> 继承父任务 D1 / D2 / D3 决策，本任务仅落地实施。

## Out of Scope

- 图片导入会话隔离（属于 sibling subtask `05-16-per-mode-import-isolation`）。
- 调整任何 design token / 颜色。
- 新增「ultra-wide」size class（≥1920 dp 暂不需要单独分支）。

## Technical Notes

### 关键文件

- `lib/core/constants/breakpoints.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
- `lib/features/grid/presentation/screens/grid_editor_screen.dart`
- `lib/features/export/presentation/screens/export_screen.dart`（如有 1200 帽）
- `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart`
- `.trellis/spec/frontend/responsive-layout.md`
- `test/features/long_stitch/presentation/stitch_editor_responsive_test.dart`（含其他 widget tests）

### 现有 spec / guide 依赖

- `.trellis/spec/frontend/responsive-layout.md` — 本任务核心 spec 改动。
- `.trellis/spec/frontend/component-guidelines.md` — sheet ↔ panel 拆分约定（保持，不动）。
- `.trellis/spec/frontend/quality-guidelines.md` — lint / test 红线。

