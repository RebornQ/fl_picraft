# 预览渲染基础设施（Subtask A of 05-20-export-page-preview）

> 父任务：[`05-20-export-page-preview/prd.md`](../05-20-export-page-preview/prd.md)
> 兄弟任务：[`05-20-preview-ui/prd.md`](../05-20-preview-ui/prd.md)

## Goal

为导出页面预览图的"真实渲染"流程铺设底层基础设施：抽取共享的渲染管线、
搭建带防抖+缓存+暂停门的 Riverpod controller、定义 sealed 状态类型、
**让 save 路径也复用 preview 的 result cache**。
此 subtask 不涉及任何 UI，纯数据/逻辑层；Subtask B 在此之上做 widget 集成。

## 与现有代码的关键差距

> 在 grill 阶段已通过代码核对发现：`export_repository_impl.dart` 已存在私有的
> `_processOneInIsolate(_ProcessOneRequest r)`（top-level + Request 对象 + 已通过 `compute()`
> 调用 + 已 isolate-safe）。本 subtask 的"渲染管线"工作**不是从零造**，而是：
>
> 1. 把私有函数提到公共 `preview_renderer.dart`、改 public 命名为 `processExportBytes`
> 2. 重构 `ExportRepositoryImpl._processOne` 为薄包装
> 3. 加 cache 让 save 路径命中时跳过 isolate hop
>
> 缓存键基于 `editorStateHash`（**不是** `sourceBytesIdentityHash`，因为 stitch/grid
> `render()` 每次返回新 `Uint8List`，identity 永不命中）。
> `StitchEditorState.hashCode` / `GridEditorState.hashCode` 已实现完整字段哈希，直接复用。

## Requirements

### 1. 公共渲染函数（`lib/features/export/data/preview_renderer.dart`）

```dart
typedef ProcessBytesFn = Future<Uint8List> Function({
  required Uint8List source,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
});

/// 生产实现：内部 compute(_processExportInIsolate, _ProcessExportRequest(...))
Future<Uint8List> processExportBytes({
  required Uint8List source,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
});
```

- 中性命名（不带 preview 字样）——save 路径也用
- pure-Dart，无 `dart:ui`，isolate-safe
- 重构 `ExportRepositoryImpl._processOne` 调用此函数，删除本地 `_ProcessOneRequest` / `_processOneInIsolate`

### 2. 可测试性：依赖注入（`processBytesFnProvider`）

```dart
final processBytesFnProvider = Provider<ProcessBytesFn>(
  (ref) => processExportBytes,
);
```

- previewController 通过 `ref.read(processBytesFnProvider)` 拿函数，**不直接调** `processExportBytes`
- 测试时 `ProviderScope(overrides: [processBytesFnProvider.overrideWithValue(fakeFn)])`，
  fake 是同步函数，可计数、可 `FakeAsync` 控制时间
- 解决"compute() 在 isolate 里 → FakeAsync 失效"的硬伤

### 3. result cache（`processedBytesCacheProvider`）

```dart
class ProcessedBytesCache {
  List<Uint8List>? read(int key);
  void write(int key, List<Uint8List> bytes);
  void invalidate();
}

int computeProcessedBytesCacheKey({
  required ExportSourceKind kind,
  required int editorStateHash,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
});

final processedBytesCacheProvider =
    NotifierProvider<ProcessedBytesCacheNotifier, ProcessedBytesCache>(...);
```

- cache 容量上限（如 4 条 LRU）防止内存膨胀
- 读写双方：
  - **写入者**：`PreviewController` 每次成功渲染后写入
  - **读取者**：`PreviewController`（命中跳过 isolate）+ `ExportController.save`（命中跳过 `_processOne`）
- 缓存键由 `computeProcessedBytesCacheKey(...)` 计算（任何调用方共用）

### 4. PreviewState sealed class

```dart
sealed class PreviewState {}
class PreviewEmpty extends PreviewState { const PreviewEmpty(); }
class PreviewLoading extends PreviewState {
  final List<Uint8List>? staleBytes;  // 首次进页 null；从 Ready 转入时携带
  const PreviewLoading({this.staleBytes});
}
class PreviewReady extends PreviewState {
  final List<Uint8List> bytes;
  final int totalSizeBytes;  // grid 多子图时为字节数之和
  const PreviewReady({required this.bytes, required this.totalSizeBytes});
}
class PreviewError extends PreviewState {
  final String message;
  final List<Uint8List>? staleBytes;  // 失败时保留 stale 给"重试"路径占位
  const PreviewError({required this.message, this.staleBytes});
}
```

### 5. `previewControllerProvider`：`NotifierProvider<PreviewController, PreviewState>`

**不要用 `AsyncNotifierProvider<_, PreviewState>`**——`AsyncValue` 自带 loading/error 会与 sealed
重复表达，UI 消费侧 4×4 笛卡尔积。Riverpod 内部仍可用 `Future`，但不向消费侧暴露 `AsyncValue`。

**Controller 行为**：

- **依赖**：监听 `watermarkConfigProvider` / `exportControllerProvider.format+quality` /
  `currentExportSourceKindProvider` / `stitchEditorControllerProvider` / `gridEditorControllerProvider`
- **source bytes 生命周期**：controller 内部拉，以 `editor.state.hashCode` 为索引；
  editor state 哈希不变 → 复用已拉取的 source，**不重跑 source isolate**；
  editor state 哈希变化 → 重拉 source（用户回去改编辑器再回来）
- **防抖**：配置变化后 300ms 内的连续变更只触发一次渲染（`Timer? _debounce`）
- **result cache**：以 `computeProcessedBytesCacheKey(...)` 为 key，
  通过 `processedBytesCacheProvider` 共享读写
- **保存中暂停门**：当 `ExportState.isSaving == true` 时**跳过新的渲染调度**；
  `isSaving` 切回 false 时，若当前输入的缓存键与最近一次成功渲染不同，自动触发一次新渲染
- **refresh() 方法**：
  - 仅对 `PreviewError` / `PreviewReady` 生效；`PreviewLoading` 状态下**忽略**（避免任务重叠）；
    `PreviewEmpty` 状态下也忽略（无可预览源）
  - 生效时**绕两层缓存**：editor-state 缓存（重拉 source）+ result 缓存（重走 watermark+encode），
    且 immediate（跳过 300ms 防抖窗）

### 6. `ExportController.save()` 改造（cache hit 跳过 isolate）

- 在调用 `exportRepositoryProvider.exportAndSave(...)` **之前**：
  1. 算 `computeProcessedBytesCacheKey(...)`
  2. 查 `processedBytesCacheProvider`
  3. 命中 → 直接拿 processed bytes，调用 repository 的新 `persistOnly(...)` 路径（不再跑 `_processOne`）
  4. 未命中 → 走原 `exportAndSave(...)` 路径
- `ExportRepository` 接口新增 `persistOnly(...)` 方法（接收已处理的 bytes 直接走 `_persist`）

### 7. Timeline 标记

- **不要**在 `processExportBytes` 自身打 Timeline——由调用方各自打：
  - preview 路径：`Timeline.startSync('export.preview')` / `finishSync()` 包住 controller 内调用
  - save 路径：保留现有 `Timeline.startSync('export.process')` 行为
- 这样 DevTools 能区分 preview 与 save 两条路径耗时

### 8. 测试覆盖

8.1 **`preview_renderer_test.dart`**：契约测试
   - 水印关 + PNG → 字节与 `encodeForExport` 一致
   - 水印开 + JPG → 字节包含水印且 JPG 解码后尺寸正确

8.2 **`processed_bytes_cache_test.dart`**：cache 行为
   - LRU 淘汰：写入超过容量上限时丢弃最旧的
   - `computeProcessedBytesCacheKey` 对相同输入产生相同 key、不同 watermark 产生不同 key

8.3 **`preview_controller_test.dart`**（用 `overrideWithValue(fakeFn)` + `FakeAsync`）
   - 防抖：300ms 内 5 次配置变更只触发 1 次 fakeFn 调用
   - 缓存：相同 (sourceKind, editorHash, wm, fmt, q) 第二次调用 fakeFn 计数仍为 1
   - 保存中暂停：`isSaving=true` 期间配置变化不触发 fakeFn；切回 false + 输入变化时触发 1 次
   - 失败传播：fakeFn 抛错时 state 进入 `PreviewError`，带上 stale bytes（若有）
   - refresh() 在 Loading 状态被忽略：fakeFn 调用计数不增

8.4 **`export_controller_save_cache_hit_test.dart`**：save cache hit
   - cache 已写入 → `ExportController.save()` 不调用 fakeFn，直接走 `persistOnly`
   - cache 未命中 → 走原 `exportAndSave` 路径，fakeFn 被调用一次

## Acceptance Criteria

- [ ] `lib/features/export/data/preview_renderer.dart` 暴露 `processExportBytes(...)`
      + `typedef ProcessBytesFn` + `_ProcessExportRequest` + `_processExportInIsolate`
- [ ] `processBytesFnProvider` 定义并被 previewController 注入
- [ ] `ExportRepositoryImpl._processOne` 重构调用 `processExportBytes`，删除本地 `_ProcessOneRequest` / `_processOneInIsolate`
- [ ] `ExportRepository` 接口 + 实现新增 `persistOnly(...)` 方法
- [ ] `PreviewState` sealed 4 个变体（Empty / Loading{staleBytes?} / Ready{bytes,totalSizeBytes} / Error{message, staleBytes?}）
- [ ] `previewControllerProvider` 是 `NotifierProvider<_, PreviewState>`，不暴露 `AsyncValue`
- [ ] `processedBytesCacheProvider` 存在，含 LRU 容量上限 + invalidate()
- [ ] `ExportController.save()` 先查 cache，命中跳 `_processOne` 走 `persistOnly`
- [ ] 防抖 300ms / source 复用 / result cache / save 复用 / 保存中暂停 / refresh 语义全部实现
- [ ] Timeline 由调用方各自打（`export.preview` / `export.process`），processExportBytes 自身不打
- [ ] 全部 4 组测试（renderer / cache / controller / save cache hit）通过
- [ ] `flutter analyze` / `dart format .` / `flutter test` 全部 green
- [ ] 无新增 widget 文件（UI 由 Subtask B 负责）

## Definition of Done

- 现有 export 测试（`export_screen_test`、`export_repository_impl_test` 等）全部通过——不引入回归
- save 路径在 cache 命中时**无 isolate hop**（DevTools 可验证：`export.process` 区段消失）
- 提交独立 PR，PR 描述写明：
  - 为 Subtask B（UI）铺路
  - 顺带优化 save 路径（cache hit 时跳过 1~2s isolate hop）
  - 不引入任何用户可见 UI 变化

## Out of Scope

- 任何 widget / UI 代码（属于 Subtask B）
- 修改 `export_screen.dart` 布局
- 修改 `applyWatermark` / `encodeForExport` 内部实现
- 跨 session 持久化 cache（cache 仅活在 Riverpod container 生命期内）

## Decision (ADR-lite)

### D1：previewControllerProvider 返回类型 → `NotifierProvider<PreviewState>`

**Context**：sealed PreviewState 自己含 Loading/Error；若再包 AsyncValue 会双重表达，UI 4×4 笛卡尔积。

**Decision**：用 `NotifierProvider<PreviewController, PreviewState>`；Riverpod 内部仍用 `Future`，
但消费侧只见 `PreviewState`，单层 `switch` 穷尽。

**Consequences**：消费侧代码极简；测试时 controller 内部依赖（如 processBytesFn）改为
provider 注入即可控制。

### D2：source bytes 生命周期 → controller 内部拉 + editor-state 哈希作键

**Context**：stitch/grid `render()` 每次返回新 `Uint8List`，`identityHashCode(bytes)` 作 cache key
**永不命中**。

**Decision**：controller 持有 `_cachedSource: List<Uint8List>?` + `_cachedEditorStateHash: int?`；
editor state 哈希不变时复用已拉 source。`StitchEditorState.hashCode` / `GridEditorState.hashCode` 现成可用。

**Consequences**：缓存真实命中；测试用现成 hashCode 即可，无需额外哈希实现。

### D3：公共函数命名 → `processExportBytes`（命名参数）

**Context**：现有 `_processOneInIsolate` 已做 watermark+encode；要提到公共模块。PRD 原命名
`previewExportBytes` 误导（暗示"仅预览"），但 save 也调它。

**Decision**：中性命名 `processExportBytes(...)` + 命名参数（API 友好）；内部组装 private Request
对象传 `compute()`。

**Consequences**：调用方语义清晰；新增使用方（如 share、batch）不会因命名而困惑。

### D4：PreviewLoading 骨架表达 → stale bytes 优先，首次 fallback widget canvas

**Context**：父 PRD 决定 widget canvas 作骨架；Subtask A 想用 stale bytes 作过渡。

**Decision**：`PreviewLoading({List<Uint8List>? staleBytes})`；UI 优先用 stale，无 stale 时
fallback 到 widget canvas。

**Consequences**：调水印滑块时预览不"闪回无水印 canvas"，过渡顺滑；首次进页仍有完整骨架。

### D5：refresh() 语义 → 保守、Loading 时忽略

**Context**：refresh 在 Loading 时被点会重叠 isolate 任务；"绕缓存"是绕一层还是两层不清。

**Decision**：仅对 Ready/Error 生效；绕两层缓存（source + result）；immediate（跳防抖）。

**Consequences**：UI 重试按钮行为可预测；不会因连点而排队多个 isolate 任务。

### D6：可测试性 → typedef + Provider 注入

**Context**：`compute()` 在 isolate 跑，`FakeAsync` 控制不了；PRD 原 AC 不可达。

**Decision**：抽 `typedef ProcessBytesFn` + `processBytesFnProvider`；测试 override 为同步 fake。

**Consequences**：所有时序 / 计数 AC 可用 `FakeAsync` 验证；测试快、稳。

### D7：save 复用 preview cache → 抽公共 `processedBytesCacheProvider`

**Context**：preview 已渲染过相同输入时，save 再跑一次 isolate 浪费 1~2s。

**Decision**：抽 cache 为独立 provider；previewController 写入；
`ExportController.save` 先查 cache，命中跳 `_processOne` 走新 `persistOnly`。

**Consequences**：用户调好参数后点保存，瞬间响应；Subtask A 范围扩张 ~20%（新增 cache provider +
repository.persistOnly + ExportController.save 改造 + 对应测试）；但跨 subtask 边界仍清晰
（Subtask B 不需要改 save 路径）。

## Technical Notes

- `_ProcessExportRequest` 是 SendPort-transferable，仿现有 `_ProcessOneRequest` 形态
- 缓存键算法：`Object.hash(kind, editorStateHash, watermark.hashCode, format.index, quality)`
- LRU 实现：`LinkedHashMap` + `removeWhere`/`remove(first)` ；4 条上限足够
  （PNG/JPG × 5 个常用质量档 = 10 个组合，但大多用户只切 1~2 次）
- `ExportRepository.persistOnly(...)`：签名 `Future<SaveResult> persistOnly(List<Uint8List> processed, ExportFormat format)`
- 测试 fake：`fakeProcessBytesFn = ({...}) async => Uint8List.fromList([1,2,3]);` + 计数包装

## 与父任务/兄弟任务的契约

- 输出给 Subtask B 的 API：`previewControllerProvider`（返回 `PreviewState`，**不是** `AsyncValue<...>`）
- 输出给 save 路径（同 subtask 内）：`ExportController.save` 内部对接 cache，Subtask B 不需要改 save
- Subtask B 仅消费 `previewControllerProvider`，不绕过它直接调用渲染管线
