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
