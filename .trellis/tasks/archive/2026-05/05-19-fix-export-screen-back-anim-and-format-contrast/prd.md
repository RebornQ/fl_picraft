# 修复导出页返回动画 + 格式按钮对比度

## Goal

修复 `/export` 导出页面两个 UX 缺陷，让导出流程的返回交互符合移动端约定，并解决格式选择按钮选中态文字看不清的可读性问题。

## What I already know

### 问题 1 — 返回动画异常（根因）

- `/export` 在 `lib/app/router.dart:97` 注册为 root-navigator 的兄弟路由（在 `StatefulShellRoute` 之外），目的是覆盖底部 nav 做模态。
- 进入路径：`StitchEditorScreen._onExportPressed` (`lib/features/long_stitch/.../stitch_editor_screen.dart:139`) 和 `GridEditorScreen._onExportPressed` (`lib/features/grid/.../grid_editor_screen.dart:215`) 都用 `context.go('/export')` 进入。
- 返回路径：`ExportScreen._onBackPressed` (`lib/features/export/.../export_screen.dart:59`) 用 `context.go('/stitch'|'/grid')`。
- **根因**：`context.go` 是声明式替换（不入栈），在 root navigator 下会触发 push/forward 的转场动画（右进左出），所以"返回"看起来像"前进"，与系统/iOS 返回手势的反向 pop 动画(左进右出)不一致 → 用户感知"动画奇怪"。
- 之所以原作者写成 `go` 而不是 `pop`：因为进入也是 `go`，navigator stack 上没有可 pop 的项。

### 问题 2 — 格式按钮选中态对比度不足（根因）

- 组件：`lib/features/export/presentation/widgets/format_quality_card.dart:98-128` 的 `_FormatButton`。
- 当前选中态：背景 = `colorScheme.primaryContainer`、文字/图标 = `colorScheme.primary`。
- 主题令牌定义在 `lib/app/theme/app_colors.dart`：
  - `primary = 0xFF4F378A`（深紫）
  - `primaryContainer = 0xFF6750A4`（中紫，**不是 M3 标准的浅色容器**）
  - `onPrimary = 0xFFFFFFFF`（白色）
  - `onPrimaryContainer = 0xFFE0D2FF`（浅紫，作为前景文字也偏淡）
- **根因**：`primaryContainer` 被设计为中等饱和度的紫色（接近 primary），与作为前景的 `primary` 形成"紫底紫字"，对比度严重不足。
- 项目中已存在的同类组件 `lib/features/long_stitch/presentation/widgets/stitch_mode_segmented.dart:67-68` 用的是 `primary + onPrimary`（白字）方案，对比度好，可作为参照。

## Assumptions (to validate)

- 用户只关心 `_FormatButton` 的选中态可读性，不要求改主题令牌（影响面更大，会波及 `grid_type_selector.dart` 等其他 primaryContainer 使用点）。
- 返回动画期望的"正确"行为是反向 pop（与系统返回手势一致）。
- 不需要拆 subtask —— 两个改动各 1 个文件 + 路由调整，体量小且互相不耦合。

## Open Questions

_（无 — 颜色方案已锁定为 A）_

## Resolved Decisions

- ✅ **格式按钮选中态颜色**：方案 A — 背景 `colorScheme.primary` + 前景 `colorScheme.onPrimary`（白色），与 `StitchModeSegmented` 一致。

## Requirements (evolving)

1. **返回动画自然**：从导出页返回 stitch/grid 编辑器时，使用反向 pop 转场（与系统返回手势一致），不再触发"前进"式的右进左出。
2. **格式按钮可读**：JPG/PNG 选中态的文字与图标必须有 ≥ WCAG AA 对比度，目视上应清晰可读（用户主诉"应该是白色"）。
3. 不破坏既有路由模态行为：`/export` 仍需覆盖底部 nav。
4. `currentExportSourceKindProvider` 的现有契约保持不变（仍作为兜底路径，处理 deep-link 直入 `/export` 的边缘情况）。

## Acceptance Criteria (evolving)

- [ ] 从长图拼接编辑器点"导出" → 进入 export → 点返回箭头 → 反向 pop 动画，落回长图编辑器，状态保留。
- [ ] 从宫格切图编辑器点"导出" → 同上，落回宫格编辑器。
- [ ] 系统返回手势（Android 系统返回、iOS 左滑）也走相同的 pop 路径。
- [ ] 直接 deep-link 打开 `/export` 时（无 stack 可 pop），返回按钮仍能根据 `currentExportSourceKindProvider` 路由回正确编辑器（兜底分支）。
- [ ] 选中态 JPG/PNG 按钮的文字、图标在 light 主题下目视清晰可读，白色字。
- [ ] 选中态在 dark 主题下也清晰可读（确认 `onPrimary` 在 dark scheme 下的值）。
- [ ] `flutter analyze` / `dart format` / 测试通过。

## Definition of Done (team quality bar)

- 现有 widget 测试（如有）继续通过；若引入新分支逻辑，补充测试。
- `flutter analyze` clean、`dart format .` 已跑、所有相关测试绿。
- `export_screen.dart` 类注释中的"How to exit"段落如有变化需要同步更新。
- spec `.trellis/spec/frontend/component-guidelines.md` 若涉及导航或选中态约定，按需更新（视改动而定）。

## Out of Scope (explicit)

- **不**修改主题令牌 `primaryContainer` 的值（影响面广，超出本次任务）。
- **不**改动 watermark / quality slider / save action 等其他子组件。
- **不**重构 export 路由拓扑（仍保持 root-level 兄弟路由覆盖 bottom nav）。
- **不**改 `currentExportSourceKindProvider` 的契约或语义。

## Technical Approach (proposed)

### 问题 1 — 返回动画

把进入 + 返回都改成入栈式导航：

- **进入**：`StitchEditorScreen._onExportPressed` 与 `GridEditorScreen._onExportPressed` 把 `context.go('/export')` 改为 `context.push('/export')`，使 `/export` 真正进入 navigator stack。
- **返回**：`ExportScreen._onBackPressed` 优先 `context.pop()`；若 `Navigator.of(context).canPop()` 为 false（deep-link 直入），再回退到当前 `context.go('/stitch'|'/grid')` 的兜底分支（继续依赖 `currentExportSourceKindProvider`）。
- 同时拦截系统返回：在 `ExportScreen` 外层包一个 `PopScope(canPop: false, onPopInvokedWithResult: ...)` 或者用 `WillPopScope` 等价物，把硬件返回也导流到同一个 `_onBackPressed`，保证两条返回路径一致。

### 问题 2 — 格式按钮配色

把 `_FormatButton` 的选中态切到「primary + onPrimary」模式，与 `StitchModeSegmented` 对齐：

- 选中：背景 = `colorScheme.primary`、边框 = `colorScheme.primary`、文字 + 图标 = `colorScheme.onPrimary`（白色）。
- 未选中：保持现状（背景 surface、边框 outlineVariant、文字 onSurfaceVariant）。
- 同步更新文件头的 docstring，把"primaryContainer"措辞换成实际方案。

### 替代方案（已评估，不采用）

- **方案 B（仅改 onPrimaryContainer 颜色）**：用 `onPrimaryContainer` 作前景仍然偏淡（0xFFE0D2FF）—— 还是看不清。✗
- **方案 C（改主题 primaryContainer 为浅色）**：影响面更广，`grid_type_selector.dart` 等其他位置都会变 —— 超出本次任务范围。✗

## Decision (ADR-lite)

**Context**: 用户报告导出页两个 UX 缺陷；分析后确认根因分别是 (1) `go` 触发前进动画、(2) 选中态紫底紫字。
**Decision**: 路由侧改为 push/pop 模型 + canPop 兜底；配色采用 primary + onPrimary（与 stitch mode segmented 一致）。
**Consequences**:

- ✓ 返回动画自然，符合移动端约定。
- ✓ 选中态可读性达标，与项目内既有 segmented 控件视觉一致。
- ✗ 引入入栈/出栈式导航后，需要确保 deep-link 兜底完备（已覆盖在 AC 中）。
- ✗ 不修复 `primaryContainer` 的"中紫不像 M3 容器色"这个潜在主题缺陷（留待后续主题 review 处理）。

## Implementation Plan (small PRs)

- PR1: 修复返回动画（router 不变、改 push/pop + PopScope + canPop 兜底）。
- PR2: 修复格式按钮配色（`_FormatButton` 选中态颜色）。

> 两个改动独立、互不耦合，可单 PR 合并；也可拆 2 个 PR 便于 review。视实际拆分情况调整。

## Technical Notes

### 关键文件清单

- `lib/app/router.dart` — 路由拓扑（无需改动，确认即可）
- `lib/features/export/presentation/screens/export_screen.dart` — 返回逻辑 + PopScope 包裹
- `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart:139` — 入口改 push
- `lib/features/grid/presentation/screens/grid_editor_screen.dart:215` — 入口改 push
- `lib/features/export/presentation/widgets/format_quality_card.dart` — `_FormatButton` 选中态配色
- 参考：`lib/features/long_stitch/presentation/widgets/stitch_mode_segmented.dart:67-68`（同款 primary + onPrimary 方案）

### 相关 Spec

- `.trellis/spec/frontend/component-guidelines.md` — StatefulShellRoute / per-branch screen 约定
- `.trellis/spec/frontend/state-management.md` — Riverpod provider 用法
