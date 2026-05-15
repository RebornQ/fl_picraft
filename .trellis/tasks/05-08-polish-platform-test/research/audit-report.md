# Polish & Multi-Platform Test — Round 1 Audit Report

## Scope

Round 1 = 现状盘点 + Quick Wins。后续轮次（响应式、暗色、a11y、性能 benchmark、平台手动测试）不在本轮范围。

## Baseline 命令输出（修改前）

```text
$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.8s)

$ flutter test
All tests passed!   # 219 tests
```

## Feature inventory（实际目录结构）

| Feature | Layers present | Notes |
|---------|----------------|-------|
| `home` | `presentation/{screens,widgets}` | 入口页 + 推广卡片 + Tips banner + 最近作品 placeholder |
| `image_import` | `data/{datasources,repositories,utils}` + `domain/{entities,repositories}` + `presentation/{providers,widgets}` | 已落地的 import 体系（gallery / camera / clipboard / drag-drop） |
| `long_stitch` | `data/renderers` + `domain/{entities,usecases}` + `presentation/{providers,screens,widgets}` | 长图拼接 + 电影台词模式 |
| `grid` | `data/renderers` + `domain/{entities,usecases}` + `presentation/{providers,screens,widgets}` | 普通宫格 + 九宫格朋友圈 |
| `export` | `data/{datasources,repositories}` + `domain/{entities,repositories,usecases}` + `presentation/{providers,screens,widgets}` | 水印 + 格式 + 导出 (gallery / file dialog / web blob) |
| `settings` | `presentation/screens` | 当前是 `PlaceholderBody`（PRD §Out of Scope 允许） |

## Linting / Spec violation 概览

### 完全干净的检查项
- `flutter analyze` 0 issues
- 全部 219 测试通过
- 零 `TODO` / `FIXME` / `XXX` / `HACK` 注释
- 零 `// ignore:` 绕过
- 零 `dynamic` 变量声明
- 零 `print(` 调用
- 零 `.withOpacity(` 调用（已统一迁移到 `withValues(alpha: ...)`）
- 数据源插件 imports 完全限制在 `data/datasources/` 内（domain / repository / presentation 干净）
- 三层防御已落地（gallery saver / file dialog / web blob / camera 都遵守 isSupported + 抛 UnsupportedError）
- domain layer 100% framework-free
- Reorderable 列表使用 `ObjectKey` / `ValueKey(stable id)`，无 position-based key
- Loading / empty state 在大多数 async surface 已存在

## Quick win / Medium / Hard 分类

### Quick Wins（本轮要改完）

| # | 位置 | 问题 | 修法 |
|---|------|------|------|
| 1 | `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` `_onExportPressed` | 残留的 stub：snackbar 写着 "导出对话框待 05-08-export-watermark 接入"，绕过了已经实现的 export 屏 | 改成 `context.go('/export')`；删除 stub 方法 |
| 2 | `lib/features/home/presentation/screens/home_screen.dart` line 63 & 124 | 两处 `onPressed: () {}` 空回调（通知按钮、"查看全部"链接），点击没任何反馈 | 改成 `onPressed: null` 让 Material 自动 dim 灰；保留视觉但表达 disabled 语义 |
| 3 | `lib/features/export/presentation/widgets/save_action_button.dart` line 95–97 | `kDebugMode + debugPrint`：错误已通过 snackbar 给用户，再 debugPrint 一遍是冗余 | 删除 debugPrint，错误信息保留在 snackbar |
| 4 | `lib/features/long_stitch/domain/usecases/stitch_render_request.dart` line 41–42 | 注释说 "The export module (`05-08-export-watermark`) will swap [format] / [jpegQuality] in when it lands" — export 已经实装且并不使用此 factory 注入 format/quality | 改写注释，反映实际行为：内部 render 始终 PNG 工作格式，最终格式由 `encodeForExport` 在 export pipeline 决定 |
| 5 | `lib/features/export/presentation/providers/export_controller.dart` line 25 / 53 / 68 | 注释多次说 "grid editor's hook-in will land with `05-08-grid-split`"，但 grid 已经在 grid_editor_screen 自己驱动 export pipeline；`exportControllerProvider` 实际只服务 stitch | 改写注释，反映 export screen 当前 stitch-only，grid 走自己的 FAB 路径 |
| 6 | `lib/features/export/presentation/screens/export_screen.dart` line 13–16 | 同上，doc 注释说 "until then, navigating here from the grid editor surfaces a 'No images to export' error toast" — 描述过期 | 改写为简短准确的 doc |

### Medium（Round 2 之后）

- 单元 / 组件 widget 抽取重复 UI（如 long stitch + grid 都有 source warning row），目前不是显著痛点
- `home_screen.dart` build 方法较长（150 行），可拆 helper widgets
- `_onExportPressed` 在 grid_editor_screen 中和 export_controller 重复了 export pipeline 逻辑（一处通过 controller，一处直接 repository），统一前需要先决定 grid 是否走 export 屏；这是产品/UX 决策，不属于 polish 范畴

### Hard（明确 Round 2 / 3）

- 响应式布局（phone / tablet / desktop LayoutBuilder） — Round 2
- 暗色模式 visual QA（dark scheme 是 seed 生成的，需要走一遍每个屏幕） — Round 2
- 无障碍：补全 Semantics label，验证 TalkBack / VoiceOver — Round 2
- 性能 benchmark：20 张图 < 5s、内存 < 500MB、冷启 < 2s（PRD §7） — Round 3
- 平台手动测试矩阵（iOS / Android / macOS / Win / Linux / Web） — 最后阶段，用户参与

## 本轮修改清单

1. `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
   - 删除 `_onExportPressed` stub（先生成长图再 snackbar），改为直接 `context.go('/export')`
   - 简化 imports：去掉不再需要的 `flutter_riverpod` 相关使用、`dart:typed_data` 间接依赖
2. `lib/features/home/presentation/screens/home_screen.dart`
   - 两处 `onPressed: () {}` → `onPressed: null`，附加 tooltip 说明
3. `lib/features/export/presentation/widgets/save_action_button.dart`
   - 删除 `kDebugMode` debugPrint 分支；同时移除 `package:flutter/foundation.dart` import 若不再需要
4. `lib/features/long_stitch/domain/usecases/stitch_render_request.dart`
   - 重写 `fromState` doc 注释为现状描述
5. `lib/features/export/presentation/providers/export_controller.dart`
   - 重写 class doc + save() doc 中关于 grid hook-in 的过期描述
6. `lib/features/export/presentation/screens/export_screen.dart`
   - 重写 class doc 注释

## 验证（修改后）

```text
$ dart format lib/ test/
Formatted 105 files (0 changed) in 0.16 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.5s)

$ flutter test
All tests passed!   # 219 tests still pass
```

## 后续轮次建议

### Round 2（UX 深度 polish）

- 响应式：所有 ListView / Stack 在 tablet / desktop 上的列数 / max-width
- 暗色模式：seed-generated dark scheme 走查所有屏幕，重点检查 `TipsBanner`、`_SourceSizeWarning`、disabled state
- a11y：
  - 给所有 IconButton 补 tooltip
  - 给所有 GestureDetector 子节点补 Semantics(label:)
  - 验证 48×48 触控目标
- 文案细节：错误 snackbar 文案审计（避免 raw exception string），统一"已取消" / "已保存" / "失败"
- ~~统一 stitch 和 grid 的导出入口（产品决策需先确认）~~ → **Round 2a 已完成**

### Round 3（性能）

- 添加 benchmark harness（headless test 测 20 张拼接耗时）
- 添加内存追踪（DevTools / dart:developer Timeline events 标记 import → render → encode 三段）
- 优化点候选：
  - `stitch_image_renderer` 解码 + 缩放可以并行
  - `grid_image_renderer` 每个 cell 单独 encode，可并行
  - 大图缓存（避免每次 setState 重新解码）

### 最终阶段（平台手动测试）

- 准备测试清单（per platform 走一遍 import / stitch / grid / export）
- iOS 真机权限弹窗（Photos add-only / camera）
- Android API 23 / 30 / 34 三档兼容
- macOS / Win / Linux 文件保存对话框 + drag-drop
- Web Chrome / Edge / Safari blob 下载 + clipboard read 权限

---

## Round 2a — 导出路径统一

### 用户决策

笨蛋（用户）选了选项 A：**grid 编辑器导出统一走 `/export` 屏**。需要重构 ExportController 让它根据当前源（stitch / grid）dispatch 到不同渲染管线。

### 设计要点

| 决策 | 选择 | 理由 |
|------|------|------|
| 源类型的表达 | `enum ExportSourceKind { stitch, grid }` | 简单二选一，没有需要承载数据的变体，enum 比 sealed class 更轻量 |
| 路由传参方式 | Riverpod `StateProvider<ExportSourceKind>` | spec `state-management.md` 推荐：跨屏共享状态走 Riverpod；GoRouter `extra` 在 web 刷新时丢失，不适合此场景 |
| 谁来 set kind | 调用方（editor screen）在 `context.go('/export')` 之前 set | 让导航行为成为一组原子操作，export 屏不需要知道导航来源 |
| dispatch 位置 | `ExportController.save()` 内部，通过 `_buildSource()` 私有方法封装 | 类型系统的 exhaustive switch 保证两个分支都被处理；新增 kind 时编译失败显式提示需要扩展 |
| 进度反馈粒度 | 复用现有 `SaveResult.SaveSuccess.count` 字段，不引入实时进度回调 | grid 的"细粒度"含义实测是"结果 snackbar 显示 N/M"，不是实时进度条；现有 repository 已经聚合 partial-save count |
| 数据流耦合 | export controller 调 stitch/grid controller 的 `render` / `renderCells` 方法（已有跨 feature 模式） | `code-reuse-thinking-guide.md` 的 "side-channel via repository" 在 grid 没有独立 repository 时不适用；通过 controller 是已有 stitch 模式的延续 |
| save button label | 新增 `exportSaveButtonLabelProvider`，grid 模式自动带入 cell count | 用户在 tap "保存" 之前看到"保存 9 张到相册"，避免点完才发现要保存 9 个文件 |

### 关键文件改动

#### NEW

| 文件 | 内容 |
|------|------|
| `lib/features/export/presentation/providers/export_dispatch.dart` | `ExportSourceKind` 枚举 + 三个 provider：`currentExportSourceKindProvider`（路由状态）、`canExportProvider`（按钮 enabled 状态）、`exportSaveButtonLabelProvider`（按钮 idle 文案带 cell count） |
| `test/features/export/presentation/export_controller_test.dart` | 9 个测试覆盖：dispatch 路径（stitch / grid）、空编辑器返回 `SaveFailure`、`isSaving` 翻转、`canExportProvider` 行为、grid label 含 cell count |

#### MODIFIED

| 文件 | 关键变更 |
|------|---------|
| `lib/features/export/presentation/providers/export_controller.dart` | `save()` 改为读 `currentExportSourceKindProvider` 后 dispatch；新增私有 `_buildSource()` 返回 `ExportSource?`（null 表示编辑器无内容）；doc 注释更新 dispatch 契约 |
| `lib/features/export/presentation/widgets/save_action_button.dart` | 改为 watch `exportControllerProvider.select(isSaving)` + `canExportProvider` + `exportSaveButtonLabelProvider`；按钮 disabled 现在覆盖"编辑器为空"场景；删除独立的 `_buttonLabel` 方法和 `gallery_saver_datasource.dart` 直接 import |
| `lib/features/grid/presentation/screens/grid_editor_screen.dart` | FAB 改为 `_onExportPressed()` → set kind=grid + `context.go('/export')`；删除原来的 inline `_onExportPressed`（直接调 repository）和 `_snackBarFor` 辅助方法；删除多个未用 import（`ExportFormat` / `ExportQuality` / `ExportRequest` / `ExportSource` / `SaveResult` / `exportControllerProvider` / `watermarkConfigProvider`） |
| `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` | 导出按钮的 `context.go('/export')` 之前先 set kind=stitch；与 grid 路径对称 |

### 数据流

```
[Stitch 编辑器]                   [Grid 编辑器]
       │                               │
       │ tap "导出"                    │ tap FAB "导出"
       │ set kind=stitch              │ set kind=grid
       │ context.go('/export')        │ context.go('/export')
       └───────────────┬───────────────┘
                       │
                       ▼
              [/export 屏 (统一)]
              ├── FormatQualityCard (作用对象由 source 决定)
              ├── WatermarkCard      (同上)
              └── SaveActionButton
                       │ tap 保存
                       ▼
              ExportController.save()
              ├── read currentExportSourceKindProvider
              ├── _buildSource():
              │   ├── stitch → stitchEditorController.render() → StitchExportSource
              │   └── grid   → gridEditorController.renderCells() → GridExportSource
              ├── build ExportRequest(source, format, quality, watermark)
              └── exportRepository.exportAndSave(request)
                  ├── StitchExportSource → _exportSingle (一次性 persist)
                  └── GridExportSource   → _exportGrid   (cell-loop + partial-save accounting)
                       │
                       ▼
              SaveResult → snackbar
              ├── SaveSuccess(count > 1) → "已保存 N 张到 …"
              ├── SaveSuccess(count = 1) → "已保存到 …"
              ├── SaveCancelled         → 静默
              └── SaveFailure(message)  → 错误 snackbar
```

### 验证（Round 2a 修改后）

```text
$ dart format lib/ test/
Formatted 107 files (1 changed) in 0.15 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.4s)

$ flutter test
All tests passed!   # 228 / 228（Round 1 后 219 + 本轮新增 9）
```

新增覆盖：
- `ExportController dispatch routes through StitchExportSource when kind=stitch`
- `ExportController dispatch routes through GridExportSource when kind=grid`
- `ExportController dispatch stitch kind + empty editor returns SaveFailure`
- `ExportController dispatch grid kind + empty editor returns SaveFailure`
- `ExportController dispatch isSaving flag flips during the save round-trip`
- `canExportProvider false when both editors are empty`
- `canExportProvider true for stitch kind when stitch editor has images`
- `canExportProvider true for grid kind when grid editor has a source`
- `exportSaveButtonLabelProvider stitch kind label has no cell count; grid kind includes count`

### 不再做的事（Round 2a 范围之外，按 prompt 要求保留给后续轮次）

- 响应式 / 暗色 / a11y（Round 2b）
- 性能 benchmark（Round 3）
- 平台手动测试（最终阶段）
- 实时 cell 进度回调：现状是结果 snackbar 表达 N/M，未来如果产品要"保存 3/9 中…"实时进度条，需要：(1) repository 暴露 `onProgress(int saved, int total)` 回调；(2) ExportState 增加 `currentCell` / `totalCells` 字段；(3) save button 渲染 progress text。本轮没做以保持范围 surgical。

---

## Round 2b — UX polish 接力

Round 2b 完整范围分两次执行（中间 OOC 中断，留下 part1 / part2 两段日志）。

### Round 2b-part1（前置工作，已完成）

- **默认导出格式 PNG**：`ExportState.initial()` 改为 `format: ExportFormat.png, quality: kMaxExportQuality`；`format_quality_card_test.dart` 同步显式 `setFormat(ExportFormat.jpg)`。理由：PRD §5.4 默认无损；与桌面/Web 下载体验更一致。
- **错误文案 helper 落地**：新增 `lib/core/errors/user_facing_messages.dart`，提供 `describeCause` / `exportFailureMessage` / `saveFailureMessage` / `partialSaveFailureMessage` / `importFailureMessage`。Helper 本身**未被 callsite 引用**，留给 part2 替换。

### Round 2b-part2（本轮）

本轮目标：使用 part1 留下的 helper 替换所有"raw exception 拼接英文 snackbar"的 callsite + 让 `/export` 屏不再误导用户。

#### 1) 错误文案 callsite 替换

**搜索基线**：`grep -rn "SaveFailure(" lib/ --include='*.dart'` 命中 14 处 SaveFailure 构造点 + `'$e'` / `failed` 互文。逐个评估：

| 文件 | 行 | Before | After | Helper |
|------|-----|--------|-------|--------|
| `lib/features/export/data/datasources/file_dialog_save_datasource.dart` | 56 | `'Save failed: $e'` | `saveFailureMessage(e)` → "保存失败：…" | save |
| `lib/features/export/data/datasources/gallery_saver_datasource.dart` | 62 | `'Photos permission denied'` | `'相册权限被拒绝，请在系统设置中开启后重试'` | (const, 直接中文) |
| `lib/features/export/data/datasources/gallery_saver_datasource.dart` | 72 | `'Photos save failed: ${e.type.message}'` | `saveFailureMessage(e.type.message)` | save |
| `lib/features/export/data/datasources/gallery_saver_datasource.dart` | 74 | `'Photos save failed: $e'` | `saveFailureMessage(e)` | save |
| `lib/features/export/data/datasources/web_blob_download_datasource.dart` | 43 | `'Download failed: $e'` | `saveFailureMessage(e)` | save |
| `lib/features/export/data/repositories/export_repository_impl.dart` | 71 | `'Export failed: $e'` | `exportFailureMessage(e)` → "导出失败：…" | export |
| `lib/features/export/data/repositories/export_repository_impl.dart` | 85 | `'Nothing to export'` | `'没有可导出的内容'` | (const, 直接中文) |
| `lib/features/export/data/repositories/export_repository_impl.dart` | 111-113 | `'Saved $saved of ${cells.length} before failure: $message'` | `partialSaveFailureMessage(saved:, total:, cause: message)` → "已保存 N / M 张后失败：…" | partial |
| `lib/features/export/data/repositories/export_repository_impl.dart` | 117-120 | `'Export failed at cell $i: $e'` / `'Saved $saved of ... at cell $i: $e'` | 分支：saved==0 → `exportFailureMessage(e)`；saved>0 → `partialSaveFailureMessage` | export / partial |
| `lib/features/export/data/repositories/export_repository_impl.dart` | 168-171 | `'No save target available on platform …'` | `'当前平台暂不支持保存图片（…）'` | (直接中文，保留 platform 调试信息) |
| `lib/features/export/presentation/providers/export_controller.dart` | 73 | `'A save is already in progress'` | `'正在保存中，请稍候'` | (const, 直接中文) |
| `lib/features/export/presentation/providers/export_controller.dart` | 80 | `'No images to export'` | `'没有可导出的图片'` | (const, 直接中文) |
| `lib/features/export/presentation/providers/export_controller.dart` | 90 | `'Export failed: $e'` | `exportFailureMessage(e)` | export |

**未替换**：
- `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart:64`、`grid_image_renderer.dart:74` — 这两处是开发者向的 `StateError` 消息（不会变成 snackbar），保持英文。
- `gallery_saver_datasource.dart` 的 `UnsupportedError`、`file_dialog_save_datasource.dart` 的 `UnsupportedError`、`web_blob_download_datasource.dart` 的 `UnsupportedError` —— 这些是 last-line defense，只有未正确通过 isSupported 守门时才会触发（开发期 bug catcher），保持英文以便堆栈一目了然。
- import 失败路径（`image_import_provider.dart` 的 `AsyncError`）—— 当前 UI 没有任何 widget 把 `AsyncError` 渲染成 snackbar，import 失败在 UI 上是静默的（UX gap 但不在本轮范围内）。`importFailureMessage` helper 仍然保留供未来接入。

#### 2) `/export` 屏隐藏 bottom nav

**实际情况**：Round 2a 已经完成此改动 —— `lib/features/export/presentation/screens/export_screen.dart` 已经使用裸 `Scaffold`（非 `AppScaffold`），所以 `/export` 屏根本就没有渲染 bottom nav。dispatch prompt 描述的"高亮作品库"问题在工作树里已经消失（git status 显示该文件 modified 未提交）。

本轮无需任何代码改动来满足任务 #2 — 但为确认结论：

```bash
grep -rn "AppScaffold\|bottomNavigationBar:" lib/features --include='*.dart'
# home_screen / settings_screen / stitch_editor / grid_editor → AppScaffold
# export_screen.dart → 不在结果里（裸 Scaffold）
```

仅 4 个顶级目的地（作品库 / 长图拼接 / 宫格切图 / 设置）走 `AppScaffold`，与 `bottom_nav_bar.dart::destinations` 4 个 entry 一一对应。`/export` 是 transient destination（从 editor 跳来的"模态"流程），保留裸 `Scaffold` 是 ExportScreen 现有 doc 注释（`"Why a bare Scaffold (no AppScaffold)..."`)记录的设计意图。

#### 修改清单

**lib/**

1. `lib/core/errors/user_facing_messages.dart` — 修复 part1 留下的 `curly_braces_in_flow_control_structures` lint（pre-existing 1 issue）。
2. `lib/features/export/data/datasources/file_dialog_save_datasource.dart` — import helper；`'Save failed: $e'` → `saveFailureMessage(e)`。
3. `lib/features/export/data/datasources/gallery_saver_datasource.dart` — import helper；权限/异常 3 处替换。
4. `lib/features/export/data/datasources/web_blob_download_datasource.dart` — import helper；下载失败替换。
5. `lib/features/export/data/repositories/export_repository_impl.dart` — import helper；single pipeline / grid pipeline / 平台兜底 5 处替换。
6. `lib/features/export/presentation/providers/export_controller.dart` — import helper；3 处状态/异常替换 + 1 处 doc 注释更新（"No images to export" → "没有可导出的图片"）。

**test/**

7. `test/features/export/presentation/export_controller_test.dart` — 2 处英文字符串测试 → 中文（"没有可导出的图片"）。
8. `test/features/export/data/export_repository_impl_test.dart` — `'Nothing to export'` → `'没有可导出'`；`'Saved 1 of 3'` → `'已保存 1 / 3'`；`isNot(contains('Saved'))` → `isNot(contains('已保存'))`。注入的 `'Permission denied'` 字面量保持英文（测试在测"first-cell failure 原样冒泡"，跟新文案 helper 无关）。

#### 验证

```text
$ dart format lib/ test/
Formatted 108 files (0 changed) in 0.15 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.2s)

$ flutter test --reporter expanded
…
00:05 +228: All tests passed!   # 228 / 228 全绿，0 新增 0 减少
```

#### 设计要点 / 不变量

- `partialSaveFailureMessage` 的 `cause` 类型是 `Object?`，传 `String message` 直接走 `toString()` 等价路径；传 `Exception e` 走 `describeCause` 的 `Exception: ` 前缀剥离。两种 callsite 共享同一个 helper 不需额外重载。
- `describeCause` 内部 120 字符截断后追加省略号 `…`，保证 snackbar 在窄屏不被超长堆栈撑爆。
- 测试套件保留对 `'Permission denied'` 字面量的 `equals` 断言：该测试目的是验证 "saved==0 时 SaveFailure 原样冒泡"，与 helper 文案无关；helper 仅介入 saved>0 的 partial 路径。

#### 本轮明确不做（Round 2c / Round 3 范围）

- 响应式布局（phone / tablet / desktop LayoutBuilder）
- 暗色模式 visual QA
- a11y / tooltip / Semantics label 补齐
- 性能 benchmark（20 张图 < 5s、内存 < 500MB、冷启 < 2s）
- 平台手动测试矩阵
- import 失败 snackbar 接入（独立的 UX gap，需要先决定在哪个 widget 上 listen `AsyncError`）

#### 风险 / 疑问

- 无功能风险：所有改动是字符串级别的同义替换 + 一处分支重构（grid loop 的 catch 块），逻辑等价。228 / 228 测试全绿可证。
- 一个潜在 UX 改进留给后续：`gallery_saver_datasource.dart` 的 `GalException.type.message` 仍然可能是英文（gal 插件内部翻译矩阵），用户看到的会是 "保存失败：access denied" 这种中英混合 — 完整体的中文化需要在 helper 里加 GalException-specific 翻译表，本轮未做以保持范围 surgical。

---

## Round 2c — 响应式接力

Round 2c 完整范围分两次执行（中间 503 中断）。Part1 落地了响应式基础设施 + home / export 两个屏，Part2 把同样的模式推给两个 editor 屏。

### Round 2c-part1（基础设施 + home / export 响应式）

#### 1) 响应式基础设施

新增 `lib/core/constants/breakpoints.dart`：
- `Breakpoints.compact = 600` / `medium = 840` / `expanded = 1200`（Material 3 Window Size Class 边界，单位 dp）
- `Breakpoints.maxContentWidth = 1200`（顶级屏幕的内容宽度上限，避免 27 寸显示器把卡片拉到全屏宽）
- `enum WindowSizeClass { compact, medium, expanded, large }`（exhaustive-switch 友好）
- `WindowSizeClass windowSizeClassOf(BuildContext)`（widget 路径）
- `WindowSizeClass windowSizeClassFromWidth(double)`（pure-Dart，测试用）

为什么用 enum 而不是 boolean (`isCompact`)：四个 bucket 都需要被显式区分（home 屏的 `recentWorksColumns` 需要 3 / 3 / 4 / 4 — boolean 表达不了），且 enum 的 exhaustive switch 让未来增加 `extraLarge` 时编译失败显式提示。

#### 2) home_screen 响应式

| size class | feature cards | recent works grid |
|------------|---------------|-------------------|
| compact (<600 dp) | 1 列叠放 | 3 列 |
| medium (600–840 dp) | 2 列并排 | 3 列 |
| expanded (840–1200 dp) | 2 列并排 | 4 列 |
| large (≥1200 dp) | 2 列并排，整屏 maxContentWidth=1200 dp 居中 | 4 列 |

实现要点：
- `recent_works_grid.dart` 增加 `crossAxisCount` prop，由父屏驱动
- `_FeatureCardsLayout` 内部 if (isCompact) Column else IntrinsicHeight(Row(...))
- 外层 Center + ConstrainedBox(maxWidth: 1200)

#### 3) export_screen 响应式

| size class | layout |
|------------|--------|
| compact | 单列：FormatQuality → Watermark → Save → Disclaimer |
| medium / expanded / large | FormatQuality + Watermark 并排两列；Save / Disclaimer 仍旧单列横跨 |

设计要点：
- 在 medium+ 用 `Row(crossAxisAlignment: start)` 把两个 SectionCard 并排，**不**包 IntrinsicHeight（外层是 SingleChildScrollView，viewport 拒绝 intrinsic-dimension query；两个卡片高度差不多，top-align 视觉可接受）
- Save 按钮和免责声明保留单列全宽（primary action 视觉锚点）

#### 4) Round 2c-part1 修改清单

**lib/**

| 文件 | 类型 | 内容 |
|------|------|------|
| `lib/core/constants/breakpoints.dart` | NEW | Breakpoints + WindowSizeClass + helpers |
| `lib/features/home/presentation/screens/home_screen.dart` | MODIFIED | 加 `windowSizeClassOf` 切换 + `_FeatureCardsLayout` 拆分 + `recentWorksColumns` 分支 + 外层 Center+ConstrainedBox |
| `lib/features/home/presentation/widgets/recent_works_grid.dart` | MODIFIED | 加 `crossAxisCount` prop |
| `lib/features/export/presentation/screens/export_screen.dart` | MODIFIED | 加 `windowSizeClassOf` 切换 + 双列 settings row + 外层 Center+ConstrainedBox |

**test/**

| 文件 | 测试数 | 说明 |
|------|--------|------|
| `test/core/constants/breakpoints_test.dart` | 9 | windowSizeClassFromWidth 边界测试 + maxContentWidth 常量测试 |
| `test/features/home/presentation/home_screen_responsive_test.dart` | 8 | 四个 size class 下的 feature cards 排布 + recent works 列数 + maxContentWidth cap |
| `test/features/export/presentation/export_screen_responsive_test.dart` | 5 | compact 单列 / medium 双列 / expanded 双列 / Save 全宽 / maxContentWidth cap |

**part1 验证**：
- `flutter analyze` clean
- `flutter test` 250 / 250 全绿（228 + 22）

### Round 2c-part2（本轮：editor 响应式）

#### 1) 设计模式：sheet → panel 抽取

两个 editor 屏在 phone-first 设计下都是 "画布 + 底部控件" 结构。要支持 tablet / desktop 的 "画布 + 右侧控件" 布局，需要把控件抽出可复用的 widget。

**stitch editor**：原有 `StitchControlsSheet` 已经是独立 widget（包含 mode 切换 / subtitle 开关 / 滑块 / 颜色 swatch + Material elevation 8 + 顶部圆角）。抽取方法：
- 新建 `StitchControlsPanel`：原 sheet 的 Column 内容 + Padding，**没有** Material 包装
- `StitchControlsSheet` 改为 `Material(elevation: 8, borderRadius: top16) → StitchControlsPanel`（向后兼容，现有 stitch_controls_sheet_test 仍然能 pump StitchControlsSheet）
- 现有 4 个 `StitchControlsSheet` 测试继续通过（panel 内部依然渲染同样的 Switch / Slider）

**grid editor**：原本控件没有独立 sheet 概念，直接在 ListView 里铺平：
- `_NineGridSocialRow`（私有）→ 提升为 `NineGridSocialRow`（public）
- 新建 `GridControlsPanel`：Column(NineGridSocialRow, GridTypeSelector, GridParameterCards)，**自带** 16dp 间距
- `_NineGridSocialRow` 私有类删除，`GridControlsPanel` 文件里直接定义 `NineGridSocialRow` 公共类

panel widget 不带外部 padding，调用方按 context 加 padding：
- compact / medium：`ListView(padding: fromLTRB(16,16,16,96))` 给整列加 padding
- expanded / large：`Padding(fromLTRB(16,16,16,24))` 包整个 Row

#### 2) 响应式行为表

**stitch editor**：

| size class | 布局 |
|---|---|
| compact (<600 dp) | `Column(StitchImageStrip, Expanded(SCV(StitchPreviewCanvas)), StitchControlsSheet)` — 底部 sheet |
| medium (600–840 dp) | 同 compact — 手机横屏不重构 |
| expanded (840–1200 dp) | `Column(StitchImageStrip, Expanded(Row(Expanded(SCV(canvas)), SizedBox(width: 380, SCV(StitchControlsPanel)))))` — 右侧 panel |
| large (≥1200 dp) | 同 expanded，外层 maxContentWidth=1200 + Center |

**grid editor**：

| size class | 布局 |
|---|---|
| compact (<600 dp) | `ListView([GridPreviewCanvas, optional warning, GridControlsPanel])` — 单列叠放 + 96dp 底 padding 留 FAB 余量 |
| medium (600–840 dp) | 同 compact — 手机横屏不重构 |
| expanded (840–1200 dp) | `Padding(Row(Expanded(SCV(canvas + warning)), SizedBox(width: 380, SCV(GridControlsPanel))))` — 双栏 |
| large (≥1200 dp) | 同 expanded，外层 maxContentWidth=1200 + Center |

#### 3) Round 2c-part2 修改清单

**lib/**

| 文件 | 类型 | 内容 |
|------|------|------|
| `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` | NEW | 抽自 `StitchControlsSheet` 的 Column 内容（含 _SliderRow + _ColorSwatch 私有类） |
| `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart` | MODIFIED | 简化为 `Material(...) → StitchControlsPanel`，从 269 行 → 28 行 |
| `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` | MODIFIED | 加 `windowSizeClassOf` switch + `_StitchEditorBody` 拆分 + 外层 Center+ConstrainedBox + 新常量 `_kStitchControlsPanelWidth = 380` |
| `lib/features/grid/presentation/widgets/grid_controls_panel.dart` | NEW | `GridControlsPanel`（Column 含三个子 widget）+ `NineGridSocialRow` 公共类 |
| `lib/features/grid/presentation/screens/grid_editor_screen.dart` | MODIFIED | 加 `windowSizeClassOf` switch + `_GridEditorBody` 拆分（ConsumerWidget，select sourceTooSmall 减少 rebuild）+ 外层 Center+ConstrainedBox + 新常量 `_kGridControlsPanelWidth = 380` + 删除原私有 `_NineGridSocialRow` 类 |

**test/**

| 文件 | 测试数 | 说明 |
|------|--------|------|
| `test/features/long_stitch/presentation/stitch_editor_responsive_test.dart` | 5 | compact/medium 找 StitchControlsSheet + StitchControlsPanel；expanded/large 只找 panel；maxContentWidth cap |
| `test/features/grid/presentation/grid_editor_responsive_test.dart` | 5 | compact/medium 找 panel + 验证 stacked（同 dx，panel 在下）；expanded/large 验证 side-by-side（panel.dx > canvas.dx）；maxContentWidth cap |

#### 4) 测试基础设施小坑

stitch / grid editor 屏的 body 用了 `Column + Expanded` 结构，**只**用 `MediaQuery` override `size` 不够 —— 因为 Flutter 测试默认 paint surface 是 800×600，`Column + Expanded` 依赖真实 bounded vertical constraints。home / export 屏没有这个问题（body 是 ListView / SCV，能优雅吃任何高度）。

修法：在新测试里加 helper

```dart
Future<void> _setViewportSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
```

设置真实 surface size 后 layout 才能正确计算 Expanded 子元素的可用高度。

另一个小坑：stitch 编辑器的 image strip 用 `Image.memory(image.bytes)`，原本 `stitch_controls_sheet_test` 用 `Uint8List.fromList([1,2,3,4])` 这种假字节没问题（sheet 不渲染 strip），但新的 editor 屏测试会真的渲染 strip。修法：用 `image` 包生成真实 8×8 PNG bytes：

```dart
Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}
```

#### 5) 验证（Round 2c-part2 后，最终状态）

```text
$ dart format lib/ test/
Formatted 116 files (0 changed) in 0.15 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.3s)

$ flutter test
…
00:06 +260: All tests passed!   # 260 / 260（part1 后 250 + part2 新增 10）
```

#### 6) 不变量 / 设计要点

- `StitchControlsSheet` 公共 API 完全不变（向后兼容现有 4 个 sheet 测试）；它现在是 `Material → StitchControlsPanel` 的薄壳
- `NineGridSocialRow` 由私有 `_NineGridSocialRow` 提升为公共类，现在可以在 `GridControlsPanel` 之外被引用（未来如果有第三个屏需要这个 toggle 也能复用）
- 两个 editor 的 panel 宽度都设为 380dp（`_kStitchControlsPanelWidth` / `_kGridControlsPanelWidth`），保持横向一致的视觉节奏；这个值能容纳最长的滑块标签 + 数值显示而不换行，又比画布的 flex 区窄，让画布保持 tablet / desktop 上的视觉主体
- 两个 editor 都按 `Center + ConstrainedBox(maxWidth: 1200)` 顶层包装，与 home / export 一致；large 窗口（≥1200 dp）整个内容居中且不超过 1200 dp 宽
- grid 编辑器 body 改为 `ConsumerWidget` 并用 `provider.select((s) => s.sourceTooSmall)` 只订阅必要状态，避免无关 state 变化触发整个 body 重建

#### 7) 本轮明确不做（Round 2d / Round 3 范围）

- 暗色模式 visual QA（每个屏走查 dark seed）
- a11y / tooltip / Semantics label 补齐
- 错误文案补充（Round 2b 已做）
- 性能 benchmark（20 张图 < 5s、内存 < 500MB、冷启 < 2s）
- 平台手动测试矩阵
- 把 stitch controls sheet 内容改为 scrollable（窄屏小高度时仍有溢出风险，UX 改进，非本轮 surgical 范围）

#### 8) 风险 / 疑问

- 测试基础设施修改（`tester.view.physicalSize`）只在 5 个新测试里使用，其它测试没动，没回归风险
- 新的 panel 宽度 380dp 是 hard-coded 常量，如果未来设计要求 fluid 宽度（比如 30% of canvas），需要把 SizedBox 换成 Expanded(flex: 1) 或 LayoutBuilder
- expanded / large 窗口下 stitch editor 的 image strip 仍然横跨整个 maxContentWidth=1200，没和 panel 列对齐。视觉上是单独 row（合理 —— strip 是上下文 metadata，不属于 controls）；如果设计审稿觉得 "strip 应该限于画布列宽"，需要再改一次（本轮按"strip 横跨"实现，与原始 mock 的视觉层级一致）

---

## Round 2d — 暗色 + a11y + 两个遗留 gap

Round 2d 是 polish 阶段的最后一轮（性能 benchmark / 平台手动测试不在本任务范围内）。本轮闭合了 Round 2b / 2c 留下的两个 UX gap，把暗色模式 + 无障碍走查推到 mvp 可接受线。

### 1) Gap 修复

#### Gap 1.1 — `gal` 插件英文 enum 翻译为中文

**问题**: Round 2b-part2 风险记录 → `gallery_saver_datasource.dart` 在 `on GalException catch (e)` 分支把 `e.type.message` 喂进 `saveFailureMessage(e.type.message)`。`GalExceptionType.message` 是插件烧死的英文（"Permission to access the gallery is denied." 等），所以用户看到 "保存失败：Permission to access the gallery is denied." 这种中英混合 snackbar。

**修复**:

1. `lib/core/errors/user_facing_messages.dart` 增加 `gallerySaveFailureMessage(GalException e)`：

```dart
String gallerySaveFailureMessage(GalException e) => switch (e.type) {
  GalExceptionType.accessDenied      => '保存失败：相册权限被拒绝，请在系统设置中开启后重试',
  GalExceptionType.notEnoughSpace    => '保存失败：存储空间不足',
  GalExceptionType.notSupportedFormat => '保存失败：图片格式不被相册支持',
  GalExceptionType.unexpected        => '保存失败：${describeCause(e)}',
};
```

2. `gallery_saver_datasource.dart` 的 `on GalException catch (e)` 分支改为 `return SaveFailure(gallerySaveFailureMessage(e));`。

**Layer trade-off**: `core/errors/user_facing_messages.dart` 现在 import `package:gal/gal.dart`。严格说这是 core 层依赖 plugin 包（违反 "Data-source DTO isolation" pattern）。但是 user_facing_messages 的定位是 "error translation surface"，把插件 enum 翻译表集中在这里比让每个 datasource 自己内嵌字符串更可维护。其他 datasource (file_dialog / web_blob) 没有等价的 enum，所以不会扩散到额外 plugin 依赖。

#### Gap 1.2 — import 失败的 snackbar 接入

**问题**: Round 2b-part1 落地的 `importFailureMessage(cause)` helper **没有 callsite** —— `image_import_provider.dart` 在 import 失败时 `state = AsyncError(failure, ...)`，但 UI 只通过 `importedImagesProvider.valueOrNull ?? const []` 消费，所以失败被静默丢弃。

**修复**:

1. `image_import_failure.dart` 给 `sealed class ImageImportFailure` 的所有变体加 `toString()`，返回 zh-CN 描述（前提是 `describeCause` 会调用 `error.toString()`）：

```dart
class UnsupportedSource extends ImageImportFailure {
  ...
  @override
  String toString() => '当前平台不支持的导入来源（$source）';
}
class TooManyImages extends ImageImportFailure {
  ...
  @override
  String toString() => '尝试导入 $attempted 张图片，超过上限 $maxAllowed 张';
}
// ImportCancelled / InvalidImageData / PermissionDenied / UnknownImportFailure 同样模式
```

2. `stitch_editor_screen.dart` + `grid_editor_screen.dart` 各 attach 一次 `ref.listen<AsyncValue<List<ImportedImage>>>(imageImportControllerProvider, ...)`：

```dart
ref.listen<AsyncValue<List<ImportedImage>>>(imageImportControllerProvider, (
  previous,
  next,
) {
  if (next is! AsyncError) return;
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(importFailureMessage(next.error))),
  );
});
```

只在两个 editor 屏 attach 是有意为之：
- home 屏没有 import 入口（FeatureCard 是 navigation）。
- 两个 editor 屏不会同时 mount（GoRouter 单实例），所以 listener 不会重复触发。
- 用户在哪个屏 import 失败，就在哪个屏看到 snackbar；这与"snackbar 在产生失败的 surface 上出现"的 mental model 一致。

`ImportCancelled` 已经在 provider 的 switch 里被吃掉（不会 promote 到 AsyncError），所以 listener 不会因用户取消而误报。

### 2) 暗色模式 visual QA

#### 2.1 走查方法

静态 grep 三种模式：
1. `grep "Color(0xFF\|Colors\." lib --include="*.dart"` — 找出非语义化颜色硬编码
2. `grep "withValues(alpha:" lib --include="*.dart"` — 找出叠加 surface 的 alpha overlay（dark scheme 下最容易失效的形式）
3. `grep "fontSize:" lib --include="*.dart"` — 找出绕过 textTheme 的字号硬编码

#### 2.2 风险点 → 修复

| 文件 | 风险 | 修复 |
|------|------|------|
| `lib/features/home/presentation/widgets/tips_banner.dart` | `tertiaryContainer.withValues(alpha: 0.10)` 作 bg + `(alpha: 0.20)` 作 border。dark scheme 的 `tertiaryContainer` 本身是暗紫红，10% / 20% alpha 叠在 dark surface 上等于近乎透明 → banner 在 dark 模式下"消失"。 | 改为 `Color.alphaBlend(tertiaryContainer.withValues(alpha: 0.10/0.30), surface)`，预先把 tint 与 surface 显式叠加，保证产物是不透明颜色 → light/dark 都能看到清晰的 banner。 |
| `lib/features/grid/presentation/screens/grid_editor_screen.dart` `_SourceSizeWarning` | `errorContainer.withValues(alpha: 0.4)` 作 bg + `error.withValues(alpha: 0.4)` 作 border。dark `errorContainer` 是暗红，40% alpha 在 dark surface 上仍能看到但对比度不够。 | 同样用 `Color.alphaBlend(...)`，让 light/dark 下 warning banner 视觉强度一致。 |
| `lib/features/export/presentation/widgets/save_disclaimer.dart` | inner icon chip 的背景 `tertiaryContainer.withValues(alpha: 0.2)` 在 dark 模式下消失。 | 用 `Color.alphaBlend(tertiaryContainer.withValues(alpha: 0.2), surface)`。 |

#### 2.3 接受的现状（已知遗留 / 设计意图）

- `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` 的 `_borderSwatches` 包含 `Colors.black / Colors.white / Color(0xFF...)` 等硬编码颜色 —— 这些是**色谱选项**（用户从 6 个固定颜色里选边框色），不是 theme tokens。保留硬编码符合"色谱固定不应跟 theme 变化"的语义。
- `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` 的网格线 `Color(0xFFFFFFFF).withValues(alpha: 0.6)` —— 网格线叠加在用户的图片上，无论 light/dark 都需要白色（与图片对比，不与 app theme 对比）。设计意图与 mock HTML 一致。
- `lib/features/grid/presentation/widgets/center_cell_overlay.dart` 的 CTA placeholder `Colors.black.withValues(alpha: 0.2) + Colors.white text` —— 同理是叠加在用户图片上的 chrome，固定黑底白字是合理。
- `lib/features/home/presentation/widgets/feature_card.dart` 的 `Colors.black.withValues(alpha: 0.04)` 阴影 —— 4% alpha 极淡，在 light/dark 下都接近不可见，属于 elevation 装饰，保留。
- `lib/features/long_stitch/domain/entities/stitch_border.dart` 的默认 `Color(0xFF000000)` —— 这是 domain entity 的 **默认值**（用户未选时默认黑色），不是 theme token。✗ 严格意义上 domain 不应 import flutter，但 `StitchBorder.color` 字段必须用 `Color`（presentation 和 data 层都要消费），这是项目已存在的 cross-layer 折中，本轮不动。
- 其它窗口装饰、shadow、固定品牌色继续保留。

#### 2.4 测试

新增 6 个 dark mode smoke tests:

- `test/features/home/presentation/home_screen_dark_mode_test.dart` (3 tests)
  - HomeScreen 在 `ThemeMode.dark` 下渲染不抛错
  - TipsBanner 的背景是 alphaBlend 产物（验证 `decoration.color.a == 1.0`）
  - HomeScreen 在 `ThemeMode.light` 下渲染不抛错
- `test/features/export/presentation/export_screen_dark_mode_test.dart` (3 tests)
  - ExportScreen 在 `ThemeMode.dark` 下渲染不抛错
  - SaveDisclaimer 的 icon chip 背景是 alphaBlend 产物
  - ExportScreen 在 `ThemeMode.light` 下渲染不抛错

### 3) 无障碍 a11y

#### 3.1 走查方法

1. `grep "IconButton\|GestureDetector\|InkWell" lib --include="*.dart"` —— 找所有 tappable 节点
2. 对每个节点 verify (a) tooltip / Semantics label 存在 (b) 触控目标 ≥ 48×48
3. 跑 `meetsGuideline(androidTapTargetGuideline / iOSTapTargetGuideline / textContrastGuideline / labeledTapTargetGuideline)` 端到端验证

#### 3.2 修复清单

| 文件 | 风险 | 修复 |
|------|------|------|
| `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` `_ColorSwatch` | 24×24 GestureDetector，没 Semantics label，触控目标低于 48×48 | (1) 包外层 `Semantics(button: true, selected: selected, label: '边框颜色')`；(2) hit area 用 `SizedBox(width: 48, height: 48, child: Center(child: visualDisc24x24))` 扩到 48×48；(3) 外层 swatches `Row` 改为 `Wrap` 避免 6 个 48dp swatches 在窄屏溢出 |
| `lib/features/grid/presentation/widgets/grid_parameter_cards.dart` `_BentoCard` | InkWell 没 Semantics label，screen reader 只能念 generic "button" 而无法说出"调间距还是圆角" | 包 `Semantics(button: true, label: '$label，当前 $value')`，让读屏直接念出参数名 + 当前值 |
| `lib/features/grid/presentation/widgets/center_cell_overlay.dart` GestureDetector | 中心格 pinch/pan/long-press 没 a11y label，empty-state CTA InkWell 也没 label | (1) 把 GestureDetector 包在 `Semantics(label: '中心格图片，双指缩放或拖动调整', hint: '长按以打开图片操作菜单', onLongPress: ...)` 内；(2) `_CenterCtaButton` 包 `Semantics(button: true, label: '替换中心格图片')` |
| `lib/features/export/presentation/widgets/watermark_card.dart` master Switch | bare Switch 没 a11y label —— `labeledTapTargetGuideline` 检查失败 | 把 "水印" Text + Switch 用 `MergeSemantics` 包起来，让读屏念出 "水印, switch, off/on"；Semantics(label:) 单独包 Switch 不起作用因为 Switch 自带 Semantics node 不会合并外层 label |

#### 3.3 接受的现状 / 已知遗留

- `lib/features/long_stitch/presentation/widgets/stitch_mode_segmented.dart` 的 `_Segment` InkWell —— 没有显式 Semantics label，但 Material 的 InkWell 默认会暴露 button role + child text 作为 label。`androidTapTargetGuideline` 和 `labeledTapTargetGuideline` 在 home / export 屏都过了，stitch 屏没有专门测，但行为是 default-correct。
- `lib/features/grid/presentation/widgets/grid_type_selector.dart` 已经手动包 Semantics（之前的 task 落地的）。
- `lib/features/export/presentation/widgets/format_quality_card.dart` 已经手动包 Semantics。
- `lib/features/export/presentation/widgets/watermark_card.dart` 的 `_AnchorCell` 已经手动包 Semantics。
- 文字基本走 `Theme.of(context).textTheme.xxx`，唯一硬编码 `fontSize: 12` 出现在 `center_cell_overlay.dart` 的 CTA placeholder，因为它叠在用户图片上是 chrome 文字（不应跟系统字号缩放），属于设计意图。
- stitch / grid editor 屏没有专门的 a11y guideline test —— 它们的 widget 主体（StitchControlsPanel / GridControlsPanel）在新加的 a11y 修复中已经覆盖；正式的 editor-level a11y 测试需要复杂的 viewport setup（见 Round 2c-part2 的 `tester.view.physicalSize` 经验），本轮按"高价值优先"原则跳过，记为后续可选改进。

#### 3.4 测试

新增 8 个 a11y guideline tests:

- `test/features/home/presentation/home_screen_a11y_test.dart` (4 tests)
  - meetsGuideline(androidTapTargetGuideline)
  - meetsGuideline(iOSTapTargetGuideline)
  - meetsGuideline(textContrastGuideline)
  - meetsGuideline(labeledTapTargetGuideline)
- `test/features/export/presentation/export_screen_a11y_test.dart` (4 tests)
  - 同上 4 个 guideline

### 4) 验证（Round 2d 修改后，最终状态）

```text
$ dart format lib/ test/
Formatted 120 files (0 changed) in 0.17 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.3s)

$ flutter test
…
00:00 +274: All tests passed!   # 260 (Round 2c-part2) + 14 新增 = 274
```

新增覆盖（14 个）:
- 6 个 dark mode smoke tests
- 8 个 a11y guideline tests（4 home + 4 export）

### 5) 修改清单（Round 2d）

**lib/**:

| 文件 | 类型 | 内容 |
|------|------|------|
| `lib/core/errors/user_facing_messages.dart` | MODIFIED | 新增 `gallerySaveFailureMessage(GalException e)`，import gal 包 |
| `lib/features/export/data/datasources/gallery_saver_datasource.dart` | MODIFIED | `on GalException catch (e)` 改为 `gallerySaveFailureMessage(e)` |
| `lib/features/image_import/domain/entities/image_import_failure.dart` | MODIFIED | 所有 sealed 变体加 `toString()` 中文实现 |
| `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` | MODIFIED | 加 import-failure listener (ref.listen → snackbar) |
| `lib/features/grid/presentation/screens/grid_editor_screen.dart` | MODIFIED | 同上 + `_SourceSizeWarning` 用 `Color.alphaBlend` 修暗色对比 |
| `lib/features/home/presentation/widgets/tips_banner.dart` | MODIFIED | 用 `Color.alphaBlend` 显式叠加 tint 与 surface |
| `lib/features/export/presentation/widgets/save_disclaimer.dart` | MODIFIED | 同上 |
| `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` | MODIFIED | `_ColorSwatch` 加 Semantics + 48×48 hit area；外层 swatches Row → Wrap |
| `lib/features/grid/presentation/widgets/grid_parameter_cards.dart` | MODIFIED | `_BentoCard` 加 Semantics(label) |
| `lib/features/grid/presentation/widgets/center_cell_overlay.dart` | MODIFIED | GestureDetector 包 Semantics；`_CenterCtaButton` 包 Semantics |
| `lib/features/export/presentation/widgets/watermark_card.dart` | MODIFIED | 标题 + Switch 用 MergeSemantics 合并 |

**test/**:

| 文件 | 类型 | 测试数 |
|------|------|--------|
| `test/features/home/presentation/home_screen_dark_mode_test.dart` | NEW | 3 |
| `test/features/export/presentation/export_screen_dark_mode_test.dart` | NEW | 3 |
| `test/features/home/presentation/home_screen_a11y_test.dart` | NEW | 4 |
| `test/features/export/presentation/export_screen_a11y_test.dart` | NEW | 4 |

### 6) 风险 / 疑问

- `core/errors/user_facing_messages.dart` 现在 import gal 包 —— 严格说违反 "core 干净 / plugin 限制在 datasource" 模式，但 user_facing_messages 是错误翻译表的集中点，让它知道 gal enum 比让每个 datasource 内联中文字符串更可维护。如果未来其它 datasource 也需要类似翻译（file_picker / image_picker 错误码），同一个 helper 会越来越像 "plugin error registry"。
- import-failure listener 在两个 editor 屏分别 attach。如果未来增加第三个使用 `imageImportControllerProvider` 的屏（比如 widget gallery），需要在该屏也 attach 同样的 listener，否则失败会再次"消失"。
- `_ColorSwatch` 外层从 `Row` 改成 `Wrap` 改变了视觉行为：在足够宽时仍是单行（与原来一致），但在窄屏（compact phone < 320 dp effective）会 wrap 到第二行。这是为了让 48×48 hit area 不导致水平溢出的必要 trade-off。
- Editor 屏 (stitch / grid) 没有专门的 a11y guideline 测试 —— 这两个屏的 layout 需要 `tester.view.physicalSize` setup 才能 pump，与 home / export 的 MediaQuery 模式不同。Round 2c-part2 已经踩过这个坑，本轮按"先覆盖高价值"原则只测 home + export 两个 surface。如果未来想完整覆盖，可以参考 `stitch_editor_responsive_test.dart` / `grid_editor_responsive_test.dart` 的 viewport setup helper。
- 暗色模式 visual QA 完全是静态分析 + smoke render，没有真实人眼审查。`Color.alphaBlend` 修复确保产物不透明，但实际"对比度是否达标"还需要在真实设备上目视确认（属于 Round 3 / 平台测试阶段）。

### 7) 本轮明确不做（Round 3 / 平台测试范围）

- 性能 benchmark（20 张拼接 < 5s、内存 < 500MB、冷启 < 2s）
- 平台手动测试矩阵（iOS / Android / macOS / Win / Linux / Web）
- 真实设备 dark mode 目视审查
- Editor 屏（stitch / grid）的端到端 a11y guideline 测试
- import-failure listener 的位置抽取（若未来出现第三个消费 surface）



---

## Round 3 — 性能 benchmark + manual test plan

Round 3 = headless benchmark harness + Timeline 标记 + manual checklist。
PRD §7 三个性能预算：20 张拼接 < 5s（headless 可测）/ 内存 < 500 MB / 冷启 < 2s（后两个只能 manual）。

### 1) Timeline 标记

为 DevTools Performance overlay 提供阶段化追踪，让 release-build profile 时能一眼定位是 decode / compose / encode 哪个阶段超 budget。

| 文件 | 标签 |
|------|------|
| `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart` | `stitch.decode`, `stitch.compose`, `stitch.encode` |
| `lib/features/grid/data/renderers/grid_image_renderer.dart` | `grid.cell-render`（外层循环）, `grid.encode`（每个 cell 的 PNG encode）|
| `lib/features/export/data/repositories/export_repository_impl.dart` | `export.save`（包裹 _persist 的平台 dispatch）|

实现细节：
- 用 `Timeline.startSync(label)` + try / finally + `Timeline.finishSync()` 包裹同步段，保证抛异常也能正确 finish
- `Timeline.timeSync` 也可以但 `startSync/finishSync` 更直观，特别是当一段代码可能 early-return（如 stitch encode 的 switch 两个分支）
- import：`import 'dart:developer' show Timeline;`

### 2) Benchmark harness

新建 `test/benchmarks/`，两个 benchmark 文件：

| 文件 | 测试覆盖 |
|------|---------|
| `test/benchmarks/stitch_export_benchmark_test.dart` | 20 张 1920×1080 PNG encode + JPEG encode 两条路径 |
| `test/benchmarks/grid_export_benchmark_test.dart` | 3×3 (3000×3000) / 4×4 (4000×4000) / 3×3 social (with center replacement) 三条路径 |

关键约束：
- `@Tags(['benchmark'])` + `library;`：mark 文件为 benchmark；配合根目录 `dart_test.yaml` 的 `tags.benchmark.skip` 让默认 `flutter test` 跳过它们
- 显式 invocation：`flutter test --run-skipped --tags benchmark test/benchmarks/`（`--run-skipped` 覆盖 yaml 的 skip；`--tags benchmark` 缩窄到 benchmark group）
- 阈值用 30s 松弛 ceiling（基线工具，非 deadline gate）；PRD 5s 目标在 manual checklist 里通过 release build + 真机验证
- 使用直接 renderer call（`StitchImageRenderer.render` / `GridImageRenderer.render`），不走 export pipeline（避免 platform plugin mock）

### 3) 基线表（macOS Apple Silicon, debug profile）

| Benchmark | synth (ms) | render (ms) | output bytes | vs PRD 5s |
|-----------|-----------:|------------:|-------------:|----------:|
| stitch 20×(1920×1080) PNG | 865 | **5771** | 210 132 | **超 15%** |
| stitch 20×(1920×1080) JPEG q=85 | 841 | **9485** | 1 134 643 | **超 90%** |
| grid 3×3 @ 3000×3000 (9 cells PNG) | 211 | 584 | 5214 / cell | 通过 |
| grid 4×4 @ 4000×4000 (16 cells PNG) | 326 | 955 | 5216 / cell | 通过 |
| grid 3×3 social + center replacement | 208 | 577 | — | 通过 |

> Synth 时间不计入 budget（属于 benchmark 自己造测试数据的开销）。
> "render" 列就是 `StitchImageRenderer.render()` / `GridImageRenderer.render()` 的端到端耗时，包含 decode + compose + encode 三阶段。

### 4) 是否触发优化

**结论：本轮不优化**。理由：

1. **debug profile 数据不能直接对标 PRD**：headless benchmark 在 `flutter test` 下跑（debug 配置 + Dart VM JIT），release build 通常快 2–4×。stitch PNG 5.77s 在 debug 下，估算 release build 1.5–3s 区间，符合 PRD < 5s。
2. **renderer 已经走 isolate**：`StitchImageRenderer._shouldUseIsolate` 在 ≥ 5 张图或单图 ≥ 2MB 时自动 `compute()` 到 isolate；20 张测试用例必然走 isolate 路径。再引入更深层的 isolate fan-out（例如每张图独立 isolate）属于 prompt 限制的"非平凡优化"，先停下报告。
3. **JPEG quality=85 是已有最大用户档位**：JPEG encode 9.48s 比 PNG 慢 65%，说明 `image` 包的 libjpeg encoder 是热点。优化路径是 (a) 调低默认 quality（产品决策） / (b) 把 encode 放到独立 isolate（架构改动）—— 都超出 surgical 范围。
4. **真实 mid-tier 设备表现需要平台手动测试**：Apple Silicon 的 vs Pixel 5 / iPhone SE 2 的相对性能不能从 desktop benchmark 外推。release build 真机数字才是 PRD 的判定依据，进入 Round 3 之后的"平台手动测试矩阵"阶段。

### 5) Manual checklist

新建 `.trellis/tasks/05-08-polish-platform-test/research/manual-test-plan.md`，覆盖：

- **Section A**：冷启动测试 — Android `adb shell am start -W` / iOS Xcode Instruments，列了 mid-tier device list（iPhone SE 2 / Pixel 5）
- **Section B**：内存峰值 — Flutter DevTools Memory profiler，3 个 snapshot（loaded baseline / peak / steady state），含 20 张测试图准备清单
- **Section C**：6 平台兼容矩阵手动测试 — 每个平台 4 个 must-pass flows（vertical PNG / movie-subtitle JPEG / regular 3×3 / nine-grid social）+ 平台特定 extras（iOS Photos perm / Android scoped storage / macOS drag-drop / Windows HiDPI / Linux Wayland / Web blob download per browser）
- **Section D**：失败上报模板

### 6) 修改清单

**lib/**

| 文件 | 类型 | 内容 |
|------|------|------|
| `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart` | MODIFIED | import `dart:developer`；`_renderInIsolate` 三阶段用 Timeline.startSync / finishSync 包裹（try/finally 保证异常 unwind） |
| `lib/features/grid/data/renderers/grid_image_renderer.dart` | MODIFIED | 同上；外层 cell-render 循环 + 每 cell encode 嵌套 Timeline 标签 |
| `lib/features/export/data/repositories/export_repository_impl.dart` | MODIFIED | import `dart:developer`；`_persist` 整个平台 dispatch 段包在 `export.save` Timeline 内（含 await，return 改为 await ... 让 Timeline scope 包住实际 IO） |

**test/**

| 文件 | 类型 | 测试数 | 说明 |
|------|------|--------|------|
| `test/benchmarks/stitch_export_benchmark_test.dart` | NEW | 2（PNG / JPEG）| @Tags(['benchmark'])，print 阶段 timing |
| `test/benchmarks/grid_export_benchmark_test.dart` | NEW | 3（3×3 / 4×4 / 3×3 social）| 同上 |
| `dart_test.yaml` | NEW | — | 配置 `tags.benchmark.skip`，让默认 `flutter test` 跳过 benchmark group |

**.trellis/**

| 文件 | 类型 | 内容 |
|------|------|------|
| `.trellis/tasks/05-08-polish-platform-test/research/manual-test-plan.md` | NEW | 上述 4 个 Section |
| `.trellis/tasks/05-08-polish-platform-test/research/audit-report.md` | MODIFIED | 本节（Round 3）|

### 7) 验证（Round 3 修改后）

```text
$ dart format lib/ test/
Formatted 122 files (0 changed) in 0.16 seconds.

$ flutter analyze
Analyzing fl_picraft...
No issues found! (ran in 2.7s)

$ flutter test
…
00:08 +274 ~2: All tests passed!   # 274 pass + 2 skip（benchmark group 被 dart_test.yaml skip）

$ flutter test --run-skipped --tags benchmark test/benchmarks/
…
[stitch] synth elapsed: 865 ms
[stitch] render elapsed: 5771 ms
[stitch-jpeg] synth elapsed: 841 ms
[stitch-jpeg] render elapsed: 9485 ms
[grid-3x3] synth elapsed: 211 ms
[grid-3x3] render elapsed: 584 ms
[grid-4x4] synth elapsed: 326 ms
[grid-4x4] render elapsed: 955 ms
[grid-social] synth elapsed: 208 ms
[grid-social] render elapsed: 577 ms
00:18 +5: All tests passed!     # 5 个 benchmark 全 pass（30s 松弛阈值）
```

### 8) 风险 / 疑问

- **stitch PNG/JPEG 在 debug benchmark 超 PRD 5s budget**：本轮决定不优化，理由见 §4。release build + 真机数字才是判定依据，需要进入 manual checklist 阶段验证。如果真机也超 budget，候选优化路径（按代价从小到大）：
  1. PNG 默认压缩 level 从隐含的 6 改成 1（`img.encodePng(canvas, level: 1)`）—— 单文件单参数，速度提升 2-3x，但输出大约大 30%
  2. JPEG 默认 quality 从 85 降到 75 —— 产品决策，与 PRD §5.4 默认无损 PNG 的方向一致（JPEG 质量条用户可调）
  3. 把 encode 阶段进一步拆分到独立 isolate —— prompt 限制的"非平凡优化"
- **Timeline 标记只在 debug / profile build 起效**：release build 默认 strip 所有 Timeline 调用（`dart:developer` 在 release 下是 no-op）。这是预期行为：标记是开发期诊断工具，不影响生产路径。
- **benchmark 阈值 30s 是松弛 ceiling**：故意比 PRD 5s 大 6×，避免 CI 慢 runner 误报失败。如果未来 CI 想 enforce PRD budget，可以加一个 `flutter test --tags benchmark-strict` 标签 + 5s 阈值的并行测试套，但本轮按 prompt 不引入。
- **benchmark 是 desktop-only 数据**：headless test 在 host OS 上跑，无法替代真机性能数据。manual-test-plan.md 的 §A / §B 是 release build 真机测试的 single source of truth。
- **manual checklist 没有自动化执行**：本轮交付的是检查清单文档，需要在 release 前由人工或 release runner 执行。如果未来需要自动化（例如用 maestro / patrol 跑 6 平台 e2e），需要单开任务。

### 9) 不变量

- benchmark 文件用 `@Tags(['benchmark'])` mark + `dart_test.yaml` 的 `tags.benchmark.skip` 让默认 `flutter test` 跳过；显式触发要同时传 `--run-skipped --tags benchmark`（验证：`flutter test` 报 `+274 ~2: All tests passed!`，2 是 skip 的 benchmark group）
- Timeline 标记只增加观测点，**不改变** renderer 的输出 bytes（grid_image_renderer / stitch_image_renderer 的现有测试 274 全绿可证）
- export_repository_impl 的 `_persist` 改为 `await override(...)` / `await _gallery.save(...)` 等是为了让 Timeline 的 finally scope 真的包住 IO 完成 —— 等价于"返回 Future" → "等 Future 完成再返回结果"，对调用方语义不变（外层依然 await）；现有 export_repository_impl_test 全绿可证


