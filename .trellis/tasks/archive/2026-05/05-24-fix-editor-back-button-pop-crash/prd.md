# 修复长图/栅格编辑器返回按钮的 go_router pop 崩溃

## Goal

修复点击长图编辑器（`StitchEditorScreen`）/ 栅格编辑器（`GridEditorScreen`）AppBar
返回按钮时偶发的 `currentConfiguration.isNotEmpty` 断言崩溃。错误根因是 tab branch
root 上的 `Navigator.canPop(context)` 在某些瞬态返回 `true`、按钮渲染出来，但实际点
击时 GoRouter 的 `currentConfiguration` 已空，`_handlePopPageWithRouteMatch` 抛断言。

修复方式：**彻底删除两个 editor 的 AppBar leading 返回按钮**，与 spec 中"tab branch
root 不应该有返回按钮，使用 bottom nav 替代"的契约完全对齐，零崩溃面。

## Requirements

- [R1] 删除 `StitchEditorScreen.build` AppBar 的 `leading: Navigator.canPop(...) ?
      IconButton(...) : null` 整段
- [R2] 删除 `GridEditorScreen.build` AppBar 的 `leading: Navigator.canPop(...) ?
      IconButton(...) : null` 整段
- [R3] 修复后从 home tab 切换到 stitch / grid tab、从 grid / stitch tab 切回 home
      tab 的体验完整保留（用户用 bottom nav）
- [R4] Android 系统返回键、iOS 边缘手势返回的行为不退化（由 `AppShell.PopScope`
      处理，不受本次改动影响）
- [R5] 同时清理 stitch / grid editor 顶部 dartdoc 中关于 "AppBar with back" 之类
      过时的层叙述（如果存在）

## Acceptance Criteria

- [ ] `StitchEditorScreen` 渲染后 AppBar 没有 leading 返回按钮（`appBar.leading == null`）
- [ ] `GridEditorScreen` 渲染后 AppBar 没有 leading 返回按钮
- [ ] 切换到 stitch / grid tab 时不再有 race window 让返回按钮短暂可见
- [ ] 新增 widget 测试断言两个 editor 的 AppBar `leading == null`（或断言
      `find.byIcon(Icons.arrow_back)` 在 AppBar 区域中 `findsNothing`）
- [ ] Android 系统 back → 回 home tab（由 `AppShell.PopScope` 兜底，既有 `app_shell_test`
      已覆盖，不退化）
- [ ] 既有所有 stitch / grid editor 相关测试通过
- [ ] `flutter analyze` 0 issues
- [ ] `dart format .` 0 changes
- [ ] `flutter test` 全套通过

## Definition of Done

- Tests added/updated
- `flutter analyze` 干净
- `dart format` 干净
- `flutter test` 全绿

## Technical Approach

**核心改动**：在 `stitch_editor_screen.dart:99-106` 和 `grid_editor_screen.dart:174-181`
将以下整块代码移除：

```dart
appBar: AppBar(
  leading: Navigator.canPop(context)
      ? IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
        )
      : null,
  title: const Text('长图拼接' / '宫格切图', ...),
  …
),
```

移除后变成：

```dart
appBar: AppBar(
  title: const Text('长图拼接' / '宫格切图', ...),
  …
),
```

`AppBar.leading` 默认为 `null` —— 这与 spec 完全对齐：tab branch root 不需要返回按钮，
用户用 bottom nav 切换。

**为什么不用方案 A（防御性 pop）**：保留按钮 + 内部 canPop 检查仍然违反 spec
"tab root 不该有返回按钮"的契约，而且 race window 中按钮仍会短暂可见，按下虽然不
崩但 UX 一致性差。

**为什么不用方案 C（_onBackPressed fallback）**：为一个"未来可能 push 进入"的假设
提前引入额外代码路径，YAGNI 原则下不必要——未来如果真的引入 push 入口，再参照
`export_screen.dart:89` 加 `_onBackPressed` 也来得及。

## Decision (ADR-lite)

**Context**: `StitchEditorScreen` / `GridEditorScreen` 的 AppBar 都用
`Navigator.canPop(context) ? IconButton : null` 模式条件渲染返回按钮，企图兼容
"未来可能从其他地方 push 进入" 的场景。但：
1. 全仓 grep 0 个 `push('/stitch')` / `push('/grid')`
2. spec `component-guidelines.md` 明确说 "tab root is not 'back-able'; use the
   bottom nav instead"
3. 实际运行中出现 `canPop` 瞬态返回 `true` → 按钮可见 → 按下 → GoRouter
   `currentConfiguration` 已空 → `_handlePopPageWithRouteMatch` 断言失败崩溃

**Decision**: 彻底移除两个 editor 的 leading 返回按钮，与 spec 契约完全一致。

**Consequences**:
- ✅ 零崩溃面：按钮不存在 → race window 无法触发
- ✅ 与 settings tab 行为一致（settings 本来就没有 leading）
- ✅ 改动最小：每个文件删除 ~8 行
- ✅ 系统 back / iOS 手势返回行为不受影响（由 `AppShell.PopScope` 处理）
- ⚠️ 未来若真要做"快速开始 → push 进 editor"，需要按 export_screen 模式重新加
  完整 `_onBackPressed`（不是再写一遍这个有 race 的 canPop 守卫）

## Out of Scope

- 不动 `ExportScreen._onBackPressed`（成熟模式，本来就正确）
- 不动 `AppShell.PopScope`（已经正确处理系统 back）
- 不修改 `component-guidelines.md` 的 spec 文字（已经盖棺定论，本次修复正是
  让代码追上 spec）
- 不引入 `_onBackPressed` 方法到 stitch / grid editor（YAGNI；未来真有 push 入口
  时再加）
- 不调查具体哪种瞬态触发了 race（删除按钮后无关紧要）

## Technical Notes

- 受影响文件：
  - `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
    （删除 leading + 检查 dartdoc 是否需要同步）
  - `lib/features/grid/presentation/screens/grid_editor_screen.dart`
    （同样删除）
  - `test/features/long_stitch/presentation/screens/stitch_editor_screen_test.dart`
    或同目录下既有测试（新增 leading == null 断言）
  - `test/features/grid/presentation/screens/grid_editor_screen_test.dart`
    或同目录下既有测试（同样）
- 关键参考：
  - `lib/features/settings/presentation/screens/settings_screen.dart` —— 同样作为
    tab branch root，没有 leading 返回按钮，行为参考
  - `lib/core/widgets/app_shell.dart` `_handlePop` —— 兜底 PopScope
  - `.trellis/spec/frontend/component-guidelines.md` —— "StatefulShellRoute +
    per-branch screen + Android back-key contract" 章节（line 234+）

## Implementation Plan

单 PR 实现，2 个 commit 序列：
1. **PR-step-1**: 删除 stitch + grid editor 的 leading 返回按钮（+ 调整相关
   dartdoc 注释）
2. **PR-step-2**: 新增 widget 测试断言两个 editor 的 AppBar `leading == null`
