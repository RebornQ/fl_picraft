# 预览 UI 集成（Subtask B of 05-20-export-page-preview）

> 父任务：[`05-20-export-page-preview/prd.md`](../05-20-export-page-preview/prd.md)
> 兄弟任务：[`05-20-preview-renderer-infra/prd.md`](../05-20-preview-renderer-infra/prd.md)
> **依赖**：Subtask A 完成后才能开始（消费其 `previewControllerProvider`）

## Goal

在 `/export` 页面顶部插入预览区域，消费 Subtask A 的 `previewControllerProvider`，
完成 4 种 sealed 状态分派（**单层 switch**，无 `AsyncValue.when` 嵌套）、
stitch/grid 两路适配、点击全屏、骨架占位（stale bytes 优先 + widget canvas fallback）、
文件大小标签的 UI 实现。

## Requirements

### 核心 widget

1. **`PreviewCard`**（`lib/features/export/presentation/widgets/preview_card.dart`）
   - 顶级容器，`ref.watch(previewControllerProvider)` 直接拿 **`PreviewState`**（**不是** `AsyncValue<PreviewState>`）
   - 按 sealed `PreviewState` 单层 `switch` 穷尽分派：
     ```dart
     return switch (state) {
       PreviewEmpty() => _EmptyView(),
       PreviewLoading(:final staleBytes) => _LoadingView(staleBytes: staleBytes),
       PreviewReady(:final bytes, :final totalSizeBytes) => _ReadyView(...),
       PreviewError(:final message, :final staleBytes) => _ErrorView(...),
     };
     ```
   - 固定高度 240dp（design token，常量定义在 widget 文件内）
   - 卡片样式与 FormatQualityCard / WatermarkCard 一致（surfaceContainerLow + 圆角 + border）
   - 顶部 header："预览"标题；`PreviewReady` 状态下右侧附"约 X.X MB"标签

2. **`PreviewThumbnail`**（`preview_thumbnail.dart`）
   - 单张缩略图，stitch / grid 共用
   - `BoxFit.contain` 适配
   - 点击调用 `showDialog(...)` 弹出 `PreviewFullScreenDialog`

3. **`PreviewSkeleton`**（`preview_skeleton.dart`）
   - **极简占位**：surfaceContainerLow 背景 + 居中 `CircularProgressIndicator` + 下方文案
     （"加载中..." / "刷新中..." 按 staleBytes 是否非空决定）
   - **不复用** `StitchPreviewCanvas` / `GridPreviewCanvas`——见下方 *Decision (revised twice)* §D4
   - **不展示 staleBytes**——见下方 *Decision (revised)* §D4
   - 真实预览到达后 `AnimatedSwitcher` 淡入替换

4. **`PreviewFullScreenDialog`**（`preview_full_screen_dialog.dart`）
   - `Dialog.fullscreen` 包 `InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4.0)`
   - 顶部 AppBar：标题"预览"+ 关闭按钮
   - barrier dismissible，关闭后回到导出页

5. **状态分派**：
   - **`PreviewEmpty`**：占位 + "没有可预览的图片"文案
   - **`PreviewLoading(staleBytes)`**：始终走 `PreviewSkeleton`（spinner + 文案），
     **忽略 staleBytes**。文案按 staleBytes 是否非空决定（首次"加载中..."，
     刷新"刷新中..."）
   - **`PreviewReady(stitch)`**：单张 `PreviewThumbnail`
   - **`PreviewReady(grid)`**：水平 `ListView.builder` + 分页指示器或滚动指示
   - **`PreviewError(message, staleBytes)`**：错误图标 + 错误文案 + 「重试」`TextButton`
     （调用 `ref.read(previewControllerProvider.notifier).refresh()`）；若 `staleBytes != null` 同时
     在背景显示 stale（半透明），让用户知道"上一次还在那"——错误状态下保留 stale 是因
     "预览暂不可用"已经明确告知用户当前状态，stale 仅作安抚背景，**不会与 Loading 同样
     产生"以为是最新"的歧义**

### 集成

6. **修改 `export_screen.dart`**：
   - 在 `_ExportBody` 的 `Column` 最顶部插入 `_SectionCard(child: PreviewCard())`
   - 三种 size class 下保持顶部位置（compact 单列；medium+ 跨整行）
   - 不修改 FormatQuality / Watermark / Save / Disclaimer 的现有布局与行为

### 测试

7. **`preview_card_test.dart`**（widget 测试）
   - 4 种 sealed 状态各自正确分派（用 `ProviderScope.overrides` 注入 mock state）
   - `PreviewEmpty` 显示空文案
   - `PreviewError` 点击重试按钮触发 `refresh()`
   - `PreviewReady` 显示文件大小标签 `约 X.X MB`
   - `PreviewReady(grid)` 显示水平 ListView 且子图数量正确
   - `PreviewLoading(staleBytes: null)` → spinner + "加载中..." 文案；
     **断言 `StitchPreviewCanvas` / `GridPreviewCanvas` 不在树中**
   - `PreviewLoading(staleBytes: [bytes])` → spinner + "刷新中..." 文案；
     **断言 `Image.memory` 不在树中（stale 不展示）**
   - `PreviewError(staleBytes: [bytes])` → 背景显示 stale（半透明） + 错误图标
8. **`preview_full_screen_dialog_test.dart`**
   - 点击缩略图打开 Dialog
   - Dialog 关闭按钮关闭 Dialog
   - Dialog 内 `InteractiveViewer` 存在
9. **`export_screen_test.dart` 现有测试不破坏**：确保现有断言（Save 按钮、Watermark 卡片）仍通过

## Acceptance Criteria

- [ ] 进入 `/export` 页面顶部出现预览区，骨架占位先显示
- [ ] 真实预览到达后淡入替换，文件大小标签同步显示
- [ ] 切换 PNG/JPG / 调质量滑块 / 改水印配置 → 预览刷新（debounce 由 Subtask A 保证）
- [ ] Grid 模式下水平滚动浏览所有子图，每张含水印
- [ ] 点击缩略图打开全屏 Dialog，可双指缩放、可滚动
- [ ] 渲染失败显示错误占位 + 重试按钮，点击重试触发刷新
- [ ] 保存中（`isSaving=true`）预览停止刷新（由 Subtask A 保证，UI 不需要额外逻辑）
- [ ] compact / medium / expanded 三种 size class 下布局都合理
- [ ] 现有的 FormatQuality / Watermark / Save / Disclaimer 卡片与行为不受影响
- [ ] widget 测试覆盖 5 种状态、全屏 Dialog、重试按钮
- [ ] `flutter analyze` / `dart format .` / `flutter test` 全部 green

## Definition of Done

- 视觉风格与 FormatQualityCard / WatermarkCard 保持一致
- 与 `stitch_preview_canvas` / `grid_preview_canvas` 骨架占位平滑过渡（无白屏闪烁）
- 全屏 Dialog 关闭后焦点正确回到主页面
- 提交独立 PR，PR 描述附 compact / medium 两种屏幕下的 screenshot / GIF

## Decision (revised after user testing)

### D5 (added 2026-05-21)：全屏预览 InteractiveViewer 充满全屏 + 无限 boundary

**Context**：原实现 `Center(child: InteractiveViewer(child: Image.memory(fit: contain)))`
让 InteractiveViewer 的 viewport 收缩到 image 的 intrinsic display rect；又加上
`boundaryMargin: EdgeInsets.zero` 默认值，放大后超出原 viewport 的部分**无法 pan 到**。

**Real-world feedback**：用户实测时反映"全屏预览的画布应该是全屏的，现在画布大小是
图片内容大小，放大内容时会受限于画布大小而无法显示全部内容"。

**Decision**：反转嵌套关系——InteractiveViewer 直接做 `Scaffold.body`（充满全屏），
`Image.memory(fit: contain)` 用 Center 包起来放在 InteractiveViewer 内部居中显示；
加 `boundaryMargin: EdgeInsets.all(double.infinity)` 允许放大后无限 pan，与系统照片
查看应用的标准交互一致。

**Consequences**：
- ✅ Viewport = 全屏，放大后能 pan 到任何位置
- ✅ Image 初始 `BoxFit.contain` 居中显示效果不变
- ✅ 与 iOS / Material 照片查看应用的标准交互一致
- ⚠️ 测试需新增 `boundaryMargin == EdgeInsets.all(double.infinity)` 断言

### D6 (added 2026-05-21)：消除 mount 时闪过旧 PreviewReady 帧的 stale-flash bug

**Context**：`previewControllerProvider` 是普通 `NotifierProvider`（非 autoDispose），
controller 实例 + state 在用户离开 export 页面后**仍然存活**。用户返回 export 页面时，
PreviewCard 首次 watch 立即拿到上一次的 `PreviewReady(bytes: ...)`；而 `ref.listen`
回调触发的 `_scheduleRender` 走 300ms debounce → `_runRender` 才把 state 转入
`PreviewLoading`。这 300ms 内 UI **闪一下旧的 Ready 帧**，体验明显不顺。

**Real-world feedback**：用户实测"测试进入导出页面时, 如果有上一次的缓存, 预览页面
进入加载状态前会闪一下展现缓存再进入加载状态"。

**Decision**：两处协同修复，不引入 autoDispose（保留 `_cachedSource` 跨 visit 复用）：

1. **`build()` 同步决定初始 state**：新增 `_initialStateFromCache()` 辅助函数同步
   读 `processedBytesCacheProvider` + 当前编辑器 state——cache hit → 直接返回
   `PreviewReady(cached)` 并 seed `_lastRenderedKey`；cache miss 有源 → 返回
   `PreviewLoading()`（不再先返 Empty 再异步转 Loading）；无源 → `PreviewEmpty()`。

2. **`_scheduleRender()` 同步预转 Loading**：被 `ref.listen` 触发时，立即比对
   `_currentInputKey()` vs `_lastRenderedKey`——不同且当前不在 Loading 就同步
   `state = PreviewLoading(staleBytes: ...)`；之后再启动 300ms debounce timer。
   保留 idempotent 守卫避免重复 set Loading。

**Consequences**：
- ✅ 首帧准确：cache hit 立即 Ready 不闪；cache miss 立即 Loading 不闪
- ✅ 配置变更触发的 re-render 也立即转 Loading，spinner 与配置变化在视觉上同步
- ✅ 300ms debounce 行为不变（仍用于合并 slider 拖动期间的连续 listen）
- ✅ ProcessedBytesCache 跨 visit 复用不丢
- ⚠️ Riverpod 陷阱：`build()` 不能调用 `_scheduleRender()`（后者读 state，build 完成前
  state getter 抛 `StateError`），timer-queuing 逻辑被拆出独立路径。已加 4 个测试覆盖
  新契约（含 reverse-sanity：暂时回滚改动 → 3/4 测试失败 → 证明修复有效）
- 沉淀到 `.trellis/spec/frontend/state-management.md` "Don't: rely on async
  dependency-listens to set the initial state in a non-`autoDispose` controller"

### D7 (added 2026-05-21)：多 editor screen 同时存活的 FAB heroTag 冲突

**Context**：`StatefulShellRoute.indexedStack` 让 `StitchEditorScreen` 和
`GridEditorScreen` 同时挂载，两个 screen 各自的 `FloatingActionButton.extended('导出')`
都没显式设 `heroTag`，共用 `_kDefaultHeroTag`。点击任意一个 FAB 触发路由切换时，
Flutter 收集到 ≥2 个相同 tag 的 Hero，抛断言：

```
Hero animation: There are multiple heroes that share the same tag within a subtree.
... multiple heroes had the following tag: <default FloatingActionButton tag>
```

**Decision**：给两个 FAB 加显式唯一 `heroTag`——
`stitch-export-fab` / `grid-export-fab`。命名约定 `<feature>-<purpose>-fab`，
保留默认 hero animation（不使用 `heroTag: null` 禁用动画）。

**Consequences**：
- ✅ 多 screen 同存的导出按钮不再冲突
- ✅ FAB 的 MD3 hero 过渡动画保留
- ✅ 沉淀到 `.trellis/spec/frontend/component-guidelines.md` 作为 Gotcha：
  "FloatingActionButton 默认 heroTag 在多 screen 同时存活时冲突"
- ⚠️ 新增 screen 用 FAB 时必须 grep 现有 heroTag 避免命名碰撞

### D8 (added 2026-05-21)：previewControllerProvider 改 autoDispose 修 cache 生命期 leak

**Context**：`trellis-check` audit 发现 `previewControllerProvider` 是普通
`NotifierProvider`（非 autoDispose）：用户 pop `/export` 回 `/stitch` 或 `/grid` 后，
controller 实例 + 6 个 `ref.listen` 回调 + `_debounce` Timer + `_cachedSource` 都
**仍然存活**。用户在 editor 里拖滑块 / 改图 → listen 触发 `_scheduleRender` →
300ms debounce → `_runRender` → 调编辑器昂贵的 render() + `compute()` isolate hop →
写入 `processedBytesCacheProvider` LRU。**全部在后台默默进行**，用户看不见。
worst-case 内存留存 25-100 MB。

**Real-world finding（审计场景 A + F）**：
- Scenario A：后台 isolate render leak（隐性 CPU + 内存）
- Scenario F：worst-case 25-100 MB 常驻，无 background 释放路径

**Decision**：把 `previewControllerProvider` 和 `previewBytesProvider` 都改为 autoDispose：

```dart
class PreviewController extends AutoDisposeNotifier<PreviewState> { ... }

final previewControllerProvider =
    AutoDisposeNotifierProvider<PreviewController, PreviewState>(...);

final previewBytesProvider = Provider.autoDispose<List<Uint8List>>(...);
```

**关键**：`processedBytesCacheProvider` **保留非 autoDispose**——这样 PRD §D6 的
"mount 不闪 stale"契约不破坏：下次 mount 时 `_initialStateFromCache()` 仍能命中
缓存，同步返回 `PreviewReady`。

**Consequences**：
- ✅ pop `/export` 后所有 listen + Timer + `_cachedSource` 立即释放，**后台 render 停止**
- ✅ 内存随页面释放，不再 25-100 MB 常驻
- ✅ 在飞 `compute()` isolate 仍会跑完，但结果写入已 dispose 的 controller 时
  Riverpod 静默丢弃，不会污染缓存（key 仍正确，只是 PreviewState 不更新）
- ✅ "mount 不闪 stale"契约由 `processedBytesCacheProvider` 保留 + `_initialStateFromCache`
  同步命中保障，不破坏
- ⚠️ 所有现有 13 个 controller 测试需加 `_keepPreviewAlive(container)` helper，
  否则 `async.elapse(...)` 会触发 autoDispose 让 controller 跑路
- ⚠️ 新增 1 个 regression test 验证 `identical(notifier1, notifier2) == false` 后
  cache 仍存活（reverse-sanity 验证 autoDispose 真的 fire）
- 沉淀到 `.trellis/spec/frontend/state-management.md` 作为
  *Pattern: Split lifecycle — autoDispose controller + non-autoDispose cache*
  （任何"页面级 controller 持昂贵资源 + 跨 visit 复用 cache"的场景都可借鉴）

### D4 (revised twice 2026-05-21)：PreviewLoading 改用极简 spinner + 文案

**Iteration 1 (上线后实测)**：移除 staleBytes 展示，改用 widget canvas 骨架
（`StitchPreviewCanvas` / `GridPreviewCanvas` + Opacity(0.6) + chip）。理由是
stale 帧太逼真会误导用户。

**Iteration 2 (再次实测)**：widget canvas 骨架体验**也不好**——canvas 本身是
"完整的预览图样貌"（只是不含水印/格式编码），用户看到它仍会与"完成态"混淆，
并且 canvas 会随用户在编辑器侧的源图变化跳动，与"在加载中"语义脱节。

**Decision (final)**：PreviewLoading 改用**极简通用 loading 占位**——
surfaceContainerLow 背景 + 居中 `CircularProgressIndicator` + 文案，**不复用
编辑器的任何 canvas widget**。文案按 staleBytes 是否非空区分（首次"加载中..."，
刷新"刷新中..."），spinner 视觉一致。

**Consequences**：
- ✅ 视觉上**明显不像"完成的预览"**，用户一眼知道是"在加载"
- ✅ 不再随编辑器源图变化跳动，loading 占位语义稳定
- ✅ 不依赖任何 cross-feature widget（`PreviewSkeleton` 完全独立）
- ✅ 零额外依赖（Material 标准 `CircularProgressIndicator`）
- ⚠️ Loading 期间不再有"近似预览"的视觉信号——但 stitch/grid 编辑器自己的预览
  canvas 仍在导出页面之前的编辑器页面里可见，用户进入导出页面前已经看过
- ⚠️ `currentExportSourceKindProvider` 不再被 `PreviewSkeleton` watch，
  减少了一次 cross-feature provider 依赖
- ⚠️ PreviewState.PreviewLoading.staleBytes 字段仍保留不删（Subtask A 代码不改），
  保留扩展空间

**Out of scope of this revision**：
- 不删除 `PreviewState.PreviewLoading.staleBytes` 字段（Subtask A 代码不改）
- 不改 PreviewError 的 stale 展示行为
- 不引入 shimmer 包等额外依赖
- 不修改 PreviewEmpty / PreviewReady 的视觉

## Known Issues / Follow-up

### Scenario B（待后续 polish）：`refresh()` 过度清理整张 LRU

**Source**：`trellis-check` cache 生命周期 audit（2026-05-21）。

**问题**：`refresh()` 当前实现（`preview_controller.dart`）调用
`processedBytesCacheProvider.notifier.invalidate()` **清空整张 LRU 4 条**，而非
只清当前失败的 key。如果用户在 PNG/q=90 上失败，点重试 → 即便之前在
PNG/q=80 / JPG/q=90 / JPG/q=80 上有 3 条好缓存也全部被丢弃，下次切回这些组合
需要全部重新 render。

**根因**：PRD §5 / §D5 描述 refresh "绕两层缓存" 被理解为"清空整张 LRU"，
应理解为"**本次** render 绕开两层缓存"——精细 invalidate 才对。

**建议方案**（留作后续）：
1. `ProcessedBytesCache` 新增 `invalidateKey(int key)` API
2. `refresh()` 改为先取 `_currentInputKey()`，仅 invalidate 该 key

**优先级**：低。这是优化项，不是 bug；用户体验上仅"重试后某些缓存丢失"，不会导致
错误结果。等下一个 preview 相关任务时一起处理。

**Spec 触发**：本任务的 audit 也发现 Scenario F (内存留存) 已被 D8 (autoDispose)
解决；Scenario C / D / E 行为正确。仅 Scenario B 留作后续。

## Out of Scope

- 修改任何 `data/` / `domain/` 层代码（在 Subtask A 完成）
- 修改 `applyWatermark` / `encodeForExport` 内部实现
- 预览图独立分享 / 下载

## Technical Notes

- `_SectionCard` 现有定义在 `export_screen.dart`（私有类），可继续复用
- 骨架占位的 widget 来源派生：
  ```dart
  ref.watch(currentExportSourceKindProvider) == ExportSourceKind.stitch
    ? const StitchPreviewCanvas()
    : const GridPreviewCanvas()
  ```
  注意它们位于 `lib/features/{long_stitch,grid}/presentation/widgets/`——跨 feature 引用，
  遵循 `directory-structure.md` → "Cross-feature Dependencies" 走 public 导出
- 文件大小标签格式：`'${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'`（grid 模式取所有子图之和）
- `Dialog.fullscreen` 是 MD3 推荐的全屏对话框样式（M3 spec ref）

## 与父任务/兄弟任务的契约

- **输入依赖**：Subtask A 的 `previewControllerProvider`（返回 **`PreviewState`**，不是 `AsyncValue<PreviewState>`）
- 不直接调用 `processExportBytes()` 或任何 isolate 路径，全部走 provider
- 不修改 `ExportController.save()` —— save 路径的 cache hit 优化由 Subtask A 完成，对 UI 透明
