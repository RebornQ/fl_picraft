# 导出页面预览图

## Goal

让用户进入 `/export` 页面时能"所见即所得"地看到即将保存的最终图像，
不必先点"保存"再去相册里翻看效果。减少误操作（错选格式、忘开/关水印、水印位置不满意），
也让长图拼接 / 网格切片两条来源都有统一的视觉确认入口。

## Requirements (final)

### 核心功能

1. **预览区域**：在 `/export` 页面顶部新增预览区域，固定高度（建议 240dp）
2. **真实渲染**：走完整导出管线 `render → applyWatermark → encodeForExport` 产出最终字节，所见即所得
3. **两路来源适配**：
   - **stitch**：单张长图，BoxFit.contain 缩略
   - **grid**：水平滚动 ListView 显示全部子图（带分页/滚动指示器）
4. **配置联动**：水印（开关/文字/锚点/透明度/字号）、格式（PNG/JPG）、JPG 质量变化时预览刷新
5. **防抖**：配置变化时 debounce 300ms，避免连续触发
6. **点击全屏**：点击预览缩略图打开 `Dialog`（`InteractiveViewer`）查看原尺寸 + 双指缩放 + 上下滚动

### MVP 加分项（全部纳入）

7. **预估文件大小标签**：预览下方显示"约 X.X MB"，PNG/JPG/质量切换时数字跟随
8. **失败降级 + 重试**：渲染失败显示错误占位 + 「重试」按钮，不静默
9. **保存中暂停预览渲染**：当 `ExportState.isSaving=true` 时暂停预览刷新，避免抢 CPU 拖慢保存
10. **骨架占位**：首屏加载时显示 widget 版预览（复用 `stitch_preview_canvas` / `grid_preview_canvas`），真实渲染完成后淡入替换

### 性能与可观测

- 渲染走 isolate（`compute()`），主 isolate 无 jank
- 缓存最近一次预览（按 `(sourceKind, watermarkConfig, format, quality, sourceHash)` 哈希）避免重建白屏
- 关键路径打 `Timeline.startSync('export.preview')`（区分于 `export.save`）

## Acceptance Criteria

- [ ] 进入 `/export` 页面立即可见骨架占位，2 秒内（小图）/ 5 秒内（长图）替换为真实预览
- [ ] 切换 PNG/JPG、调质量滑块后，debounce 300ms 后预览刷新；文件大小标签同步更新
- [ ] 切换水印开关 / 文字 / 锚点 / 透明度 / 字号后，debounce 300ms 后预览刷新
- [ ] Grid 模式下，所有子图水平 ListView 展示，每张独立含水印
- [ ] 点击 stitch 预览或任一 grid 子图，弹出全屏 `Dialog`，可缩放、可滚动
- [ ] 渲染失败时显示「预览暂不可用」+「重试」按钮，点击重试触发重渲染
- [ ] 保存中（`isSaving=true`）预览不重渲染；保存结束后恢复
- [ ] compact / medium / expanded 三种 size class 下，预览区始终位于顶部，Save CTA 始终位于底部
- [ ] 不破坏现有的 FormatQuality / Watermark / Save / Disclaimer 卡片布局与行为
- [ ] 单元 + widget 测试覆盖：
  - PreviewProvider 防抖、缓存、保存中暂停的契约
  - PreviewCard widget 在 stitch / grid / loading / error / empty 五种状态下的渲染
  - 文件大小标签随 format/quality 变化
  - 全屏 Dialog 的打开/关闭

## Definition of Done

- Tests added/updated（widget + provider + repository helper）
- `flutter analyze` / `dart format .` / `flutter test` 全部 green
- 关键性能点添加 `Timeline.startSync('export.preview')` 标记
- 与现有 `stitch_preview_canvas` / `grid_preview_canvas` 视觉风格保持一致
- 不破坏现有的 Save CTA 跨 size class 全宽行为

## Out of Scope

- 完整重做导出页面布局（仅在顶部新增预览区，其余卡片不动）
- 预览图独立导出 / 分享（仍走原有 SaveActionButton）
- 编辑器内预览的优化（本任务只关心 `/export` 上的预览）
- 替代当前 `applyWatermark` / `encodeForExport` 管线
- 预览中支持局部编辑（如直接拖动水印位置）—— 配置面板仍是唯一编辑入口

## Technical Approach

### 关键组件

```
lib/features/export/
  data/
    preview_renderer.dart      # processExportBytes 公共函数 + typedef ProcessBytesFn
  presentation/
    providers/
      preview_controller.dart  # NotifierProvider<PreviewState>（非 AsyncNotifier）
                               # 含 source 缓存 / debounce / 暂停门 / refresh
      preview_state.dart       # sealed: PreviewEmpty | PreviewLoading{staleBytes?} |
                               #         PreviewReady{bytes,totalSizeBytes} |
                               #         PreviewError{message, staleBytes?}
      processed_bytes_cache.dart  # NotifierProvider<LRU Map>，preview+save 共用
      process_bytes_fn.dart    # Provider<ProcessBytesFn> 注入点（测试可 override）
    widgets/
      preview_card.dart        # 单层 switch 分派（不嵌套 AsyncValue.when）
      preview_thumbnail.dart   # stitch 一张 / grid N 张共用
      preview_skeleton.dart    # stale bytes 优先 + 首次 fallback widget canvas
      preview_full_screen_dialog.dart  # Dialog.fullscreen + InteractiveViewer

修改：
  data/repositories/export_repository_impl.dart  # _processOne 调 processExportBytes、
                                                  # 新增 persistOnly(...)
  domain/repositories/export_repository.dart     # 接口加 persistOnly(...)
  presentation/providers/export_controller.dart  # save() 先查 cache 命中跳 _processOne
  presentation/screens/export_screen.dart        # 顶部插入 PreviewCard
```

### 关键决策汇总（详细 ADR 见 Subtask A 的 PRD §Decision）

1. **决策 1（预览源）**：真实导出渲染（B）
2. **决策 2（Grid 呈现）**：水平滚动 thumbnail（A）
3. **决策 3（长图交互）**：缩略 + 点击全屏 Dialog（D）
4. **决策 4（布局位置）**：预览顶部跨行（A）
5. **加分项**：预估大小标签 + 失败重试 + 保存中暂停 + 骨架占位（全部纳入）
6. **决策 D1（provider 返回类型）**：`NotifierProvider<PreviewState>`，**不是** `AsyncNotifier<PreviewState>`
7. **决策 D2（source 生命周期）**：controller 内部拉 + `editor.state.hashCode` 作 cache 键
8. **决策 D3（公共函数）**：`processExportBytes`（中性命名，命名参数）
9. **决策 D4（骨架）**：`PreviewLoading.staleBytes` 优先，首次 fallback widget canvas
10. **决策 D5（refresh）**：保守，Loading 时忽略，生效时绕两层缓存
11. **决策 D6（可测试性）**：`typedef ProcessBytesFn` + `processBytesFnProvider` 注入
12. **决策 D7（save 复用 cache）**：抽 `processedBytesCacheProvider`，save 命中跳 isolate

### Provider 拓扑

```
watermarkConfigProvider ───┐
exportControllerProvider ───┼─► previewControllerProvider
currentExportSourceKindProvider ─┤   (NotifierProvider<PreviewState>)
stitchEditorControllerProvider ──┤   内部：
gridEditorControllerProvider ────┘   - source bytes 拉取（editor.hashCode 缓存）
                                     - 300ms debounce
                                     - read processBytesFnProvider
                                     - 命中 processedBytesCacheProvider 跳 isolate
                                     - 写入 processedBytesCacheProvider
                                     - isSaving 暂停门
                                       │
                                       ▼
                                  PreviewCard widget
                                  (单层 switch 分派)

ExportController.save() ────► 查 processedBytesCacheProvider
                                 ├─ 命中：拿 bytes 调 repository.persistOnly()
                                 └─ 未命中：走原 exportAndSave() 路径
```

### 渲染管线复用（不再造轮子）

现有 `_processOneInIsolate` 已做 `applyWatermark + encodeForExport` + isolate-safe + `compute()`。
Subtask A 的工作只是把它**提到公共文件 + 改 public 命名**，不是从零写。
缓存键基于 `editorStateHash`（**不是** `sourceBytesIdentityHash`，因为 render() 每次返回新 `Uint8List`）。

## Decision (ADR-lite)

### 决策 1：预览源策略 → **B 真实导出渲染**

**Context**：导出页面需要让用户保存前确认最终效果。可选 A（widget 轻量预览）、
B（真实管线渲染）、C（渐进式混合）。

**Decision**：采用 **B**——预览走真正的导出管线
（`render` → `applyWatermark` → `encodeForExport`），所见即所得。

**Consequences**：
- ✅ 水印效果、JPG 压缩痕迹、格式差异都能真实可见
- ✅ 实现简洁，不需要管理两套渲染源 + 切换动效
- ⚠️ 首屏需等待 0.5~2s（视图片大小），需要 loading 占位
- ⚠️ 配置变化要 debounce（建议 300ms）避免连续触发
- ⚠️ 需要缓存最近一次预览，避免 size class 切换、`_ExportBody` 重建时白屏
- 关键性能点：单独的 `Timeline.startSync('export.preview')` 区分于 `export.save`

### 决策 2：Grid 多子图呈现 → **A 水平滚动 thumbnail**

**Context**：Grid 模式有 2~9 张子图（GridType.g1x2~g3x3），需要在预览区呈现。
可选 A（水平滚动 thumbnail）、B（网格还原）、C（仅首张代表）。

**Decision**：采用 **A**——所有子图横向 ListView 排列，可滑动浏览。

**Consequences**：
- ✅ 每张独立看水印位置（per-cell 水印的关键确认）
- ✅ 与"会生成 N 个文件"的产品认知一致
- ✅ 实现简单：`SizedBox(height: H, child: ListView.builder(scrollDirection: horizontal))`
- ⚠️ 可加分页指示器或滚动指示器，提示"有更多内容可滑动"

### 决策 3：长图预览交互 → **D 缩略 + 点击全屏**

**Context**：长拼接图高度可能是宽度的 5~20+ 倍。可选 A（仅缩略）、B（区内可滚）、
D（缩略 + 点击全屏）。

**Decision**：采用 **D**——预览区固定高度（如 240dp）BoxFit.contain 缩略；
点击后弹出 `Dialog`（`InteractiveViewer` 支持双指缩放 + 上下滚动）。

**Consequences**：
- ✅ 默认占位可控，不喧宾夺主
- ✅ 用户能查看原尺寸细节（水印文字、压缩痕迹）
- ✅ Material You 常见交互模式（与系统相册行为一致）
- ⚠️ 需新增一个 `PreviewFullScreenDialog`，增加一个 widget 文件
- ⚠️ 用 Dialog 而非 push 路由——避免污染路由栈，全屏查看属于"次级附属"交互

### 决策 4：响应式布局位置 → **A 预览顶部跨行**

**Context**：现有 compact 单列、medium+ 两列布局。需要决定预览放在哪个层级。

**Decision**：采用 **A**——预览始终位于顶部：
- compact：Preview → FormatQuality → Watermark → Save → Disclaimer
- medium+：Preview 跨整行 → [FormatQuality | Watermark] → Save → Disclaimer

**Consequences**：
- ✅ 与现有 `_ExportBody` 的 Column 结构最兼容（仅在最顶插入新行）
- ✅ 用户进入页面"先看效果，再调配置，再保存"的心智模型
- ✅ Save CTA 保持在底部，与现有跨 size class 全宽行为不冲突
- ⚠️ medium+ 大屏时预览高度受限（240dp）可能略显单调——靠"点击全屏"补足细节查看

### 决策 5（加分项打包）：MVP 全纳入

预估大小标签、失败降级 + 重试、保存中暂停、骨架占位 —— 四项全部进 MVP。
所有加分项共享同一个 `previewControllerProvider`，无新增 provider；
仅在 widget 层做状态分派和文案适配。

## Technical Notes

- 现有渲染入口可复用：
  - `stitchEditorControllerProvider.notifier.render()` → `Uint8List`（PNG）
  - `gridEditorControllerProvider.notifier.renderCells()` → `List<Uint8List>`
  - 需提取 `previewExportBytes(...)` 复用 `ExportRepositoryImpl._processOne` 的水印 + 编码逻辑
- 防抖实现：`AsyncNotifier` + `Timer` 取消重入；测试用 `FakeAsync` 验证
- 缓存键：`(sourceKind, watermarkConfigHash, format, quality, sourceBytesIdentityHash)`
- 全屏 Dialog 使用 `showDialog(barrierDismissible: true)` + `InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4.0)`
- 骨架占位 widget 直接复用编辑器组件，必要时包一层 `Opacity(0.6)` 让"未完成"语义可见

## Research References

（无需外部研究：渲染管线、Riverpod、Flutter 路由 / Dialog 均为已熟悉的本地模式）
