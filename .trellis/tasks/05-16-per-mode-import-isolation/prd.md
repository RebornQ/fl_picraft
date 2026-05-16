# Per-Mode Image Import Session Isolation

> Parent: [`05-16-editor-layout-and-import-isolation`](../05-16-editor-layout-and-import-isolation/prd.md)

## Goal

把图片导入会话从「全局共享」改造为「按顶级编辑模式（stitch / grid / 未来 …）一份独立 session」，让长图拼接和宫格切图各自维护一份导入列表、warnings、AsyncError 流，互不串扰。

继承父任务 D4 / D5 决策：用 `AsyncNotifier.family<ImageImportSessionKind>` 模式实现；stitch 内部的 movie-subtitle flag 共享 stitch session。

## What I already know

### 当前 import 流（必须改造）

- `imageImportControllerProvider` 是全局 `AsyncNotifierProvider`（`lib/features/image_import/presentation/providers/image_import_provider.dart:165-168`）。
- `importedImagesProvider` 是它的 `valueOrNull` 派生（同文件 173-175）。
- 两个编辑器 controller 都在 `build()` 里 `ref.listen(importedImagesProvider, ...)`：
  - `stitch_editor_provider.dart:31-37` — 直接同步整个 list 到 stitch 内部 state。
  - `grid_editor_provider.dart:32-39` — 取第一张作为 source。
- 编辑器的 add/remove/reorder/clear 全部委托给全局 controller（stitch_editor_provider.dart:96-128，grid_editor_provider.dart:198-213）。
- `ImageDropZone` 在 `onPerformDrop` 写入全局 controller（`image_drop_zone.dart:65`）。
- 错误 SnackBar 监听挂在 stitch_editor_screen.dart:66 和 grid_editor_screen.dart:61，都监听同一个全局 controller 的 `AsyncError`。

### Nine-grid-social 中心图（**保持现状**）

- `grid_editor_provider.dart:163-178` 已经特例化：`pickCenterImage` 直接 `ref.read(imageImportRepositoryProvider).pickFromGallery(limit: 1)`，**不经过** import controller。
- 这个语义符合「中心图属于 grid mode 的子配置，不污染 grid 的图片 session」。
- 本任务保持这段逻辑不变。

### Export 流

- `currentExportSourceKindProvider` (`lib/features/export/presentation/providers/export_dispatch.dart`) 是 `ExportSourceKind { stitch, grid }` 类型的 `StateProvider`。
- 它和本任务要新增的 `ImageImportSessionKind` 值集相同，但语义不同（一个是「我从哪个编辑器来导出」，一个是「这张图属于哪个编辑器的 session」）。
- export 流走到 `ExportScreen` 时，按照 source kind dispatch 到对应的 editor controller 取图（不直接读 import provider）。本任务**不修改** export dispatch 入口，仅确保 editor controller 拿到正确的 family instance。

### 测试现状

- `test/features/image_import/presentation/image_import_controller_test.dart` — 大量 `imageImportControllerProvider.notifier` / `imageImportControllerProvider.future` 调用，签名要全部加 family 参数。
- `test/features/long_stitch/presentation/stitch_controls_sheet_test.dart` — 用 `importedImagesProvider.overrideWith(...)`，要改为 `importedImagesProvider(.stitch).overrideWith(...)`。
- `test/features/long_stitch/presentation/stitch_editor_responsive_test.dart` — 类似改造。
- Grid editor 的对应测试同样改。

## Requirements

- **R2.1** 新增枚举 `ImageImportSessionKind { stitch, grid }`，放在 `lib/features/image_import/domain/entities/image_import_session_kind.dart`。
- **R2.2** 把 `imageImportControllerProvider` 改造为 `AsyncNotifierProviderFamily<ImageImportController, List<ImportedImage>, ImageImportSessionKind>`。Controller 内部逻辑不变（pickFromGallery / addFromDrop / reorder / removeAt / clear / append capped）。
- **R2.3** `importedImagesProvider` 同步改为 `.family`，保留为「派生 valueOrNull」的便捷方式。
- **R2.4** `ImageDropZone` 接受新的必填参数 `final ImageImportSessionKind sessionKind`，把 drop 转发到对应 family instance。
- **R2.5** `StitchEditorController.build()` watch `imageImportControllerProvider(.stitch)`，所有 add/remove/reorder/clear 调用都加 `.stitch` 参数。
- **R2.6** `GridEditorController.build()` watch `imageImportControllerProvider(.grid)`，同样加 `.grid`。
- **R2.7** Stitch / Grid screen 的错误 SnackBar 监听各自监听 `imageImportControllerProvider(.stitch)` / `(.grid)`。
- **R2.8** Nine-grid-social `pickCenterImage` 逻辑保持不变（继续绕过 import controller）。
- **R2.9** Export dispatch 流不破坏 — `ExportSourceKind` 与 `ImageImportSessionKind` 保持独立类型（即便值集相同），通过显式 mapping 函数桥接。
- **R2.10** Spec `.trellis/spec/frontend/state-management.md` 新增「按模式隔离 session 的 .family 范式」段落（含 Why / How to apply）。
- **R2.11** 所有相关测试更新签名，新增至少 2 个「跨模式隔离」widget 测试。

## Acceptance Criteria

- [ ] AC2.1 在 stitch 模式导入 3 张图片，切换到 grid 模式（tab）→ grid 看到 0 张（不会同步）。
- [ ] AC2.2 反向：grid 导入图片，切到 stitch → stitch 看到 0 张。
- [ ] AC2.3 在 stitch 触发一次 `pickFromGallery` 失败（mock repo throws）→ stitch screen 弹 SnackBar；切到 grid → grid screen 不弹（错误不会窜）。
- [ ] AC2.4 `StatefulShellRoute` 状态保留语义不破坏：stitch 导入 → 切到 grid → 再切回 stitch → 仍然能看到原来 3 张图片。
- [ ] AC2.5 Nine-grid-social 中心图通路完全不变（widget test 覆盖）。
- [ ] AC2.6 Export 流在 stitch / grid 两种 source 下都拿到对应模式的图片完成导出（widget test 覆盖）。
- [ ] AC2.7 `flutter analyze` 干净，所有现有测试通过。
- [ ] AC2.8 新增 ≥2 个「跨模式隔离」widget 测试 + ≥3 个 controller family 单元测试。
- [ ] AC2.9 `.trellis/spec/frontend/state-management.md` 新增 .family 范式说明。

## Definition of Done

- 所有 AC 勾选完成。
- spec 文档 `state-management.md` 含 Why（为什么不共享全局 session） + How to apply（family + ImageDropZone 参数化 + 测试 override 模式） + Trade-offs（family key 命名稳定性 / 内存开销）。
- ImageDropZone 的 API 改动在 `.trellis/spec/frontend/component-guidelines.md` 中提及（如有 widget API 约定）。

## Technical Approach

### 改造步骤

1. **新增枚举**：`lib/features/image_import/domain/entities/image_import_session_kind.dart`。
2. **改 provider**：把 `imageImportControllerProvider` 改为 family；`importedImagesProvider` 同步。
3. **改 ImageDropZone**：加 `sessionKind` 必填参数，转发到 family instance。
4. **改 stitch_editor_screen / grid_editor_screen**：传 `sessionKind` 给 `ImageDropZone`，监听 family instance。
5. **改两个 editor controller**：所有读写都带 `.stitch` / `.grid` 参数。
6. **改测试**：全部 override 改成 family 形式；新增隔离行为测试。
7. **改 spec**：在 `state-management.md` 加 family 范式段落。
8. **回归**：跑全套 `flutter test`、`flutter analyze`、`dart format .`。

### Mapping `ExportSourceKind` ↔ `ImageImportSessionKind`

值集相同但类型独立，定义一个 `ImageImportSessionKind sessionKindFor(ExportSourceKind)` 顶层函数即可（不引入耦合）。

### 风险点

- **family key 稳定性**：枚举值名字成为 provider 缓存 key 的一部分，重命名会断 widget tests 的 override。约定枚举值名要稳定，加新值时不动旧值。
- **测试改造面广**：~20 处 override / read 调用要批量修改 — 用 `grep -n imageImportControllerProvider` 全文找一次列清单。
- **ImageDropZone 必填参数**：会让任何不传 `sessionKind` 的调用方编译失败 — 这是好事，强制 caller 显式决定归属。

## Decision (ADR-lite)

> 继承父任务 D4 / D5 决策，本任务仅落地实施。补充：

- **ADR-lite extra**: 新增独立枚举 `ImageImportSessionKind`，**不复用** `ExportSourceKind`。
  - **Reason**: 关注点分离 — 一个是「导入归属」，一个是「导出来源」。即使当前值集相同，未来 export 可能有「PDF 合并」等不附带 import session 的 source，那时强行复用就会产生「ExportSourceKind 有的值在 ImageImport 里没有 family instance」的尴尬。

## Out of Scope

- 编辑器 layout 铺满（sibling subtask `05-16-editor-fill-container-width`）。
- 持久化 import session（重启不保留 — 维持现状）。
- 引入新的编辑模式（拼贴 / 社交模板）— 仅在枚举里留扩展位。
- 任何 import 数据源（gallery / camera / clipboard / drag-drop）的实现变更。

## Technical Notes

### 关键文件

- `lib/features/image_import/domain/entities/image_import_session_kind.dart`（新建）
- `lib/features/image_import/presentation/providers/image_import_provider.dart`
- `lib/features/image_import/presentation/widgets/image_drop_zone.dart`
- `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
- `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
- `lib/features/grid/presentation/providers/grid_editor_provider.dart`
- `lib/features/grid/presentation/screens/grid_editor_screen.dart`
- `lib/features/export/presentation/providers/export_dispatch.dart`（仅检查是否需要 mapping helper）
- `test/features/image_import/...`（全套）
- `test/features/long_stitch/...`（涉及 import override 的全套）
- `test/features/grid/...`（同上）
- `.trellis/spec/frontend/state-management.md`

### 现有 spec 依赖

- `.trellis/spec/frontend/state-management.md` — 本任务核心 spec 改动。
- `.trellis/spec/frontend/type-safety.md` — enum 设计约定。
- `.trellis/spec/frontend/component-guidelines.md` — widget API 设计（ImageDropZone 新增参数）。
- `.trellis/spec/frontend/error-handling.md` — partial / TooManyImages 在 family 下的语义保持不变。

