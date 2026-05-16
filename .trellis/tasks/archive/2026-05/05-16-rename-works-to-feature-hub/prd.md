# rename works library to feature hub

## Goal

将首页 tab 从「作品库」改名为「功能大全」，同时移除首页中的「最近作品」板块（标题 + RecentWorksGrid 占位），让首页聚焦在功能入口卡片与提示横幅，不再展示 MVP 还未实现的作品列表占位。

## What I already know

- 底部导航栏 label 在 `lib/core/widgets/bottom_nav_bar.dart:44` 的 `destinations[0].label = '作品库'`。
- 「最近作品」头部 + 「查看全部」按钮位于 `lib/features/home/presentation/screens/home_screen.dart:127-163`（`Padding` 包裹的 `Row`）。
- 最近作品占位栅格在同文件 `:164-167`，引用 `lib/features/home/presentation/widgets/recent_works_grid.dart` 的 `RecentWorksGrid`。
- `lib/app/router.dart:37` 的 doc-comment 写着「(作品库 / 长图拼接 / 宫格切图 / 设置)」，需要同步更新文案。
- 受影响测试：
  - `test/core/widgets/app_shell_test.dart:59,86,123` 通过 `_navDestination('作品库')` 定位 tab，需要改成新文案。
  - `test/features/home/presentation/home_screen_responsive_test.dart:3,96-127` 4 处 `RecentWorksGrid` 断言会随板块移除而失效。
- `RecentWorksGrid` 当前仅被 `home_screen.dart` 引用，移除最近作品后该 widget 没有其他使用者。

## Confirmed Decisions (user-approved 2026-05-16)

- 首页保留「问候头部 / 标题 / FeatureCards / TipsBanner」四块，移除「最近作品标题 + 查看全部 + RecentWorksGrid」三块。
- ✅ 删除 `lib/features/home/presentation/widgets/recent_works_grid.dart` 文件（避免 dead code）。
- ✅ 路由路径保持 `/`、route name 仍为 `home`（避免 deep-link 失效）。
- ⚠️ 底部导航 tab[0] 图标同步替换：`Icons.image_outlined → Icons.apps_outlined`，`Icons.image → Icons.apps`（更贴合「功能大全」语义；`Icons.apps_outlined` 已在 SDK 中验证存在）。
- ✅ 测试文件中所有 `'作品库'` 字面量同步改为 `'功能大全'`。
- `home_screen_responsive_test.dart` 中对 `recentWorksColumns` / `RecentWorksGrid` 的响应式断言整体删除（不替换为其它板块的断言）。
- 底部导航以外的位置（FAQ、文案、README 等）没有用户可见的「作品库」字符串需要改。

## Requirements

- 底部导航第 0 个 tab 的 `label` 改为「功能大全」，`icon` 改为 `Icons.apps_outlined`，`selectedIcon` 改为 `Icons.apps`。
- 首页 `_HomeBody` 移除「最近作品」section header（含「查看全部」按钮）和 `RecentWorksGrid` 占位。
- 删除 `lib/features/home/presentation/widgets/recent_works_grid.dart`。
- 同步更新 `lib/app/router.dart:37` 的 doc-comment 文案（"作品库" → "功能大全"）。
- 同步更新 `lib/features/home/presentation/screens/home_screen.dart:17-22` 的响应式表格 doc-comment（移除 recent works grid 列）。
- 更新受影响测试：
  - `app_shell_test.dart:59,86,123`：三处 `_navDestination('作品库')` 改成 `_navDestination('功能大全')`。
  - `home_screen_responsive_test.dart`：删除涉及 `RecentWorksGrid` 的测试用例 + 顶部 import + `recentWorksColumns` 断言。

## Acceptance Criteria

- [ ] App 启动后底部第一个 tab 文字显示「功能大全」，未选中时显示 `Icons.apps_outlined`，选中时显示 `Icons.apps`。
- [ ] 切换到首页 tab 后页面不再出现「最近作品」标题、「查看全部」按钮和占位栅格。
- [ ] `lib/features/home/presentation/widgets/recent_works_grid.dart` 文件被删除。
- [ ] `flutter analyze` 干净（无未使用 import、无 dead code 警告）。
- [ ] `flutter test` 全部通过（含改写后的 app_shell / home_screen 响应式用例）。

## Definition of Done (team quality bar)

- Tests 更新到位（删除 RecentWorks 断言、更新 nav label 字面量），并继续保持响应式 size class 覆盖。
- `dart format .`、`flutter analyze`、`flutter test` 全部干净。
- 移除 dead code（`RecentWorksGrid` 及其引用），不保留 `// TODO` 占位。
- Doc-comment 与底部导航 label 保持一致（"功能大全"）。

## Out of Scope (explicit)

- 不重命名 tab 对应路由路径（继续是 `/`、name 仍为 `home`，避免外部 deep-link 失效）。
- 不实现「功能大全」的新内容（暂不新增功能卡片、不新增分类区）；本任务只是移除 + 改名，新增 feature 留给后续任务。
- 不改 tab 图标。
- 不改 `_3_首页/code.html` 等 design mock。

## Technical Notes

- 关键文件：
  - `lib/core/widgets/bottom_nav_bar.dart`
  - `lib/features/home/presentation/screens/home_screen.dart`
  - `lib/features/home/presentation/widgets/recent_works_grid.dart`（删）
  - `lib/app/router.dart`
  - `test/core/widgets/app_shell_test.dart`
  - `test/features/home/presentation/home_screen_responsive_test.dart`
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/responsive-layout.md`
  - `.trellis/spec/frontend/directory-structure.md`
