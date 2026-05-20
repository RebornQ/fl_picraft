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
   - **首次进页**（`PreviewLoading.staleBytes == null`）：复用 `StitchPreviewCanvas` /
     `GridPreviewCanvas`（根据 `currentExportSourceKindProvider` 派生），包一层 `Opacity(0.6)`
     + 顶部"加载中..."chip 让"未完成"语义可见
   - **从 Ready 转入 Loading**（`PreviewLoading.staleBytes != null`）：显示 stale bytes
     + 顶部"刷新中..."chip 让用户知道在跟随配置变化重渲染
   - 真实预览到达后 `AnimatedSwitcher` 淡入替换

4. **`PreviewFullScreenDialog`**（`preview_full_screen_dialog.dart`）
   - `Dialog.fullscreen` 包 `InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4.0)`
   - 顶部 AppBar：标题"预览"+ 关闭按钮
   - barrier dismissible，关闭后回到导出页

5. **状态分派**：
   - **`PreviewEmpty`**：占位 + "没有可预览的图片"文案
   - **`PreviewLoading(staleBytes)`**：见 `PreviewSkeleton` 上面的两段逻辑
   - **`PreviewReady(stitch)`**：单张 `PreviewThumbnail`
   - **`PreviewReady(grid)`**：水平 `ListView.builder` + 分页指示器或滚动指示
   - **`PreviewError(message, staleBytes)`**：错误图标 + 错误文案 + 「重试」`TextButton`
     （调用 `ref.read(previewControllerProvider.notifier).refresh()`）；若 `staleBytes != null` 同时
     在背景显示 stale（半透明），让用户知道"上一次还在那"

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
   - `PreviewLoading(staleBytes: null)` → widget canvas 骨架
   - `PreviewLoading(staleBytes: [bytes])` → 显示 stale bytes + "刷新中" chip
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
