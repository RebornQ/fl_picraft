# 底部导航切换：StatefulShellRoute + 状态保留

## Goal

把底部 4 个一级 tab（作品库 `/`、长图拼接 `/stitch`、宫格切图 `/grid`、设置 `/settings`）之间的切换从「整页重建」改为「IndexedStack 风格」——切换时各 tab 自身的状态（滚动位置、已加载图片、控件参数等）保留，且 NavigationBar 自身不再被销毁重建。同步推翻并重写 `.trellis/spec/frontend/component-guidelines.md` 的 "Flat routing" 章节。

## What I already know

- 现有 router：`lib/app/router.dart` 是扁平 `GoRoute`，5 条顶级路由（`/`, `/stitch`, `/grid`, `/export`, `/settings`），每次 `context.go(target)` 都会让目标 screen 完整重建。
- 现有 nav：`lib/core/widgets/bottom_nav_bar.dart` 是 Material 3 `NavigationBar`，destinations 只列了 4 项（`home / stitch / grid / settings`，**不含 `/export`**）。当前选中 index 由 `GoRouterState.uri.toString()` 派生。
- 现有 scaffold：`lib/core/widgets/app_scaffold.dart` 由每屏自己包裹，所以连 NavigationBar 自身在切 tab 时都被销毁重建。
- 4 个 tab screen 全部用了 `AppScaffold`：`home_screen.dart` / `stitch_editor_screen.dart` / `grid_editor_screen.dart` / `settings_screen.dart`。其中 stitch / grid / settings 各自带 `AppBar`，grid 还带条件 `FloatingActionButton`。
- `/export` 是 **modal 流程**：`export_screen.dart:28-33` 注释明确写明它特意用裸 `Scaffold`（不挂 bottom nav），从 stitch / grid 编辑器进入，返回键退出 → **不应纳入 tab 容器**。
- 跨屏 handoff 走 Riverpod：`currentExportSourceKindProvider` 由 stitch/grid 在 `context.go('/export')` 之前写入；spec 明确禁止用 GoRouter `extra`（见 `state-management.md:231`）。
- 依赖：`go_router: ^14.6.2`（支持 `StatefulShellRoute.indexedStack`）+ `flutter_riverpod: ^2.6.1`。
- 涉及 9 个测试文件（home / stitch / grid / export 的 responsive / a11y / dark mode 测试 + 默认 widget_test）。

## ⚠️ Spec Conflict

`.trellis/spec/frontend/component-guidelines.md:191-212` 明确写了：

> "Flat routing + per-screen AppScaffold ... we don't need the cross-tab state preservation that ShellRoute buys, and the coupling makes per-feature ownership messier."

也就是说，现在「跳转」效果是**有意为之的设计决策**，不是 bug。本任务即推翻这条 spec。R6 强制要求改完后同步更新 spec（不然下次还会被改回去）。

## Decision (ADR-lite)

**Context**: 现有底部 tab 切换走的是 GoRouter 扁平路由 + per-screen `AppScaffold`，每次 `context.go()` 都重建整个 screen 与 NavigationBar。spec 原本说"不需要 cross-tab state preservation"，但用户实际使用中发现状态丢失体验差（如 stitch 编辑器加载的图被清空），决定推翻原决策。

**Decision**: 改用 GoRouter 官方推荐的 `StatefulShellRoute.indexedStack`：

- 1 个根 shell（`AppShell`）由 router 注入，shell 自己持有 `Scaffold` + `NavigationBar` + `PopScope`
- 4 个 branch 分别对应 `/`, `/stitch`, `/grid`, `/settings`，各自独立 Navigator stack（含独立 `navigatorKey`）
- shell 内部用 `IndexedStack` 渲染当前 branch，未激活的 branch 不绘制但保留 element tree（状态全保留）
- `/export` 留在 shell 之外，作为顶层 GoRoute，进入时全屏覆盖 bottom nav
- 切换效果：**瞬时切换，无动画**（与 Material 3 NavigationBar 设计一致；用户已确认）

**Consequences**:

- ✅ 各 tab 状态完全保留（`State`, Riverpod `AsyncNotifier`, 滚动位置）
- ✅ NavigationBar 不再重建
- ✅ 深链 / URL 同步免费保留
- ✅ 每个 tab 未来可独立 push 子路由（grid 模板、stitch 历史等），不影响别的 tab
- ⚠️ 4 个 tab screen 必须去掉自己的 `AppScaffold` 包裹（变纯 body），由 shell 提供 chrome
- ⚠️ 各 tab screen 的 `AppBar` / `FloatingActionButton` 仍由 screen 自己持有（套自己的 `Scaffold`），shell 只挂 `bottomNavigationBar`
- ⚠️ `.trellis/spec/frontend/component-guidelines.md` 的 "Flat routing" 章节必须重写

## Requirements

- **R1** Tab 切换不重建 screen 实例，状态（`State`、`AsyncNotifier`、滚动位置）持久。
- **R2** Tab 切换时 NavigationBar 不重建（同一个 widget 实例横跨 tab）。
- **R3** 深链（直接打开 `/stitch` / `/grid` / `/settings`）依然 work，URL ↔ tab 高亮双向同步。
- **R4** `/export` 维持 modal 行为（无 bottom nav，可返回；从 stitch / grid 进入）。
- **R5** `currentExportSourceKindProvider` 跨屏 handoff 不被破坏（export 在 shell 之外，provider 直接读得到）。
- **R6** 同步重写 `.trellis/spec/frontend/component-guidelines.md` 的 "Flat routing" 段落，反映新决策。
- **R7** 现有 9 个 widget 测试通过（必要时调整 pump 入口为 shell-aware 版本）。
- **R8** Android 返回键三层逻辑：① 当前 branch 的 navigator 可 pop → 先 pop ② 否则若 `currentIndex != 0` → `goBranch(0)` ③ 否则 `SystemNavigator.pop()`。Web / iOS / Desktop 不接管系统返回行为（默认 routing）。

## Acceptance Criteria

- [ ] 切到 `/stitch` 加载图后，切 `/grid` 再切回 `/stitch`，原图仍在、参数未重置。
- [ ] 切到 `/grid` 后再切回 `/`，作品库滚动位置保留。
- [ ] 直接 `flutter run --route=/grid`（或 web URL `/grid`），打开就是 grid tab，nav 高亮正确。
- [ ] 从 stitch / grid 进入 `/export`，bottom nav 隐藏；返回后回到原 tab 且状态保留。
- [ ] **Android**：在 settings tab 按返回键 → 切回作品库 tab；再按返回键 → app 退出。
- [ ] **Android**：在 stitch tab 内若已 push 子路由（未来扩展点），返回键先 pop 子路由。
- [ ] `flutter analyze` 干净；`flutter test` 全绿。
- [ ] `.trellis/spec/frontend/component-guidelines.md` 已同步更新（重写 "Flat routing" 段落）。

## Definition of Done

- Acceptance Criteria 全部通过。
- 新增 widget test 覆盖「切 tab 后状态保留」+「Android 返回键三层逻辑」。
- spec 同步重写并通过 `update-spec` 流程归档（含 Why / How to apply / Trade-offs）。
- PR 描述附简短 GIF 或截屏演示新切换效果。

## Implementation Plan (single PR)

> **任务规模评估**：6 个文件改动 + 1 个新 shell widget + 1 个 spec 重写 + 1 个新测试。耦合度高（router 改了 → 4 个 screen 必然连带改），不拆 subtask 反而更易保持一致性。建议**单 PR** 一次落地。

**改动列表（按落地顺序）：**

1. `lib/core/widgets/app_shell.dart` — **新增**。`StatefulWidget`，接收 `StatefulNavigationShell`；持有 `Scaffold(body: navigationShell, bottomNavigationBar: AppBottomNavBar(...))`，最外层包 `PopScope` 实现 R8 三层逻辑。
2. `lib/core/widgets/bottom_nav_bar.dart` — 改为接收 `int currentIndex` + `ValueChanged<int> onDestinationSelected` 回调；删除 `_indexFor` 与 `GoRouterState` 依赖。
3. `lib/app/router.dart` — 重写为 `StatefulShellRoute.indexedStack`，4 个 branch + 1 个顶层 `/export` 路由；shell builder 返回 `AppShell(navigationShell: ...)`。
4. `lib/features/{home,long_stitch,grid,settings}/presentation/screens/*.dart` — 把 `AppScaffold(...)` 替换为 `Scaffold(...)`（保留各自 `AppBar` / `FloatingActionButton`）。grid 的 `AppBar` 在 grid screen 自己的 Scaffold 上挂；shell 只负责 bottom nav。
5. `lib/core/widgets/app_scaffold.dart` — 直接删除（无人引用后），简化心智模型。export screen 不依赖它。
6. `lib/features/export/presentation/screens/export_screen.dart` — 不变。注释中关于 "AppScaffold + flat routing" 的引用更新为 "shell 之外的 modal 路由"。
7. `.trellis/spec/frontend/component-guidelines.md` — 重写 191-212 行的 "Flat routing + per-screen AppScaffold" 章节为 "StatefulShellRoute + per-branch screen + Android back-key contract"。
8. `test/app/app_shell_state_preservation_test.dart` — **新增**：① pump router → 切到 stitch 模拟修改 state → 切到 grid → 切回 stitch → 验证 state 还在；② 模拟 Android back-key → 验证三层逻辑。
9. `test/widget_test.dart` 与现有 9 个 screen 测试 — pump 入口适配（去掉 AppScaffold 后变更小，多数只需删 1 行 wrapper）。

## Out of Scope

- 横屏 / 平板 NavigationRail 切换（属于 responsive 后续任务）。
- 新增第 5 个 tab。
- 切 tab 动画的视觉细节调优（先用框架默认 = 无动画）。
- iOS swipe-back 手势整合（系统默认即可）。
- `/export` 重设计为 tab 内子路由。
- **二次点击当前 tab 重置 / 滚到顶**（独立任务）。
- Web 浏览器后退键的特殊行为（沿用浏览器默认）。

## Technical Notes

- **GoRouter 14.6 关键 API**：
  - `StatefulShellRoute.indexedStack(branches: [...], builder: (ctx, state, navigationShell) => AppShell(navigationShell))`
  - 每个 `StatefulShellBranch(navigatorKey: GlobalKey<NavigatorState>(), routes: [GoRoute(...)])`
  - shell 内部切 tab：`navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex)`
  - 当前 index：`navigationShell.currentIndex`
- **PopScope 三层逻辑伪代码**：
  ```dart
  PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final currentNavigator = navigationShell
          .shellRouteContext.navigatorKey.currentState;
      if (currentNavigator?.canPop() ?? false) {
        currentNavigator!.pop();
        return;
      }
      if (navigationShell.currentIndex != 0) {
        navigationShell.goBranch(0);
        return;
      }
      await SystemNavigator.pop(); // Android only
    },
    child: scaffold,
  )
  ```
- **跨屏 handoff**：现有 `currentExportSourceKindProvider` 模式与 shell 无冲突，因为 export 在 shell 之外，`Riverpod ProviderScope` 在 `MaterialApp.router` 之上仍生效。
- **测试 pump 模板**：新的 router-level 测试用 `MaterialApp.router(routerConfig: appRouter)` + `ProviderScope` 包一层；现有 screen-level 测试改成直接 pump screen 的 body（去掉 AppScaffold 后更简单）。

## Research References

无需额外 research——`StatefulShellRoute` 是 GoRouter 14 官方支持的 first-class API，本小姐已在 brainstorm 中评估了三种方案（IndexedStack vs PageView vs AnimatedSwitcher），用户选定 IndexedStack。

## Open Questions (resolved log)

1. ✅ **[Blocking]** 推翻 flat-routing spec？→ **是**
2. ✅ **[Preference]** 切换效果 → **A. 瞬时切换 + 状态保留**（StatefulShellRoute.indexedStack）
3. ✅ **[Edge]** Android 返回键智能处理 → **包含**（三层逻辑 R8）
4. ✅ **[Edge]** 二次点击当前 tab → **Out of Scope**
