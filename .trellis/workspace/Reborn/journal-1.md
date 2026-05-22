# Journal - Reborn (Part 1)

> AI development session journal
> Started: 2026-05-07

---



## Session 1: Bootstrap Guidelines - populate frontend spec

**Date**: 2026-05-07
**Task**: Bootstrap Guidelines - populate frontend spec
**Branch**: `main`

### Summary

Populated .trellis/spec/frontend/ with Flutter project conventions (directory-structure, component-guidelines, provider/hook-guidelines, state-management, type-safety, quality-guidelines). Marked backend spec as not applicable (pure local app). Updated .gitignore for AI agent files.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `31fdc84` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Project Init: Dependencies & Platform Permissions Bootstrap

**Date**: 2026-05-09
**Task**: Project Init: Dependencies & Platform Permissions Bootstrap
**Branch**: `main`

### Summary

Bootstrapped fl_picraft pubspec deps (riverpod, go_router, image, image_picker, file_picker, super_drag_and_drop, super_clipboard, reorderables, path_provider, gal, share_plus + dev tooling) and configured iOS/Android/macOS permissions/entitlements for image-pick + save flows. All AC pass: pub get clean, analyze clean, format clean, both Debug and Release entitlements mirrored. Captured surfaced gotchas into .trellis/spec/frontend/dependencies-and-platforms.md (Riverpod 2.x lock, riverpod_annotation must be runtime dep, Android 13+ permission split, iOS three-key Photo Library requirement, macOS dual entitlements file requirement).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `e7a59aa` | (see git log) |
| `5e393bb` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: Base Architecture: GoRouter + MD3 theme + BottomNav + HomeScreen

**Date**: 2026-05-09
**Task**: Base Architecture: GoRouter + MD3 theme + BottomNav + HomeScreen
**Branch**: `main`

### Summary

Bootstrapped the real Flutter app shell over the default counter template: ProviderScope at root, MaterialApp.router with GoRouter (5 flat top-level routes), MD3 light theme hand-curated from UI design tokens (#4F378A primary), seed-generated dark theme, AppScaffold + MD3 NavigationBar (4 tabs), HomeScreen with feature cards / tips banner / recent works grid, and shared PlaceholderBody for in-progress feature stubs. Fixed macOS deployment target from 10.15 to 11.0 (Podfile + project.pbxproj all 3 occurrences) so gal plugin's pod install succeeds. Captured 4 new conventions in component-guidelines.md (MD3 token sourcing, asymmetric light/dark theme strategy, flat routing + per-screen AppScaffold, placeholder screens) plus IntrinsicHeight gotcha; added google_fonts to approved package table and a new macOS deployment-target floor section in dependencies-and-platforms.md; synced design tokens table in frontend/index.md to the production palette. flutter analyze clean, flutter test passing.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `f687762` | (see git log) |
| `e839d52` | (see git log) |
| `fc09322` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: Image Import 模块完成 + spec 模式提取

**Date**: 2026-05-09
**Task**: Image Import 模块完成 + spec 模式提取
**Branch**: `main`

### Summary

归档 Foundation 父任务后启动 Image Import (P1)。trellis-implement 子代理基于 prd.md 与 spec 实现完整模块：4 种导入源（gallery / camera / clipboard / drag-drop）× 6 平台，统一标准化为 ImportedImage，含 RawImageBytes DTO 隔离插件类型、20 张硬上限、>=2MB off-isolate 解码、camera 三层防御。trellis-check 自修 1 处文档 bug；主会话再修 3 个快胜项（满 20 短路 picker、AsyncLoading.copyWithPrevious 防闪空、删 _FirstOrNull 死代码扩展）。29/29 测试通过、analyze 0 issues。Phase 3.3 提取 3 个高复用模式入 spec：Data-source DTO isolation、Platform-aware datasource dispatch（含三层防御）、Preserve previous data during AsyncLoading。最终归档 05-08-image-import。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `f7318aa` | (see git log) |
| `f5084cc` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: Long Stitch Feature: vertical/horizontal + movie subtitle modes

**Date**: 2026-05-09
**Task**: Long Stitch Feature: vertical/horizontal + movie subtitle modes
**Branch**: `main`

### Summary

Shipped both Long Stitch subtasks end-to-end: vertical/horizontal stitch editor (new lib/features/long_stitch/ with data/domain/presentation, off-isolate compute() renderer, reuses existing image-import flow, 12 new files + 2 test files) and movie-subtitle layered-overlay mode (flag-overlay on StitchMode.vertical with subtitleOnlyMode + subtitleBandHeight on the existing state class, all consumers route through computeStitchLayout for uniform flag check). Captured two new specs: reorderable list key stability gotcha (use ObjectKey or stable id, not position-embedded keys) in component-guidelines.md, and the flag-overlay vs new-enum-variant decision pattern in type-safety.md. 50/50 tests pass, analyze clean.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `aef4c63` | (see git log) |
| `5a12208` | (see git log) |
| `c538135` | (see git log) |
| `0b32ba1` | (see git log) |
| `c2e7cf1` | (see git log) |
| `602ffcc` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: Watermark feature: isolate-safe text composition

**Date**: 2026-05-14
**Task**: Watermark feature: isolate-safe text composition
**Branch**: `main`

### Summary

Implemented 05-08-watermark subtask: domain entities (anchor/font/config), pure-Dart computeAnchor usecase, isolate-safe applyWatermark rasterizer using image package, Riverpod leaf provider, WatermarkCard widget with toggle/text/3x3 picker/opacity slider. 31 new tests (anchor math, config rules, rasterizer short-circuit/snapshot/shrink, widget interactions); flutter analyze clean, 81/81 tests green. Captured new spec pattern in frontend/directory-structure.md — 'Isolate-safe rasterizer in data/' — encoding the dart:ui-vs-compute() constraint that drove the image-package choice over TextPainter; cross-layer guide updated with a checklist pointer.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `2106d93` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 7: Multi-Platform Export 实现与父任务收尾

**Date**: 2026-05-14
**Task**: Multi-Platform Export 实现与父任务收尾
**Branch**: `main`

### Summary

完成 export-multiplatform 子任务：PNG/JPG 编码 + 平台分发保存（iOS/Android via gal、桌面 via file_picker、Web via package:web Blob）。trellis-check 修了 grid 循环 partial-save accounting 的 UX bug，并加 PersistAdapter 测试 seam。spec 更新：dependencies-and-platforms.md 补充 file_picker 在 web 无 saveFile() 的事实 + package:web Blob 下载方案 + gal album 空字符串/扩展名陷阱 + 4 行新 Validation & Error Matrix。质量门：dart format clean、flutter analyze 无 issues、flutter test 113 passed。归档当前任务及父任务 export-watermark（[2/2] 完成）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `bf47d21` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 8: Regular Grid Split: 11 types + spec pattern

**Date**: 2026-05-14
**Task**: Regular Grid Split: 11 types + spec pattern
**Branch**: `main`

### Summary

Implemented the Regular Grid Split feature under lib/features/grid/ with 11 grid types (1x2 through 4x4), live preview overlay, per-cell PNG export wired to the existing ExportRepository, and 4 test files (155/155 green). Dispatched trellis-implement then trellis-check; check caught a Clean Architecture leak (IconData on a GridType enum in domain/) and moved the icon mapping to a presentation/-side extension. Captured the lesson as a new 'Framework-free domain entities' Pattern in frontend/directory-structure.md plus a checklist line in cross-layer-thinking-guide.md. Generic computeGridLayout(rows, cols) and a reserved nineGridSocialMode field leave the sibling 05-08-nine-grid-social task ready to plug in.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `4fdd209` | (see git log) |
| `aadf200` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 9: Nine-grid social mode: implement, check, spec capture

**Date**: 2026-05-14
**Task**: Nine-grid social mode: implement, check, spec capture
**Branch**: `main`

### Summary

Implemented 3x3 social grid with center-cell image replacement (pinch+pan). Reused regular-grid layout and image-import repository via side-channel pattern; canonical centerOffset unit is source pixels with widget-boundary conversion. trellis-check caught two non-trivial bugs (preview-vs-export unit mismatch; missing PRD step-1 square-crop) and self-fixed both. Captured three spec updates: cross-layer unit semantics, ScaleUpdateDetails.focalPointDelta gotcha, side-channel repository reuse. 219/219 tests green, analyze clean. Archived nine-grid-social + parent grid-split.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `2b65af6` | (see git log) |
| `2bd9584` | (see git log) |
| `9ea709b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 10: Polish & Multi-Platform Readiness — 8 rounds across export unification, responsive, a11y, dark mode, perf

**Date**: 2026-05-16
**Task**: Polish & Multi-Platform Readiness — 8 rounds across export unification, responsive, a11y, dark mode, perf
**Branch**: `main`

### Summary

polish-platform-test 任务的 8 轮迭代收尾。Round 1 quick wins（清理 stub / 注释 / 空回调）→ Round 2a grid/stitch 导出统一到 /export 屏（ExportSource sealed + ExportSourceKind enum dispatch）→ Round 2b 错误文案中文化（lib/core/errors/user_facing_messages.dart + 14 callsite）→ Round 2c 响应式（Material 3 WindowSizeClass + 4 主屏 sheet/panel 双形态）→ Round 2d 暗色 alphaBlend + a11y meetsGuideline 测试 + import failure snackbar → Round 3 perf benchmark harness + Timeline markers。最终 274 test pass + 5 benchmark + analyze clean。Spec 提炼出 2 新建（responsive-layout / error-handling）+ 6 修改。剩余 PRD 验收（真机性能 + 6 平台兼容）通过 manual-test-plan.md 等用户手动执行。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1748862` | (see git log) |
| `a4904d3` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 11: 底部导航从扁平路由切换为 StatefulShellRoute（状态保留）

**Date**: 2026-05-16
**Task**: 底部导航从扁平路由切换为 StatefulShellRoute（状态保留）
**Branch**: `main`

### Summary

Refactor bottom-nav from flat GoRoute + per-screen AppScaffold to StatefulShellRoute.indexedStack rooted at a new AppShell. Each branch keeps its own Navigator stack so tab switches preserve state (R1). NavigationBar identity survives switches (R2). Android back-key follows a three-layer contract: inner Navigator pop → goBranch(0) → SystemNavigator.pop (R8). /export stays a sibling top-level route outside the shell; currentExportSourceKindProvider handoff unchanged. Rewrites .trellis/spec/frontend/component-guidelines.md "Flat routing" section. Adds 5 widget tests in test/core/widgets/app_shell_test.dart covering R1/R2/R8 including SystemNavigator.pop platform-channel mock. flutter analyze: clean. flutter test: 279 passed, 2 skipped (benchmark), 0 failed.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `5701514` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 12: subtask1: editor + all screens fill container width

**Date**: 2026-05-16
**Task**: subtask1: editor + all screens fill container width
**Branch**: `main`

### Summary

Brainstormed the editor-layout-and-import-isolation parent task and split it into two sibling subtasks. Implemented subtask1 in full: removed Breakpoints.maxContentWidth (1200 dp cap) so home / stitch / grid / export screens fill SafeArea on wide windows; reshaped both editors' docked control panel to a fluid [380, 480] dp clamp computed via LayoutBuilder + (container * 0.25).clamp; rewrote stitch_preview_canvas to fit the available area with a vertically-unbounded fallback for the compact SingleChildScrollView path. Spec responsive-layout.md rewritten in three places (Cap convention, panel-width convention, behavior table large columns) plus a new Common Mistakes gotcha codifying the LayoutBuilder + unbounded-parent trap discovered in the preview canvas refactor. Added panel-clamp widget tests at 1280 / 1920 / 2560 dp viewports across home / export / stitch / grid. flutter analyze clean, dart format clean, 281 tests pass. Sibling subtask 05-16-per-mode-import-isolation remains in planning with PRD + jsonl curated, ready to start.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `07490ba` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 13: subtask2: per-mode image import session isolation + parent task closure

**Date**: 2026-05-16
**Task**: subtask2: per-mode image import session isolation + parent task closure
**Branch**: `main`

### Summary

Closed the 05-16-editor-layout-and-import-isolation parent task by delivering its second subtask. Converted imageImportControllerProvider and importedImagesProvider to AsyncNotifier.family / Provider.family keyed by a new ImageImportSessionKind { stitch, grid } enum (with stability dartdoc warning that value names are Riverpod family cache keys). ImageDropZone now requires a typed sessionKind parameter so each editor screen funnels drops into its own session at compile time. Stitch and grid editor controllers / screens resolve their family instance via .stitch / .grid; nine-grid-social pickCenterImage still bypasses the import controller. Added sessionKindFor(ExportSourceKind) bridge in export_dispatch.dart to keep the two enums as independent types (no reverse layer dependency from image_import to export). New cross_mode_isolation_test covers AC2.1-2.4 with plain test + ProviderContainer to avoid the FakeAsync timer-pending interaction in testWidgets; per-mode session isolation group in image_import_controller_test covers list / lastWarning / clear / AsyncError independence. All editor / export / responsive / social tests updated to thread the family kind through their overrides. Four spec additions: state-management.md (Pattern: Per-mode session isolation via .family); component-guidelines.md (Convention: Require a typed mode parameter when a widget feeds a .family provider); type-safety.md (Pattern: Parallel enum domains with explicit bridge function); quality-guidelines.md (Pattern: Plain test over testWidgets for AsyncNotifier-only assertions under FakeAsync). flutter analyze clean, dart format clean, 289 tests pass.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `a460571` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 14: Rename works tab to 功能大全 & plan grid canvas height-first fit

**Date**: 2026-05-16
**Task**: Rename works tab to 功能大全 & plan grid canvas height-first fit
**Branch**: `main`

### Summary

Brainstorm 阶段拆分出两个独立 trellis 任务：(1) rename-works-to-feature-hub 完成 PRD/jsonl/implement/check/commit 全流程——底部导航 tab[0] label 作品库 → 功能大全、icon image_outlined/image → apps_outlined/apps，移除首页最近作品 section 与 RecentWorksGrid 占位 widget，更新 router.dart doc-comment、app_shell_test.dart 3 处 nav 断言、home_screen_responsive_test.dart 删除 RecentWorks 用例，6 files / 14 ins / 157 del，analyze 与 285 tests 全绿。(2) grid-canvas-height-first-fit 完成 PRD/jsonl，确认采用 Approach A（compact/medium ListView → Column+Expanded 高度优先骨架，画布占据剩余高度保持 1:1 居中、控件面板独立内部滚动），等待实施。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ed9b1b0` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 15: Grid canvas height-first compact-mode skeleton + spec sediment

**Date**: 2026-05-17
**Task**: Grid canvas height-first compact-mode skeleton + spec sediment
**Branch**: `main`

### Summary

Task 2 (grid-canvas-height-first-fit) 完整实施: compact/medium 模式 grid_editor_screen 重构为 Column + Expanded(Center(AspectRatio(1, Canvas))) + Flexible(loose, SingleChildScrollView(Panel)) 高度优先骨架；画布占据剩余高度保持 1:1 居中，控件面板独立内部滚动。GridPreviewCanvas 移除内部 AspectRatio sizing contract 迁移到调用方，expanded/large 调用处补包 AspectRatio(1) 保持现状。新增 compact 骨架测试（无外层 ListView + canvas square + panel SingleChildScrollView 祖先 + 无 widget tree 异常），放宽 compact+medium panelOrigin.dx 严格相等断言。5 files / 236 ins / 46 del；analyze 0 issues / 286 tests passed。Spec 沉淀: responsive-layout.md 新增 Pattern 'Compact-mode editor body — height-first Column skeleton' + Gotcha 'Flexible(loose) vs Expanded' + responsive behavior table 拆分 stitch/grid 两行。设计判断: Flexible(loose) 优于 Expanded 避免画布与控件之间的视觉裂缝（已在代码 inline 注释与 spec Gotcha 双重沉淀）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b3812b8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 16: Cleanup stale archived task paths

**Date**: 2026-05-17
**Task**: Cleanup stale archived task paths
**Branch**: `main`

### Summary

清理 task.py archive 命令遗留的 12 个 D 状态路径——archive 将 task 目录 move 到 .trellis/tasks/archive/2026-05/ 时只 stage 了新位置 add，没 stage 旧位置 delete，导致 working tree 长期 dirty。本任务用 git rm 一次性把三个受影响 task (05-16-editor-layout-and-import-isolation / per-mode-import-isolation / grid-canvas-height-first-fit) 的旧路径 deletion 提交进去。12 files / 534 deletions / 0 insertions；archive/ 下副本完整保留；flutter analyze 干净；无代码改动。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0b62bf2` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 17: Extend grid canvas height-first to expanded/large windows

**Date**: 2026-05-17
**Task**: Extend grid canvas height-first to expanded/large windows
**Branch**: `main`

### Summary

Follow-up 修复上一轮 task (05-16-grid-canvas-height-first-fit) 的 Out-of-Scope 漏洞：桌面端全屏 (1920×1080+) / ultra-wide / 平板横屏下画布按宽度撑成正方形纵向溢出。根因是 useSidePanel 分支左列用 SingleChildScrollView > Column(stretch) > AspectRatio(1, Canvas)，SingleChildScrollView 给 unbounded 纵向约束导致 AspectRatio 退化为按宽度算高度。修复方案 (Approach A): 左列改为 Expanded > Column(stretch) > Expanded(Center(AspectRatio(1, Canvas))) + warning，Row.crossAxisAlignment 从 start 改为 stretch 让左列继承 row 高度——画布在两轴都受限时取较短边 min(leftColW, rowH)，与 compact/medium 高度优先骨架对称。4 files / 223 ins / 55 del；新增 expanded (1280×800) + large (1920×1080) 两个不超高 + 正方形 + panel docked 断言；改写 'content fills wide windows' 用 panel right-edge 代替 canvas+panel width 之和；analyze 0 issues / 288 tests passed。Spec 沉淀: pattern 改名为 'Editor body — height-first Column skeleton (single-column + side-panel variants)' 并新增 side-panel variant 子段（Row(stretch) 关键性 + 左列移除 SingleChildScrollView + symmetry summary）；responsive behavior table grid_editor expanded/large 列更新。本任务承认上一轮判断失误（Out-of-Scope 划得过保守）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `af0e667` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 18: Grid side-panel surface chrome + viewport reactivity test

**Date**: 2026-05-17
**Task**: Grid side-panel surface chrome + viewport reactivity test
**Branch**: `main`

### Summary

需求 1 (画布实时响应窗口拖拽): LayoutBuilder + Row(stretch) 已实现，本次仅补测试覆盖动态改 viewport 后画布尺寸跟随。需求 2 (右侧控制栏铺满容器高度): 给 expanded/large 右列加 surface 背景容器 (surfaceContainerLow + outlineVariant + 16dp 圆角 + clipAntiAlias)，从顶部贴到底部；内部 GridControlsPanel 保持 bare + 顶部对齐 + SingleChildScrollView 内部滚动。设计判断: Container vs DecoratedBox+Padding 选 Container 与 _SourceSizeWarning / NineGridSocialRow 在本 codebase 的 idiom 保持一致；SingleChildScrollView.padding 内置 16 而非外层 Padding 包裹，让滚动条贴边、内容留呼吸。导出 kGridControlsPanelChromeKey 给测试定位（文件级 const，dartdoc 注明用途，不引 package:meta @visibleForTesting）。新增 3 个测试: 动态 viewport tracking / chrome 高度铺满 row / chrome decoration 颜色断言；3 个既有测试从 find.byType(GridControlsPanel) 迁移到 find.byKey(chromeKey) 因为 chrome 是新的 side column。3 files / 243 ins / 29 del；analyze 0 issues / 291 tests passed。Spec 沉淀: 新增 'Convention: Caller decoration variants' (bare/chrome 两种 caller 模式对比 + grid (chrome) vs stitch (bare) 决策表 + 'panel 内部保持 bare' guardrail)；responsive behavior table grid_editor expanded/large 列同步。stitch_editor / GridControlsPanel / GridLayout / Painter 未改动。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ef0448c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 19: Extend side-panel chrome to compact and medium

**Date**: 2026-05-17
**Task**: Extend side-panel chrome to compact and medium
**Branch**: `main`

### Summary

修复 compact / medium (手机/平板竖屏) 模式下控制栏下方大片裸白留白：Column 的 Flexible(loose) 在高屏幕下只取 panel intrinsic 高度，剩余 share - intrinsic 留在底部成为裸白页面背景。修复方案: compact 也加 expanded/large 已有的 surface chrome (surfaceContainerLow + outlineVariant + 16dp 圆角 + clipAntiAlias + 内 padding 16)，Flexible(loose) 改为 Expanded(fit=tight) 让 chrome 强制填满 free_space/2 覆盖裸白。抽 top-level helper _buildControlsPanelChrome(BuildContext) 让 compact 与 useSidePanel 两个分支共用 chrome，drift surface 为 0；同一 kGridControlsPanelChromeKey 复用（两分支互斥渲染）。3 files / 256 ins / 77 del；analyze 0 issues / 294 tests passed (含 3 个新增 compact / medium chrome 断言)。Spec 沉淀: 反转 Gotcha 'Flexible(loose) — not Expanded' 为「双模 Gotcha」(bare → Flexible(loose); chrome → Expanded)；Pattern Editor body compact / medium 代码示例改为 chrome 变体；Convention: Caller decoration variants 改为 per-editor × per-size-class 表格明确 grid 在所有 size class 都加 chrome、stitch 保持 bare；responsive behavior table grid_editor compact/medium 列同步。stitch_editor / GridControlsPanel / GridLayout / Painter 未改。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `08f575f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 20: Portrait grid panel bottom spacing fix

**Date**: 2026-05-17
**Task**: Portrait grid panel bottom spacing fix
**Branch**: `main`

### Summary

Eliminated the 96 dp page-bg strip between the grid editor chrome and the bottom nav on compact/medium widths by inlining FAB clearance into the chrome SingleChildScrollView bottom padding (hasSource ? 80 : 16). Outer Padding dropped from 96 to 16. Side-panel branch unchanged. Added 6 widget tests and a new spec convention block.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0ed8f34` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 21: Brainstorm grid drag/overwrite/chrome umbrella + ship ST-A chrome

**Date**: 2026-05-17
**Task**: Brainstorm grid drag/overwrite/chrome umbrella + ship ST-A chrome
**Branch**: `main`

### Summary

Ran trellis-brainstorm to decompose 三宫格切图三项改动 (canvas drag-select / overwrite-import / borderRadius=0) into an umbrella + 3 subtasks. Locked D1 pan+zoom, D2 unified square crop (breaking: non-social 3x3 cells become square-derived), D3 confirm-then-overwrite, D4 four MVP edge enhancements (clamp / reset button / hide-grid-on-drag / center-cell gesture priority). Then shipped ST-A: GridPreviewCanvas chrome borderRadius 16→0; three red lines green, no test migration needed.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `aa75f21` | (see git log) |
| `0aaa43c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 22: ST-B: grid overwrite-on-import with destructive confirm

**Date**: 2026-05-17
**Task**: ST-B: grid overwrite-on-import with destructive confirm
**Branch**: `main`

### Summary

Shipped ST-B of grid-canvas-drag-overwrite. AppBar import action now guards re-import behind a Material 3 destructive-confirm dialog when state.hasSource: confirm clears the grid-kind import session before launching the picker (overwrite via existing _syncSourceFromImports listener), cancel preserves state. First-time imports skip the dialog. Controller surfaces this as addFromGallery({bool replace = false}); the sourceOffset/Scale reset path is deliberately deferred to ST-C. Three red lines green, 304 tests passing (+4 new widget tests covering replace / cancel / first-import / barrier-dismiss). Non-blocking design note: a late picker-cancel after dialog-confirm leaves source null with no recovery — consent-aligned per umbrella D3 dialog copy.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `7a129c9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 23: ST-C: drag+pinch-zoom canvas crop; umbrella closed

**Date**: 2026-05-17
**Task**: ST-C: drag+pinch-zoom canvas crop; umbrella closed
**Branch**: `main`

### Summary

Closed the grid-canvas-drag-overwrite umbrella with ST-C. The grid editor canvas now drives an explicit square crop region via one-finger pan + two-finger pinch-zoom; the same crop math (compute_source_crop.dart, isolate-safe) feeds both the preview transform and the renderer's cell-slicing path, so what the user drags into view byte-matches what exports (RGB-band integration test on 600x300 source). Per umbrella D2 this is a breaking change: every cell is now 1:1 regardless of grid type / source aspect. R-DRAG-05 (overlay gesture priority) implementation revealed a Flutter gesture-handling subtlety: ancestor HitTestBehavior.deferToChild does NOT short-circuit hit-test the way intuition suggests; the correct pattern is sibling z-order with overlay's HitTestBehavior.opaque blocking propagation. Captured into component-guidelines.md as a new Gotcha next to the existing focalPointDelta entry. 334 tests passing (+30 new), three red lines green.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `53994d4` | (see git log) |
| `2b749da` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 24: Fix grid preview canvas spacing gap visibility

**Date**: 2026-05-17
**Task**: Fix grid preview canvas spacing gap visibility
**Branch**: `main`

### Summary

宫格切图模式调整间距时画布看不到 gap 视觉效果（原图原样透出）。在 _GridOverlayPainter 中新增 spacing + gapColor 字段，spacing > 0 时通过 saveLayer + 整片 drawRect(surfaceContainer) + BlendMode.clear 沿 RRect 挖空 cell 区域，让 gap 区域显示画布背景色，与导出后真实切片视觉等价。颜色用 M3 token (colorScheme.surfaceContainer) 注入，主题切换自动跟随。新增 3 个 painter widget 测试（spacing=0 路径 gated / spacing>0 路径 saveLayer + surfaceContainer fill / dark mode 主题切换）。三红线全绿：analyze 0 errors / format unchanged / 337 tests passed。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `c1c24be` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 25: Remove outline border from GridPreviewCanvas decoration

**Date**: 2026-05-17
**Task**: Remove outline border from GridPreviewCanvas decoration
**Branch**: `main`

### Summary

宫格切图画布外缘的 outlineVariant 描边线视觉过重。删除 GridPreviewCanvas.build 中 BoxDecoration.border 单行，保留 color (surfaceContainer — gap-fill 视觉契约依赖)、borderRadius、boxShadow (轻微投影维持画布层级感) 与 clipBehavior。1 行删除、单文件改动、0 测试改动。三红线全绿：analyze 0 errors / format unchanged / 337 tests passed。surfaceContainer 视觉契约 (上一轮 05-17-grid-spacing-color-fix 引入) 完整保留，相关 gap fill / drag 测试全部通过、无回归。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1196e49` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 26: Plan grid-slice revamp + finish Subtask A

**Date**: 2026-05-17
**Task**: Plan grid-slice revamp + finish Subtask A
**Branch**: `main`

### Summary

Brainstormed the grid-slice editor revamp (per-cell replacement + square cells + 5-variant text selector), scaffolded parent task with 3 dependency-ordered subtasks, and completed Subtask A: pruned GridType enum to {g1x2, g1x3, g2x2, g2x3, g3x3}, deleted grid_type_icons.dart, rebuilt GridTypeSelector as text-only cards (title + description), hid the 9-grid-social toggle, synced directory-structure.md, migrated 6 test files. Build gates clean: dart format + flutter analyze + flutter test (332 passed / 2 skipped). Subtasks B (square geometry) and C (per-cell replacement) remain in planning.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `2023943` | (see git log) |
| `1840679` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 27: Finish Subtask B: square cells + canvas aspect=cols:rows

**Date**: 2026-05-17
**Task**: Finish Subtask B: square cells + canvas aspect=cols:rows
**Branch**: `main`

### Summary

Architecture-core change for the grid-slice revamp. computeGridLayout now takes cellSide and emits uniform square rects; compute_source_crop accepts targetAspect; GridEditorState drops nineGridSocialMode + center* fields; GridRenderRequest mirrors that; renderer crops source to cols/rows then carves square cells; preview canvas + screen AspectRatio both read gridType.cols/rows reactively. CenterCellOverlay stubbed as passive placeholder for Subtask C. Tests: rewrote grid_layout for square assertions; new targetAspect cases on compute_source_crop; responsive AspectRatio asserted for g1x3 / g2x3 / g3x3; 4 social/center tests stubbed with deferral notes. flutter analyze clean · 300 passed / 3 skipped. Subtask C remains for per-cell replacement + CellOverlay generalization.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `64017b7` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 28: Finish Subtask C + close grid-slice-revamp umbrella

**Date**: 2026-05-17
**Task**: Finish Subtask C + close grid-slice-revamp umbrella
**Branch**: `main`

### Summary

Closing subtask of the grid-slice editor revamp. Implemented per-cell image replacement: CellReplacement domain entity, Map<int, CellReplacement> on GridEditorState (cleared on grid-type change), CellReplacementBytes isolate-safe DTO + per-cell render dispatch in grid_image_renderer, generalized CellOverlay (renamed from CenterCellOverlay) mounted on every layout rect, 5 new controller interfaces (pickCellImage / setCellImage / setCellScale / setCellOffset / resetCell). Hit-test policy: empty cells translucent (canvas drag falls through), replaced cells opaque (per-cell gestures win). Semantics labels carry cell index + row/col coordinates. Renamed compute_center_transform.dart → compute_cell_transform.dart with all Center* → Cell* symbols. flutter analyze clean · flutter test 323 passed / 3 skipped. All 5 parent ADR-lite decisions (D1–D5) hold up against the final codebase. Parent umbrella 05-17-grid-slice-revamp archived (3/3 subtasks done).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `40d6bbc` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 29: Cell add-circle hint icon

**Date**: 2026-05-17
**Task**: Cell add-circle hint icon
**Branch**: `main`

### Summary

Added Icons.add_circle_outline as a persistent affordance hint on every grid cell (both empty and replaced states). 32 dp, Colors.white + Colors.black54 drop shadow, no backdrop circle, IgnorePointer + ExcludeSemantics so it's purely decorative and doesn't break the existing gesture contract (translucent empty / opaque replaced) or a11y labels. New _CellAddHint private widget in cell_overlay.dart; two new widget tests asserting the icon appears in both states. flutter analyze clean; flutter test 325 passed / 3 skipped (was 323; +2).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `2fd162c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 30: Fix: tap on replaced cell re-picks image

**Date**: 2026-05-18
**Task**: Fix: tap on replaced cell re-picks image
**Branch**: `main`

### Summary

User reported 'cells can only be covered once'. Root cause: _ReplacedCell had no onTap handler — only longpress menu → '替换图片' offered the re-replace path. Controller (setCellImage) was already correct. Fix: added onTap to _ReplacedCell.GestureDetector calling pickCellImage(cellIndex); Flutter gesture arena routes tap vs scale vs longpress automatically. New regression widget test seeds imageA, queues imageB on a fake picker repo, taps the CellOverlay, asserts the stub was invoked + state image is imageB. flutter analyze clean · flutter test 326 passed / 3 skipped (+1 new test).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b0bf9d3` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 31: Fix: cell hint icon fades with grid lines

**Date**: 2026-05-18
**Task**: Fix: cell hint icon fades with grid lines
**Branch**: `main`

### Summary

User reported visual inconsistency — during source-image drag the grid lines fade out (via _PreviewSurfaceState._isGesturing wrapped in AnimatedOpacity 150ms) but the Icons.add_circle_outline hint on each cell stayed fully visible because CellOverlay was mounted as a sibling, not a child, of the grid-lines fade. Fix: thread a required isGesturing bool from _PreviewSurface through CellOverlay → _EmptyCellTarget / _ReplacedCell → _CellAddHint; the hint wraps its Icon in AnimatedOpacity(150ms) syncing with grid lines. Replacement images in _ReplacedCell stay at full opacity (user still needs to see them during drag). 7 existing test sites updated with isGesturing: false; 2 new tests assert opacity 0/1 + 150ms duration parity. flutter analyze clean · flutter test 328 passed / 3 skipped (+2).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8ca307d` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 32: fix grid cell image pan freeze at default scale

**Date**: 2026-05-18
**Task**: fix grid cell image pan freeze at default scale
**Branch**: `main`

### Summary

Fixed grid-mode replaced cells being unable to pan/drag at default userScale=1.0. Root cause: setCellOffset/setCellScale called clampCellOffset with the replacement image's own width/height as cellWidth/cellHeight (shape-proxy anti-pattern), collapsing maxD to zero. Fix: made cellWidth/cellHeight required source-pixel parameters; widget supplies sourceCellWidth/Height from layout.rects[i]. Added grid_cell_image_pan_test regression coverage (AC6 non-same-aspect scale=1.0, AC7 diagonal at scale>1.0). Documented the shape-proxy anti-pattern as Mistake 6 in cross-layer-thinking-guide.md.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `e545551` | (see git log) |
| `13e30ba` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 33: 改进长图拼接模式 UX

**Date**: 2026-05-18
**Task**: 改进长图拼接模式 UX
**Branch**: `main`

### Summary

为长图拼接编辑器添加一键清空（AlertDialog 二次确认）、已选图片板块折叠/展开（默认展开）、底部导航 + 首页 feature card 的「长图拼接」图标由 photo_library 改为 view_agenda、预览画布灰底 surface 撑满 Expanded 高度并保留长图滚动；配套 widget 测试覆盖 AC1–AC7，flutter analyze / test 全绿。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `a5aafda` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 34: Long-stitch toolbar height cap + subtitle-mode polish

**Date**: 2026-05-18
**Task**: Long-stitch toolbar height cap + subtitle-mode polish
**Branch**: `main`

### Summary

Capped the compact/medium StitchControlsSheet height at max(200, min(screenHeight*0.28, 360)) with an internal SingleChildScrollView so the canvas reclaims visual area. Switched subtitle band height from absolute pixels to a percent-of-first-image-height field (5-50%, default 12%), hid the no-op 图片间距 slider in subtitle mode, and added an opt-in auto-trim-black-bars toggle backed by a new detect_letterbox usecase that scans each decoded image and feeds the insets into _layoutMovieSubtitle. Promoted the height-cap idiom into responsive-layout.md as a reusable convention.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ac9a1ef` | (see git log) |
| `72f0f4d` | (see git log) |
| `13f09af` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 35: Stitch subtitle band — reset percent on first-image re-pick

**Date**: 2026-05-18
**Task**: Stitch subtitle band — reset percent on first-image re-pick
**Branch**: `main`

### Summary

Added empty->non-empty edge detection in StitchEditorController's ref.listen so subtitleBandHeightPercent resets to its default when the user clears all images and picks a fresh batch. The reset is unconditional (does not gate on subtitleOnlyMode) and guarded by a three-predicate AND (prev empty/null, next non-empty, state.images empty) so the listener's first-fire on a seeded editor does not clobber the percent. Added 7 provider-level tests including a non-trivial first-fire-guard test. Captured the listener idiom in spec/frontend/state-management.md with a counter-example pointing at grid_editor_provider's pure-mirror form.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ff0b56e` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 36: Long-image stitch: horizontal-mode tweaks (hide divider + height-fill scroll)

**Date**: 2026-05-18
**Task**: Long-image stitch: horizontal-mode tweaks (hide divider + height-fill scroll)
**Branch**: `main`

### Summary

Tightened the long-image stitch horizontal mode. Panel: hid the section Divider when subtitle module is gone (it was dangling between mode picker and spacing slider). Canvas: drove SingleChildScrollView.scrollDirection off StitchMode and added _PreviewSurface.fillAxis so horizontal mode height-fills the viewport and a wide canvas pans rightward; narrow canvas stays centered. Added widget tests for Divider visibility per mode + horizontal-mode scroll axis / extent / center / height-fill. 378 tests + flutter analyze green.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `7cfa910` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 37: Long-stitch wide-screen vertical selected list + reorder/scroll fixes

**Date**: 2026-05-18
**Task**: Long-stitch wide-screen vertical selected list + reorder/scroll fixes
**Branch**: `main`

### Summary

宽屏（>=840dp）长图拼接编辑器右侧侧栏对半分纵向已选列表 + 控制栏；新增 StitchVerticalImageList 组件、共享 confirmStitchClear helper；修复两个真实运行 bug：reorderables 0.6.0 post-removal index 与 controller 的 pre->post 调整冲突导致前->后拖拽错位、SingleChildScrollView(primary: true) 让 ReorderableColumn 双 attach 同一个 ScrollPosition 触发 _positions.length==1 崩溃。responsive-layout.md 同步更新。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `3a024a3` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 38: Rename app display name to Fl PiCraft

**Date**: 2026-05-19
**Task**: Rename app display name to Fl PiCraft
**Branch**: `main`

### Summary

Renamed user-visible application name to Fl PiCraft across iOS / Android / macOS / Linux / Windows / Web, and renamed the macOS build artifact to Fl PiCraft.app via PRODUCT_NAME + xcscheme/pbxproj sync. Verified with flutter build macos --debug -> build/macos/Build/Products/Debug/Fl PiCraft.app (CFBundleExecutable=Fl PiCraft). Technical identifiers (pubspec name, applicationId, bundle id, Linux/Windows BINARY_NAME) intentionally preserved per PRD Out of Scope. Drive-by: dropped a pre-existing unused colorScheme local in stitch_editor_screen as a separate fix(lint) commit.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `70dda6b` | (see git log) |
| `104a2e9` | (see git log) |
| `7d2d4e8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 39: 修复导出页返回动画 + 格式按钮选中态对比度

**Date**: 2026-05-19
**Task**: 修复导出页返回动画 + 格式按钮选中态对比度
**Branch**: `main`

### Summary

/export 进入改 context.push、返回优先 context.pop()，外层加 PopScope 统一 AppBar/系统返回/iOS 边缘手势三条返回路径；deep-link 兜底仍走 currentExportSourceKindProvider+go。_FormatButton 选中态由 primaryContainer+primary（紫底紫字）改为 primary+onPrimary（紫底白字），与 StitchModeSegmented 配色一致。flutter analyze clean / 387 tests pass。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `91970af` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 40: 修复宫格切图 1080x1440 EXIF 压扁 + 沉淀跨层 Gotcha

**Date**: 2026-05-19
**Task**: 修复宫格切图 1080x1440 EXIF 压扁 + 沉淀跨层 Gotcha
**Branch**: `main`

### Summary

定位根因：ImportedImage.width/height 来自 image.startDecode（不应用 EXIF），Image.memory 显示时却自动按 EXIF 旋转 → 元数据与显示视角错位，BoxFit.fill 拉扁。同根因下导出 cell 方向也错。修复策略 = Approach A：在 image_normalizer.dart 顶层 isolate-safe 函数 bakeOrientationToBytes 中烤入 orientation，所有下游 feature 零改动受益；orientation=1 走 same-instance 快路径，bake 失败回退原 bytes 不丢 import。新增 normalizer 单测（含 orientation=1/3/6 + PNG + 损坏字节）+ grid preview widget 回归测试。spec 沉淀：component-guidelines 新 Gotcha 章节；cross-layer-thinking-guide Mistake 4b + checklist 条目。所有测试 397 通过。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `81ee65b` | (see git log) |
| `abb72f4` | (see git log) |
| `cbed641` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 41: fix(platform): google_fonts macOS sandbox + Android release manifest

**Date**: 2026-05-19
**Task**: fix(platform): google_fonts macOS sandbox + Android release manifest
**Branch**: `main`

### Summary

用户报告 macOS 上 google_fonts 运行时 fetch 失败(SocketException Operation not permitted)。根因是 macOS 沙盒只开了 network.server 没开 network.client。修复方案 B(用户选项):给 Debug/Release entitlements 同补 network.client。Audit 阶段意外发现 Android main/AndroidManifest.xml 漏声明 INTERNET——Flutter 模板仅向 debug/profile manifest 注入该权限,release 合并清单不含,任何运行时网络 fetch 在 release apk 都会静默失败。顺手一并修复。Spec 沉淀两个 Critical Gotcha 章节 + Error Matrix 两行,用 captured-from 引用本任务。验证:flutter analyze 零问题、397 测试全过、flutter run -d macos 控制台零字体警告、runtime errors 零条目。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ce69ec8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 42: 修复长图拼接 stitch 卡片移除按钮在移动端视觉过大 + 沉淀 a11y spec

**Date**: 2026-05-20
**Task**: 修复长图拼接 stitch 卡片移除按钮在移动端视觉过大 + 沉淀 a11y spec
**Branch**: `main`

### Summary

修复 StitchImageStrip._ImageCard 卡片角标 × 按钮在移动端视觉过大问题。V1 padded 方案 (视觉/hit area 解耦) 真机测试发现 splash halo 仍让按钮显得过大，V2' 改用 MaterialTapTargetSize.shrinkWrap (hit area = visual = 24x24) 作为 card-corner badge 场景的显式视觉/a11y trade-off (违反 androidTapTargetGuideline)。新增 widget test 守护 shrinkWrap 决策 (反向 sanity guard ≤28x28)。沉淀 3 个 a11y 知识点到 .trellis/spec/frontend/component-guidelines.md：(1) Pitfall tapTargetSize:padded + visualDensity:compact 互相 cancel (hit area 跌至 40dp)、(2) Caveat padded splash halo 在 card-corner badge 场景的视觉副作用 (3 options trade-off menu)、(3) Pattern Direct render-size guard via find.ancestor + tester.getSize。Known follow-up: 桌面端 _VerticalImageRow 32x32 hit area 同样违反 spec、editor screens 缺 surface-level a11y test。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `47e3eb1` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 43: fix(export): 导出保存按钮解除主 isolate 卡顿

**Date**: 2026-05-20
**Task**: fix(export): 导出保存按钮解除主 isolate 卡顿
**Branch**: `main`

### Summary

修复 ExportRepositoryImpl._processOne 在主 isolate 同步跑 applyWatermark + encodeForExport 导致点击保存按钮卡 UI 线程到弹窗出现的 bug。9 宫格场景累计 18 次 decode/encode 串行阻塞 UI。按 brainstorm 收敛的 Approach A：把 _processOne 折叠成 top-level _processOneInIsolate 入口 + _ProcessOneRequest DTO 走 compute()，沿用 stitch_image_renderer / grid_image_renderer 的 'compute + 单测同步 fallback' 模式；新增 export.process Timeline marker 配合既有 export.save 做 DevTools triage。新增 3 个 isolate-hop 集成测试覆盖 stitch + grid 两条路径，既有 watermark_renderer / image_encoder snapshot 全绿确认字节 deterministic 一致；402 测试通过 + analyze clean。PRD 明确把 'spec 措辞收紧 may→MUST'、UI 增强、Approach C 消除冗余 decode/encode 列为 out-of-scope，update-spec 阶段评估无新洞察值得沉淀，跳过。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `32e07f9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 44: Subtask 1：macOS Settings 菜单桥接 + 桌面窗口管理父任务规划 + spec 沉淀

**Date**: 2026-05-20
**Task**: Subtask 1：macOS Settings 菜单桥接 + 桌面窗口管理父任务规划 + spec 沉淀
**Branch**: `main`

### Summary

完成 05-20-desktop-window-mgmt-and-menu 父任务的 brainstorm：父 PRD（含 ADR-lite D-A~D-H 与 4-PR 实施计划）+ 三端 native 调研报告（macOS frameAutosaveName + contentMinSize / Windows PerMonitorV2 + WM_GETMINMAXINFO / Linux GTK Wayland 降级矩阵）+ 4 个 subtask 拆分及各自的 mini PRD/implement.jsonl/check.jsonl。落地 Subtask 1（macOS Settings 菜单桥接到 /settings 路由）：MainMenu.xib 文案改 'Settings…'（U+2026）+ <connections> target=Voe-Tx-rLC + IBAction openSettings: on AppDelegate + MenuChannelBridge.swift 封装 FlutterMethodChannel('app.fl_picraft/menu') + lib/core/native/menu_channel.dart 端 setMethodCallHandler 调 appRouter.go('/settings') + lib/main.dart 加 WidgetsFlutterBinding.ensureInitialized() + MenuChannel.bind + 4 cases 单测覆盖契约。途中踩 macOS Xcode 新文件需注册到 Runner.xcodeproj/project.pbxproj 4 段（PBXBuildFile/PBXFileReference/PBXGroup/PBXSourcesBuildPhase）的坑，已沉淀到 .trellis/spec/frontend/dependencies-and-platforms.md（含 Windows CMakeLists/Linux CMakeLists 三端对照表 + UUID 生成方法 + sanity-check 项）。验证：flutter analyze clean、flutter test 406 passed、flutter build macos --debug ✓。剩余 3 subtask（macOS/Windows/Linux 窗口策略）待续；当前父任务进度 1/4 done。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b4fef07` | (see git log) |
| `a74abe7` | (see git log) |
| `558d159` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 45: Subtask 2：macOS 窗口策略（80% 默认 + contentMinSize + frameAutosaveName）+ NSWindow 时序 spec 沉淀

**Date**: 2026-05-20
**Task**: Subtask 2：macOS 窗口策略（80% 默认 + contentMinSize + frameAutosaveName）+ NSWindow 时序 spec 沉淀
**Branch**: `main`

### Summary

落地 05-20-desktop-window-mgmt-and-menu 父任务的 Subtask 2（macOS 原生窗口策略）：在 macos/Runner/MainFlutterWindow.swift 的 awakeFromNib 内顺序执行 contentMinSize=1280×800（excludes title bar）→ 计算 max(80% × visibleFrame, 1280×800) 居中默认 frame → setFrame(_:display:)（唯一不受 minSize clamp 的 setter）→ setFrameAutosaveName('fl_picraft.main')（一行接入 AppKit 自动持久化-恢复，多屏拓扑变化由 constrainFrameRect:to: 自动 clamp）。PR-1 既有的 MenuChannelBridge 接线完整保留。同步沉淀 NSWindow 时序约定到 .trellis/spec/frontend/dependencies-and-platforms.md 新增 §'macOS: NSWindow.setFrameAutosaveName MUST come after setFrame'（含 Wrong vs Correct 对照、AppKit 读 UserDefaults 时机说明、defaults delete + resize + relaunch 三步 smoke 模板、Validation & Error Matrix 新条目、Scope/Trigger 加'Implement custom NSWindow/Win32Window/GTK window lifecycle logic in a platform runner'第 6 项）—— 这是非显时序陷阱，无 compile warning / 无 runtime exception / flutter analyze 不覆盖。验证：flutter analyze clean、flutter test 406 passed、flutter build macos --debug ✓、app 启动 smoke 无 crash。父任务进度 2/4 done（剩 Windows、Linux 两个 subtask）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `17884a7` | (see git log) |
| `e888439` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 46: Subtask 3：Windows 窗口策略（INI + WM_GETMINMAXINFO + WM_CLOSE rcNormalPosition）+ Win32 双 spec 沉淀

**Date**: 2026-05-20
**Task**: Subtask 3：Windows 窗口策略（INI + WM_GETMINMAXINFO + WM_CLOSE rcNormalPosition）+ Win32 双 spec 沉淀
**Branch**: `main`

### Summary

落地 05-20-desktop-window-mgmt-and-menu 父任务的 Subtask 3（Windows Win32 原生窗口策略）：新建 windows/runner/window_state.{h,cpp}（INI 持久化 + 80% × rcWork 居中默认 + ≥100×100 多屏可见性兜底 + DPI snapshot）；改 main.cpp（启动时 LoadWindowState 优先 / 物理像素 ÷ scale 转逻辑像素传 Win32Window::Create / NonNeg 防 unsigned wrap）；改 win32_window.cpp（Win32Window::MessageHandler 加 WM_GETMINMAXINFO + WM_CLOSE 两个 case，分别用 AdjustWindowRectExForDpi(WS_OVERLAPPEDWINDOW) 设 ptMinTrackSize 物理像素 + GetWindowPlacement.rcNormalPosition 抓 restored rect 避开 maximized 污染）；改 CMakeLists.txt 加 window_state.cpp 到 add_executable 并链接 shcore.lib + shell32.lib。trellis-check 22 项独立复核 21 PASS + 1 UNVERIFIED（flutter build windows 本机不可用），并抓到并修了真实 bug：GetPrivateProfileIntW 静默把负值返回 0（Microsoft 文档明确说明的 quirk），改用 GetPrivateProfileStringW + wcstol 自己解析十进制保留有符号语义。同步沉淀 2 节 Win32 API 陷阱到 .trellis/spec/frontend/dependencies-and-platforms.md：§'Windows: GetPrivateProfileIntW silently returns 0 for negative integers'（含 Wrong vs Correct 代码、何时仍可安全使用、验证模板）+ §'Windows: WINDOWPLACEMENT.rcNormalPosition is workspace coordinates'（4 种 layout 影响对照表 + option A 转换 / option B SetWindowPlacement 两个修复方案 + 当前 repo 已知限制说明）。Validation & Error Matrix 同步 +2 条目。父任务进度 3/4 done。剩 Subtask 4（Linux）和 Windows 端的物理 smoke 验证（本机 macOS 跑不了 flutter build windows，用户需在 Windows 机器上跑 Smoke Verify Script 后方可宣布完工）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b292b6c` | (see git log) |
| `ba3cb7b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 47: Subtask 4：Linux GTK 3 窗口策略 + Wayland 降级矩阵 spec 沉淀（父任务 4/4 done 收尾）

**Date**: 2026-05-20
**Task**: Subtask 4：Linux GTK 3 窗口策略 + Wayland 降级矩阵 spec 沉淀（父任务 4/4 done 收尾）
**Branch**: `main`

### Summary

落地 05-20-desktop-window-mgmt-and-menu 父任务的 Subtask 4（Linux GTK 3 原生窗口策略，最后一棒）：仅改 1 个文件 linux/runner/my_application.cc，新增 #ifdef GDK_WINDOWING_WAYLAND header 守卫 + 7 个 static helpers（state_file_path / ensure_state_dir / SavedGeometry struct / load_saved_geometry / rect_is_visible / compute_default_geometry / apply_initial_geometry）+ delete-event signal handler。核心设计：gtk_window_set_geometry_hints(NULL, &hints, GDK_HINT_MIN_SIZE) 设最小 1280×800（geometry_widget=nullptr 匹配 GTK 3.20+）→ gdk_display_get_primary_monitor() ?? gdk_display_get_monitor(display, 0) Wayland fallback + gdk_monitor_get_workarea × 80% + MAX(1280,...)/MAX(800,...) 防御 clamp（Subtask 2/3 carry-forward）→ gtk_window_set_default_size 后跟 gtk_window_move(x,y) 在 #ifdef GDK_WINDOWING_X11 + GDK_IS_X11_DISPLAY 守卫下调用；delete-event 回调 gtk_window_get_size 无条件读尺寸 + gtk_window_get_position 同 X11 守卫；g_key_file_save_to_file 原子写入（GLib 2.40+ 内部 g_file_set_contents 临时文件 + rename）；return FALSE 让 GTK 继续 destroy。CMakeLists 无需改动（PkgConfig::GTK 已传递性带入 gdk-x11 + gdk-wayland）。trellis-check 21 项 PASS + 1 UNVERIFIED（flutter build linux 本机不可用）。同步沉淀 Linux Wayland 降级矩阵到 .trellis/spec/frontend/dependencies-and-platforms.md 新增 §'Linux: GTK 3 Wayland window-API degradation matrix'：4 个 API（primary_monitor / workarea / get_position / move）X11 vs Wayland 行为对比表 + GTK 3.24 源码追溯（class_init 未注册对应 vfunc）+ Wrong vs Correct 双层守卫代码示例（#ifdef GDK_WINDOWING_X11 + GDK_IS_X11_DISPLAY runtime）+ 单位约定（logical 像素，不要乘 scale_factor，与 Windows 物理像素路线相反）+ GLib 自动原子写入与 Win32 手动 flush 对比 + GTK 3 vs GTK 4 swap-points 表 + X11/Wayland 双 session smoke 模板。Validation & Error Matrix +1 综合条目。\n\n至此 05-20-desktop-window-mgmt-and-menu 父任务全部完成（4/4 subtasks archived → 父任务也归档）。3 端 native 实现 + 5 条 spec 沉淀（Desktop runners 注册 / macOS NSWindow autosave 时序 / Win32 INI 负值 / Win32 WINDOWPLACEMENT workspace 坐标 / Linux Wayland 4-API 降级）形成完整 cross-platform 对称布局。剩余物理 smoke 验证待用户在真实 macOS / Windows / Linux 机器上各自跑 prd.md Smoke Verify Script；本机 macOS 已通过 PR-1/2 自动化验证（analyze + test + build），Win/Linux 自动化在本机不可达（无 SDK），通过代码 + 研究文档 + spec 三重交叉复核保证逻辑正确性。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `4f6e1f3` | (see git log) |
| `36679e1` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 48: 移动端控制栏紧凑化（长图 sheet + 宫格 flex 倾斜 + 选中卡自动可见）

**Date**: 2026-05-20
**Task**: 移动端控制栏紧凑化（长图 sheet + 宫格 flex 倾斜 + 选中卡自动可见）
**Branch**: `main`

### Summary

compact/medium 下压低长图 sheet 上限至 min(0.22h, 320)（floor 200 不变），宫格 chrome 改用 Expanded(flex:3)+Expanded(flex:2) 倾斜分配剩余空间；轻量压缩 _BentoCard 128→104 与 GridTypeSelector strip 104→92 缓解 chrome 拥挤。顺手修复 GridTypeSelector 默认末位 g3x3 首屏不可见（StatefulWidget + ScrollController + PostFrameCallback animateTo）。原 Flexible(loose)+ConstrainedBox 方案因 chrome 收缩暴露页背景被回滚，spec 新增 Lesson 沉淀该踩坑。413 tests passed / 3 skipped。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8cd0768` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 49: 长图拼接：导入图片 20 张上限 UI 封锁

**Date**: 2026-05-20
**Task**: 长图拼接：导入图片 20 张上限 UI 封锁
**Branch**: `main`

### Summary

长图拼接编辑器达 20 张上限时，UI 层封锁所有可用入口。新增 imageImportSessionFullProvider selector（共享 kMaxImportSessionImages 单一来源）；StitchImageStrip / StitchVerticalImageList 两处「添加」按钮 onPressed:null + Tooltip「已达上限 20 张」；ImageDropZone 拒绝外部拖入并 snackbar 反馈；保留 ReorderableRow 内部排序（任何 count 下都可用，R-CAP-07）。新增 6 widget + 4 provider 测试覆盖 AC1-AC10。spec 补充 TextButton.icon / IconButton.icon 私有子类 finder 陷阱（component-guidelines.md）。flutter analyze 0 issues，flutter test 423 passed。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8906f0a` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 50: 导出页面预览基础设施（Subtask A：渲染管线 + save cache 共享 + Riverpod controller）

**Date**: 2026-05-21
**Task**: 导出页面预览基础设施（Subtask A：渲染管线 + save cache 共享 + Riverpod controller）
**Branch**: `main`

### Summary

Subtask A of 05-20-export-page-preview 完成。grill 7 轮锁定 7 项设计决策（NotifierProvider<SealedState>、controller 内部拉 source + editor.state.hashCode 作 cache 键、processExportBytes 中性命名、PreviewLoading.staleBytes 过渡、refresh 保守语义、typedef + Provider 注入让 FakeAsync 真正可用、save 路径复用 preview cache 跳过 isolate hop）。实施抽取 processExportBytes 公共渲染函数、新增 5 个 provider/state 文件、改造 ExportRepository.persistOnly + ExportController.save 命中 cache 直走 persistOnly。31 个新测试 + 现有 454/454 全绿；spec/state-management.md 沉淀 2 pattern + 1 common mistake。Subtask B（UI）仍 planning 未开始。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `100e671` | (see git log) |
| `98fd023` | (see git log) |
| `4275f40` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 51: 导出页面预览 UI 集成（Subtask B）+ 实测反馈四轮修复 + cache 生命期 audit

**Date**: 2026-05-21
**Task**: 导出页面预览 UI 集成（Subtask B）+ 实测反馈四轮修复 + cache 生命期 audit
**Branch**: `main`

### Summary

Subtask B of 05-20-export-page-preview 完成，父任务 2/2 done 一并 archive。1) 落地 PreviewCard / PreviewThumbnail / PreviewSkeleton / PreviewFullScreenDialog 四个 widget + 16 个 widget 测试，顶部插入 export_screen。2) 实测反馈触发四轮修复：D4 二次修订（stale → widget canvas → spinner+文案最终方案）、D5 全屏 viewer pan boundary fix、D6 stale-flash 消除（build 同步检查 cache + listen 同步预转 Loading）、D7 多 editor screen FAB heroTag 唯一化、D8 previewControllerProvider 改 autoDispose 修后台 isolate render leak + 内存留存。3) trellis-check 专项 audit 缓存清理时机，发现 Scenario A leak + B 过度清理 + F 内存 risk；用户选 A+F 走 autoDispose 修复，B 留 follow-up 已记 PRD。4) 沉淀 spec 6 条：state-management.md (typedef+Provider、NotifierProvider<SealedState>、stale-state-flash、Split lifecycle autoDispose+cache 4 条) + component-guidelines.md (stale-while-loading、FAB heroTag 2 条) + quality-guidelines.md (pumpAndSettle indefinite animation 1 条) — wait 重数；实际 spec 含 7 条新 pattern/gotcha。474/474 tests pass、analyze clean。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ac33a90` | (see git log) |
| `fe9f9ad` | (see git log) |
| `b88997c` | (see git log) |
| `e52555f` | (see git log) |
| `8041335` | (see git log) |
| `1790412` | (see git log) |
| `675a48a` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 52: 导出页面微调：FormatQualityCard fg 修正 + SaveActionButton 改 FAB.extended

**Date**: 2026-05-21
**Task**: 导出页面微调：FormatQualityCard fg 修正 + SaveActionButton 改 FAB.extended
**Branch**: `main`

### Summary

导出页面两处 UI 收尾微调：(1) FormatQualityCard._FormatButton 选中态 fg 从 onPrimaryContainer 改回 onPrimary，对齐 MD3 token 配对规则（背景 primary + 前景 onPrimary），修复上次 05-19 任务遗留的注释/实现漂移；(2) SaveActionButton 从 inline 全宽 FilledButton 重构为 FloatingActionButton.extended，加入 stitch/grid 命名族 (heroTag: 'export-save-fab')，遵守 component-guidelines.md:967 的 FAB heroTag 强制约定；export_screen Scaffold 增 floatingActionButton + endFloat 槽位，body 末尾 88dp 防遮挡。删除失效的 'stays full-width' 响应式测试。三件套全绿（473 tests）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `036b9b9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 53: 新增关于页面（独立 feature + url_launcher manifest spec）

**Date**: 2026-05-21
**Task**: 新增关于页面（独立 feature + url_launcher manifest spec）
**Branch**: `main`

### Summary

新增 features/about/ 独立 feature 承载 AboutScreen（112dp 图标 / 应用名 / 描述副标题 / 动态版本号 / 项目源码-问题反馈-开源许可三个 ListTile，subtitle 显示去 https:// URL）。core/constants/app_info.dart 用 class AppInfo 聚合元信息（与 Breakpoints 一致）。settings 加「关于」入口 + GoRouter /settings/about 子路由（push 语义）。引入 package_info_plus + url_launcher（archive/path 附带提交供 batch-export-all 复用）。trellis-check 发现并修复 url_launcher 在 Android 11+/iOS 9+ 的 silent canLaunchUrl 失败（缺 <queries> / LSApplicationQueriesSchemes），并把该 lesson 固化到 spec/frontend/dependencies-and-platforms.md（+87 行 cross-platform section + Validation Matrix 一行）。PRD 经过 grill 固化 9 个决策（D1-D9）。13 个新测试全过 + flutter analyze 干净 + flutter test 486 passed。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `513d677` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 54: 多图批量一键导出：BatchPersistAdapter 三端 pull-based 流式落地

**Date**: 2026-05-22
**Task**: 多图批量一键导出：BatchPersistAdapter 三端 pull-based 流式落地
**Branch**: `main`

### Summary

把 Grid 多图导出从「一张一确认」改成「一次操作搞定全部」。抽象 BatchPersistAdapter pull-based 流式接口，三端各自决定内存形状：桌面 getDirectoryPath + 批量写入 / Web archive 打包 zip 单次下载 / 移动 gal 循环写相册保持现状。新增 7 个 datasource 文件 + 5 个测试文件，526 测试全过；spec 同步落地 4 处：dependencies-and-platforms（Export 段 + 依赖锁兼容性 convention）、directory-structure（batch adapter 3 文件 conditional import pattern）、error-handling（双前缀反模式）、quality-guidelines（Timeline refactor guardrail）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `169703a` | (see git log) |
| `a16284d` | (see git log) |
| `97e4128` | (see git log) |
| `84e2deb` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 55: 全屏预览升级为沉浸式照片查看器

**Date**: 2026-05-22
**Task**: 全屏预览升级为沉浸式照片查看器
**Branch**: `main`

### Summary

导出页面 PreviewFullScreenDialog 全面升级为主流相册级沉浸式查看器：黑底全屏 + AppBar 透明叠加 + chrome 3 秒自动隐藏 + 常驻浮动 X；统一手势契约（minScale=1.0、未放大禁 pan、双击 2.0x 放大且双击点为锚 / 留白区回退中心、双击复位）；多图 PageView + 自定义 _ImmersivePageScrollPhysics 实现 photo-gallery 风格边缘弹切；向下拖关闭手势。修复两个回归：桌面端 PageView 鼠标拖动经自定义 ScrollBehavior 接通；放大态 vertical drag recognizer 通过 null callback 退出 arena 保证 InteractiveViewer 单指 pan 不被吞。两份 ADR（自定义 ScrollPhysics / 5 手势分层）+ 3 个 Flutter sharp-edge Gotcha 沉淀进 component-guidelines.md。测试 24/24，全项目 545/545。会话前期顺手修了 GridEditorScreen AppBar actions 多余 Padding 间距过宽问题（已被合并进 ab35c33）。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `a81d9bc` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 56: 全屏预览 pan 边界限制 + 居中

**Date**: 2026-05-22
**Task**: 全屏预览 pan 边界限制 + 居中
**Branch**: `main`

### Summary

PreviewFullScreenDialog 的 InteractiveViewer 配置改为 boundaryMargin: EdgeInsets.zero 配合 Center(SizedBox(renderedSize, Image(fit: fill))) 的 child 结构，让用户无法把图片完全 pan 出 viewport。最终采用 M-α 方案（constrained: true 默认 + Center 居中 + boundaryMargin: zero），视觉等价主流相册的图片像素边缘语义（dialog 黑底 + letterbox 黑色 → 用户感知不到差异）。中途曾尝试 L-β 严格方案（constrained: false + SizedBox(renderedSize) + alignment: center + boundaryMargin: zero）但 Flutter 源码 interactive_viewer.dart:1130-1138 硬编码 OverflowBox(alignment: Alignment.topLeft) 导致居中丢失，被回退。ADR-0001 Compatibility Note 重写为 M-α 三件套 + Why M-α not L-β 子段引用 Flutter 源码行号。quality-guidelines.md 新增 testing pattern：widget test 中用 tester.runAsync + precacheImage 触发 Image decode（FakeAsync zone 不驱动 ui.instantiateImageCodec 回调，pumpAndSettle 永远等不到），避免测试静默走 fallback 分支。测试 27/27，全项目 548/548。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `e0c1f1d` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 57: Brainstorm + ST1: extended_image migration risk gate

**Date**: 2026-05-22
**Task**: Brainstorm + ST1: extended_image migration risk gate
**Branch**: `main`

### Summary

Open brainstorm for migrating fullscreen preview to extended_image (PRD with Decision ADR-lite reversing ADR-0001 + 3 research files + 4 child subtasks scaffolding + 10 curated jsonl). Land ST1 risk gate: introduce extended_image ^10.0.1 dep (lock graph clean), build hermetic PoC widget at lib/_poc/extended_image_poc.dart wiring the production three-piece kit (ExtendedImageSlidePage + ExtendedImageGesturePageView.builder + ExtendedImage.memory(mode: gesture, inPageView: true)), kDebugMode-guarded entry in Home AppBar with TODO(ST4) markers. 3/3 red flags (#736 / #761 / desktop mouse drag) PASS on manual smoke. Codify new convention 'PoC gate for risky third-party packages' in dependencies-and-platforms.md. ST2/ST3/ST4 unblocked for Approach A.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `9374687` | (see git log) |
| `93798d8` | (see git log) |
| `7a644a8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 58: ST2: migrate PreviewFullScreenDialog to extended_image

**Date**: 2026-05-23
**Task**: ST2: migrate PreviewFullScreenDialog to extended_image
**Branch**: `main`

### Summary

Rewrite preview_full_screen_dialog.dart from 884 lines (self-rolled InteractiveViewer + PageView + _ImmersivePageScrollPhysics + manual drag-to-dismiss) to 429 lines using the extended_image three-piece kit (ExtendedImageSlidePage + ExtendedImageGesturePageView.builder + ExtendedImage.memory(mode: gesture, inPageView: true, enableSlideOutPage: true)). Deletes 24 self-rolled symbols (R3); preserves _ImmersiveScrollBehavior / _FloatingCloseButton / chrome auto-hide / constants byte-for-byte (R4). Spring-back curve degrades from easeOutCubic to ext's linear (accepted in brainstorm R3-exception). Dialog.fullscreen(transparent) wrapper kept so existing showDialog caller still works pre-ST3. flutter analyze 0 issues; dart format 0 changed; non-dialog tests 470/470 PASS; preview_full_screen_dialog_test.dart 9 PASS / 18 FAIL (expected — ST4 will rewrite per failing-tests.md A-E categorization). Codified the three-piece gallery pattern + 2 critical Gotcha (enableSlideOutPage / inPageView: true) + 2 sub-Pattern (Dialog.fullscreen dual-wrapper for showDialog compat / caller-owned AnimationController for double-tap zoom) in component-guidelines.md. ST3 (thumbnail) unblocked.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `c132988` | (see git log) |
| `5b73b89` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 59: Post-ST2 reverse decision + ST3 (PreviewThumbnail migration)

**Date**: 2026-05-23
**Task**: Post-ST2 reverse decision + ST3 (PreviewThumbnail migration)
**Branch**: `main`

### Summary

Two parts: (1) Record post-ST2 reverse decision in parent brainstorm PRD — keep PreviewThumbnail._openFullScreen on showDialog<void>(Dialog.fullscreen(transparent)) instead of migrating to Navigator.push(PageRouteBuilder(opaque: false)) because manual smoke after ST2 found showDialog's open/close transition smoother. Added 'Post-ST2 Revision (2026-05-23)' H2 to parent PRD with reverse decision + 'Why showDialog won' table + lessons; rewrote R6; struck through original ST2/ST3 plan lines; synced 4 jsonl files (ST3/ST4 implement+check) so ST4 ADR-0002 lands the reverse decision as a Consequences sub-bullet. (2) ST3 surgical migration of preview_thumbnail.dart leaf widget: Image.memory → ExtendedImage.memory(mode: ExtendedImageMode.none, fit: BoxFit.contain, gaplessPlayback: true). 86 → 90 lines (+4 net). Outer Semantics > InkWell > ClipRRect > ColoredBox chain byte-identical; _openFullScreen body byte-identical (still showDialog per the revision). flutter analyze 0 / dart format 0 / non-dialog tests 479/479 PASS / preview_full_screen_dialog_test.dart 9 PASS / 18 FAIL (same ST2 baseline). PoC + Home debug entry preserved for ST4 cleanup. Parent brainstorm now 3/4 done; ST4 (rewrite-tests-and-adrs) unblocked.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `fce2038` | (see git log) |
| `5eb9523` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
