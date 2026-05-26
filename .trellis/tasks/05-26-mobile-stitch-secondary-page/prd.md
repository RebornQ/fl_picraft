# 移动端拼图入口收纳到二级页面

## Goal

在移动端将「长图拼接」和「宫格切图」两个编辑器从底部导航顶层 tab，
**收纳到从首页进入的二级页面**，并在退出二级页面前增加一次二次确认；
**桌面端保持现有四 tab 结构不变**。

为什么：当前移动端底部导航塞了 4 个 tab（功能大全 / 长图拼接 / 宫格切图 / 设置），
两个编辑器作为顶层 tab 一直暴露在底部导航里，对移动端窄屏的视觉密度
和"任务式编辑"心智不友好。将编辑器降为从首页卡片入口进入的二级页面，
能让移动端底部导航回到极简（功能大全 + 设置），同时让"退出编辑器"
显式且可被二次确认所拦截，避免误退丢失图片/参数。

## Requirements

### R1 路由结构（双路由）
- 保留现有 `StatefulShellRoute.indexedStack` 4 branch 不变。
- 新增两条根级 sibling 路由 `/m/stitch`、`/m/grid`，挂在
  `_rootNavigatorKey` 下覆盖 shell，build 同一个
  `StitchEditorScreen` / `GridEditorScreen`（无重复 widget 树）。

### R2 首页入口分流
- `HomeScreen._FeatureCardsLayout` 的 `FeatureCard.onActionPressed`
  按 `windowSizeClassOf(context)` 分流：
  - `WindowSizeClass.compact` → `context.push('/m/stitch')` / `/m/grid`
  - 其他三档 → 现状 `context.go('/stitch')` / `/grid`（不动）

### R3 底部导航裁剪
- `AppBottomNavBar.destinations` 由常量数组改为按 `WindowSizeClass`
  返回的方法：
  - compact → `[功能大全, 设置]`（即原 index 0、3）
  - 其他 → 现状 4 项（不动）
- `AppShell._onDestinationSelected` 与 `currentIndex` 处理需做映射：
  compact 下 destination index 1 实际对应 branch index 3（settings）。

### R4 二次确认对话框
- 触发条件：**仅当编辑器内 `state.hasImages == true` 时**才弹出；
  空编辑器直接退出（无 dialog）。
- 触发入口：以下三种入口统一进 `PopScope.onPopInvokedWithResult`：
  - AppBar leading 返回箭头（点击）
  - Android 系统后退键
  - **iOS 边缘滑动后退**（PopScope 已天然拦截）
- 确认对话框组件：复用 Material `AlertDialog`，按钮 `[取消]` `[退出]`
  （退出按钮使用 `colorScheme.error` 文字色以提示破坏性意图）。
- 文案：标题 `退出编辑器？`；正文 `未导出的拼图将丢失。`。

### R5 确认退出 = 清空状态
- 用户点击确认对话框的「退出」按钮后：
  1. `ref.read(stitchEditorControllerProvider.notifier).clear()`
     （或 grid 同源 controller）
  2. `Navigator.pop()` 回到首页
- 编辑器 controller 已经存在 `clear()` 方法
  （见 `stitch_editor_provider.dart:220`）；本次直接复用。

### R6 AppBar 返回箭头 size class 区分
- `StitchEditorScreen` / `GridEditorScreen` 的 AppBar 增加
  `automaticallyImplyLeading: isCompactSecondary` 控制：
  - compact + 当前路由是 `/m/*`（即真正的二级页面）→ 显示返回箭头
  - 其他情况 → 不显示（保持桌面端 branch 根的现状）
- 判断方式：`GoRouterState.of(context).uri.path` 是否以 `/m/` 开头，
  或简单地用 `Navigator.canPop(context)`（二级页面里 canPop=true，
  branch 根 canPop=false，天然区分）。

### R7 桌面端 ZERO 改动
- medium / expanded / large 三档下：路由、底部导航、首页卡片行为
  全部维持现状；既有 widget 测试不破。

### R8 spec 同步
- 更新 `.trellis/spec/frontend/component-guidelines.md` 增加新约定：
  - compact 下编辑器走 `/m/*` 根级 sibling 路由覆盖 shell
  - PopScope 拦截二次确认的范式（hasImages 才拦）
  - 与现有 "StatefulShellRoute + per-branch screen" 约定共存

## Acceptance Criteria

### 路由 & 导航
- [ ] compact 视口 (< 600 dp) 下，AppBottomNavBar 仅显示「功能大全」「设置」两项
- [ ] medium 及以上视口，AppBottomNavBar 仍显示 4 项（既有行为不变）
- [ ] compact 视口首页点击「长图拼接」卡片，URL 变为 `/m/stitch`，
      编辑器盖住底部导航条，AppBar 出现返回箭头
- [ ] compact 视口首页点击「宫格切图」卡片，行为对称（`/m/grid`）
- [ ] medium 及以上视口首页点击「长图拼接」卡片，URL 变为 `/stitch`，
      底部导航仍可见（既有行为不变）

### 二次确认
- [ ] compact `/m/stitch` 下导入≥1 张图后点 AppBar 返回箭头，弹 `AlertDialog`
- [ ] 同上场景按 Android 系统后退键，弹同样 `AlertDialog`
- [ ] 同上场景执行 iOS 边缘滑动后退，弹同样 `AlertDialog`
- [ ] 空编辑器（未导图）点返回箭头，直接 pop 回首页，**不弹**对话框
- [ ] 对话框点「取消」→ 停留在编辑器，状态不变
- [ ] 对话框点「退出」→ 编辑器状态被 clear()，回到首页；再次进入是空画布

### 桌面端不退化
- [ ] medium 视口切换 stitch ↔ grid ↔ home tab，状态保留（IndexedStack）
- [ ] expanded / large 视口编辑器布局、FAB、侧边面板全部一致

### 工程
- [ ] `flutter analyze` 0 error 0 warning
- [ ] 既有 `stitch_editor_responsive_test.dart`、
      `stitch_editor_bottom_bar_test.dart` 等不破，必要时改 router fixture
- [ ] 新增 compact 路径 widget 测试覆盖：
  - `/m/stitch` 路由可达 + AppBar 有返回箭头
  - `hasImages` 时弹 dialog；不 hasImages 时直接 pop
  - 确认退出后 controller 被 clear
- [ ] `dart format .` 已应用

### Spec
- [ ] `.trellis/spec/frontend/component-guidelines.md` 新增章节
      「compact 编辑器二级页面 + PopScope 二次确认」

## Definition of Done

- 代码改动通过 `flutter analyze` + `dart format .`
- 所有新增 + 既有测试 `flutter test` 通过
- spec 同步更新
- PRD `Out of Scope` 之外的需求全部实现
- 不引入新的 lint 警告

## Decision (ADR-lite)

### ADR-1：移动端 = `WindowSizeClass.compact`（< 600 dp）
**Context**：需要明确"移动端"以驱动 router 分支与底部导航裁剪。
**Decision**：采用 Material 3 Window Size Class — `< 600 dp` 视为移动端。
**Consequences**：手机竖屏走新行为；手机横屏 / 平板 / 桌面均沿用 4 tab。

### ADR-2：双路由 — branch + 根级 sibling 并存
**Context**：桌面端需保留 4 tab（既有 spec 约束），移动端需要"覆盖底部导航 +
PopScope 拦截二次确认"的真二级页面行为。
**Decision**：保留 ShellRoute 4 branch；新增 `/m/stitch`、`/m/grid` 根级
sibling 以 `parentNavigatorKey: _rootNavigatorKey` 覆盖 shell。首页
FeatureCard 按 size class 分流。同一个 EditorScreen 被两条路径复用，
Riverpod 状态自然跨 Navigator 共享。
**Consequences**：
- 桌面端代码 / 测试 ZERO 改动
- 同一 Screen 被两路径覆盖，需双套入口测试
- 路由命名前缀 `/m/`（mobile）需写进 spec 注释

### ADR-3：二次确认 = `hasImages` 即弹 + 三入口统一拦截
**Context**：避免空编辑器误弹；同时不能因为入口不同而漏拦。
**Decision**：仅当 `state.hasImages == true` 弹；AppBar 返回箭头 / Android
系统后退键 / iOS 边缘滑动统一进 `PopScope.onPopInvokedWithResult`。
**Consequences**：实现简单（单一拦截点）；用户心智一致；空编辑器无打扰。

### ADR-4：确认退出 = clear() + pop 到首页
**Context**：二次确认文案承诺"未导出的拼图将丢失"，必须与实际行为对齐。
**Decision**：确认对话框「退出」按钮 → `controller.clear()` → `Navigator.pop()`。
**Consequences**：与文案一致；下次进入是空画布；桌面端 branch 切换
不触发此路径，桌面端状态保留行为不变。

## Out of Scope (explicit)

- 不重构编辑器内部 widget 树（StitchEditorScreen / GridEditorScreen
  内部布局、面板、底栏布局全部保持不变）。
- 不动 `/export` 路由（仍是覆盖 shell 的根级 sibling）。
- **不强制导出成功后跳回首页**（保持当前 pop 回编辑器的行为）。
- 不引入「未保存改动」状态位（isDirty 追踪），仅用 `hasImages` 作为判定。
- 不引入二次确认的全局服务（仅本次两个二级页面专用，工具函数复用）。
- 不调整 AppBottomNavBar 的视觉规范（仍是 Material 3 `NavigationBar`）。
- 不预留「作品库 / 收藏」中间 tab。

## Technical Approach

### 关键文件改动清单
| 文件 | 改动 |
|---|---|
| `lib/app/router.dart` | 新增 `/m/stitch`、`/m/grid` 两条 sibling GoRoute（参考 `/export` 写法） |
| `lib/core/widgets/bottom_nav_bar.dart` | `destinations` 由 const 改为方法/getter，按 size class 返回 2 或 4 项 |
| `lib/core/widgets/app_shell.dart` | `_onDestinationSelected` 在 compact 下做 index → branch 映射（0→0, 1→3） |
| `lib/features/home/presentation/widgets/feature_card.dart` 或调用方 | `onActionPressed` 改为按 size class 分流 `push` vs `go` |
| `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` | 增加 PopScope + 二次确认 dialog 逻辑（封装到 helper） |
| `lib/features/grid/presentation/screens/grid_editor_screen.dart` | 对称增加 |
| 新增 `lib/core/widgets/discard_editor_dialog.dart`（或同等位置） | 共享对话框 widget + 触发函数 |
| `.trellis/spec/frontend/component-guidelines.md` | 增加新章节 |
| `test/features/long_stitch/...` | 既有测试 fixture 改 router；新增 compact 路径用例 |

### 实现要点

1. **AppBottomNavBar 改造**：把 `destinations` 静态常量改为
   `static List<AppNavDestination> destinationsFor(WindowSizeClass)`，
   AppShell 透传 size class 进来。注意 NavigationBar 的 `selectedIndex`
   需对应裁剪后的列表，AppShell 要做映射。

2. **AppShell index 映射**：
   ```
   compact:  display [home, settings]   → branch [0, 3]
   其他:     display [home, stitch, grid, settings] → branch [0, 1, 2, 3]
   ```
   提供 `_displayToBranch(int displayIndex, bool isCompact)` 与
   `_branchToDisplay(int branchIndex, bool isCompact)` 双向辅助。

3. **PopScope + Dialog**：编辑器顶层包 `PopScope(canPop: !hasImages, ...)`。
   注意 `canPop` 动态依赖 `hasImages`，需在 `ConsumerWidget.build` 里 watch
   editor controller 让 PopScope 跟着重建。

4. **dialog 取消时**：不 pop，不清状态；用户继续编辑。
   **dialog 确认时**：先 `clear()` 再调用 `Navigator.pop(context, true)`
   配合 `PopScope` 的 `onPopInvokedWithResult` 处理。

5. **测试 router fixture**：把 `stitch_editor_responsive_test.dart` 的
   harness 改为同时注册 `/stitch` 和 `/m/stitch` 两路径；既有 desktop
   测试用 `/stitch`，新增 compact 测试 `pushNamed('/m/stitch')`。

## Implementation Plan (small PRs)

考虑到改动横跨 router/shell/feature 三层，分 3 个原子 commit（同一 PR 内）：

- **commit 1**：router + bottom nav + app shell 改造（双路由 + 条件 destinations
  + index 映射），不动 editor 行为。验收：compact 下能进 `/m/stitch`、
  返回箭头出现、但还没有二次确认；桌面端完全不变。
- **commit 2**：editor 二次确认（PopScope + dialog + clear() + 取消按钮逻辑），
  加上 FeatureCard 的 size class 分流。验收：完整 MVP 行为。
- **commit 3**：测试 + spec update + 文档（包括 component-guidelines.md
  新章节）。验收：CI 全绿，spec 同步。

## Technical Notes

- 关键文件：见上方 Technical Approach 表
- 已有约束：
  - 编辑器在 size class 切换时不应丢状态（既有约束，本次延续；clear
    只发生在用户主动「确认退出」时）
  - 桌面端 spec「StatefulShellRoute + per-branch screen」不被推翻，
    只是增加 compact 二级页面的并存约定
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md` → StatefulShellRoute 约定
  - `.trellis/spec/frontend/responsive-layout.md` → 编辑器响应式行为
  - `.trellis/spec/frontend/state-management.md` → Riverpod 跨屏交互
- Riverpod 生命周期：`StitchEditorController` 是普通 `Notifier`（非
  AutoDispose），跨 push/pop 自然保留 — 这正是双路由方案能复用编辑器
  状态的基础。
