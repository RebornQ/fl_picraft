# fix: 导出保存按钮卡顿 UI 线程

## Goal

修复导出页面（`/export`）点击「保存至相册 / 保存到本地」按钮时，**主 UI 线程被
长时间阻塞**的体感卡顿问题：按钮按下后界面无法重绘 / 滚动，直到系统保存弹窗
（`gal` / `file_picker` / 浏览器下载）弹出才恢复。

> 已有 [`ExportState.isSaving`] 状态可让按钮显示加载态，但因为主 isolate 正在
> 跑 CPU 工作，状态变更 → 重绘的帧根本来不及调度，所以"loading 不显示、按钮
> 不变灰"。

## What I already know

### 卡顿路径（已读代码确认）

`SaveActionButton._onSavePressed`
→ `ExportController.save()` (`lib/features/export/presentation/providers/export_controller.dart:70`)
→ `ref.read(exportRepositoryProvider).exportAndSave(request)`
→ `ExportRepositoryImpl._exportSingle` / `_exportGrid`
→ **`_processOne(bytes, request)`** （`export_repository_impl.dart:140-143`）

```dart
Future<Uint8List> _processOne(Uint8List bytes, ExportRequest req) async {
  final watermarked = await applyWatermark(bytes, req.watermark);   // ← 主 isolate
  return encodeForExport(watermarked, req.format, quality: req.quality); // ← 主 isolate
}
```

### 两个明确的主 isolate CPU 阻塞点

1. **`applyWatermark`**（`lib/features/export/data/watermark_renderer.dart:23`）
   - 函数签名是 `async`，内部却**没有任何 await 异步点**
   - 同步操作：`img.decodeImage` → `img.drawString` ×2 → `_encodeMatching`
   - **函数已是 isolate-safe**（纯 `package:image`，无 `dart:ui`），spec 里也已
     在 `.trellis/spec/frontend/directory-structure.md:281-283` 里给出标准用法
     "caller: `await compute(_applyWatermarkEntry, request);`"，但当前 caller
     没遵守
2. **`encodeForExport`**（`lib/features/export/data/image_encoder.dart:30`）
   - 同步函数：`img.decodeImage` → `img.encodePng` / `img.encodeJpg`
   - 注释已写明 "Callers may invoke this through `compute()` for heavy images"
   - 当前 caller 也没走 `compute`

### 冗余的重复 decode/encode

| Stage | 位置 | Decode | Encode |
|-------|------|--------|--------|
| 1. Renderer | isolate（`stitch_image_renderer` / `grid_image_renderer`） | 各 source bytes ×1 | composite ×1 (PNG/JPG) |
| 2. Watermark | **主 isolate** | composite ×1 | watermarked ×1 |
| 3. Encode | **主 isolate** | watermarked ×1 | final ×1 (PNG/JPG) |

主线程**每张图要做 2 次 decode + 2 次 encode**。9 宫格场景就是 **18 次 decode +
18 次 encode** 串行在 UI 线程跑——这才是用户感知到「点了就卡到弹窗出来」的根因。

### 既有 isolate 基础设施

- `stitch_image_renderer.dart:34` 已用 `compute(_renderInIsolate, request)`
- `grid_image_renderer.dart:43` 已用 `compute(_renderInIsolate, request)`
- 两者都有 `Timeline.startSync` 埋点，DevTools 可视化
- 两者都有 "compute 失败时 fallback 到同步路径"（兼容 pure-Dart 单测）

### 相关 spec / 约定

- `.trellis/spec/frontend/directory-structure.md` → "Pattern: Isolate-safe
  rasterizer in `data/`" 已经规定了 isolate-safe 函数的调用契约
- `.trellis/spec/frontend/quality-guidelines.md`（Timeline markers 约定）

## Assumptions (temporary)

- 用户能感知到的卡顿主要发生在 step 2 + step 3（watermark + 二次 encode），因为
  step 1 已经在 isolate 里
- 单图（stitch）卡顿弱于 grid（grid 9 宫格要循环 9 次主线程 process）
- 卡顿不仅出现在大图（>2MP）——`encodeForExport` 对任何尺寸图都会走一次完整
  decode + encode

## Open Questions

> 全部已收敛 — 见 Decision (ADR-lite) 与 Out of Scope。

## Requirements (evolving)

- 点击保存按钮后，主 UI isolate 必须立刻让出，至少能完成一帧重绘（保证 isSaving
  loading 态可见）
- 单图 stitch 与多图 grid 路径都要修——`_exportSingle` 与 `_exportGrid` 都走
  `_processOne`，问题对两路径都成立
- 修复后**输出字节必须 1:1 等价**于修复前（PNG 无损 round-trip / JPG 同 quality
  的 deterministic encode）——已有的 `watermark_renderer_test.dart`、
  `image_encoder_test.dart` 必须继续通过
- 单测层面要新增「走 compute 路径」的 assert（spec validation #2 已要求）

## Acceptance Criteria (evolving)

- [ ] 9 宫格 + 启用水印场景，点击保存后第一帧（≤ 16ms）内按钮进入 loading 态
- [ ] DevTools timeline 看不到主 isolate 在 `_processOne` 期间的长帧（>16ms）
- [ ] 保存最终结果 bytes 与修复前 deterministic 相等（snapshot test 不破）
- [ ] `flutter analyze` clean；`flutter test` 全绿
- [ ] 新增 isolate-path 集成测试覆盖 `_processOne`（或其拆分等价物）

## Definition of Done (team quality bar)

- Tests added/updated（含 isolate-path validation）
- Lint / typecheck / CI green
- DevTools timeline 截图或 markers 验证（写进 PR 说明）
- 若新增 spec 模式（如「`data/` 调用方必须走 compute」的强制约定），同步更新
  `.trellis/spec/frontend/directory-structure.md`

## Out of Scope (explicit)

- 重写底层 renderer（stitch/grid 已在 isolate，不动）
- 平台保存 datasource（gal / file_picker / web blob）的优化
- 渲染算法本身的优化（不改 watermark 的字体、不改 encode 的压缩参数）
- 同时增加 cancel 保存的能力（虽然 isolate 拆出后理论可行，但 MVP 不做）
- **UI 增强**（全屏遮罩 / 进度文字 / 取消按钮）— 修完主 iso 卡顿后，既有
  `isSaving` 让按钮变灰 + spinner 已足够 affordance；其余可后续单独立任务
- **spec 措辞收紧**（"may invoke through compute" → "MUST"）— 本任务只修
  代码层 bug，不动 spec；若后续再出现同类回归再补
- **消除冗余 decode/encode**（Approach C 的优化目标）— 留待后续 profile 驱动
  的性能任务

## Technical Approach (proposed — to be confirmed)

### Approach A — Wrap `_processOne` in compute（Recommended，最小可用）

- 在 `export_repository_impl.dart` 里加 top-level 函数：

  ```dart
  // top-level，可作为 compute 入口
  Future<Uint8List> _processOneInIsolate(_ProcessOneRequest r) async {
    final watermarked = await applyWatermark(r.bytes, r.watermark);
    return encodeForExport(watermarked, r.format, quality: r.quality);
  }
  ```
- `_processOne` 改成：

  ```dart
  Future<Uint8List> _processOne(Uint8List bytes, ExportRequest req) async {
    final request = _ProcessOneRequest(
      bytes: bytes, watermark: req.watermark,
      format: req.format, quality: req.quality,
    );
    try {
      return await compute(_processOneInIsolate, request);
    } catch (_) {
      // 与 stitch/grid renderer 一致的 fallback：纯 Dart 单测无 binding
      return _processOneInIsolate(request);
    }
  }
  ```
- **优点**：改动面最小（仅 1 个文件 + 一个新的 request DTO + 测试），对齐既有
  stitch/grid renderer 的 isolate 模式
- **缺点**：保留了「主 isolate 拿到 renderer bytes → 再传进新 isolate → 又
  decode/encode」的冗余拷贝；性能比 C 差但比现状好得多

### Approach B — 分别 compute applyWatermark + encodeForExport

- 两次 isolate hop（一次水印，一次编码）
- 拷贝/编解码次数与 A 相同
- 多一次 isolate 序列化开销，没明显优点 → ❌ 不推荐

### Approach C — Renderer 内联水印 + 终态编码

- 在 `stitch_image_renderer._renderInIsolate` / `grid_image_renderer._renderInIsolate`
  里直接调用 `applyWatermark` + 输出 `request.format` 的 bytes
- 一次 isolate hop 完成「decode → composite → watermark → format encode」
- **优点**：消除 step 2/3 的重复 decode/encode，性能上限最高
- **缺点**：
  - 需要把 `WatermarkConfig` + `ExportFormat` + `quality` 沿 `StitchRenderRequest`
    / `GridRenderRequest` 一路下沉，渲染器从「pure stitch」变成「stitch +
    export」语义不纯
  - 现有 `StitchEditorController.render()` 也被其他场景（如预览）调用，参数变化
    会扩散
  - 跨 feature 边界（grid feature 的 renderer 突然依赖 export feature 的
    watermark）

### Recommendation

**Approach A**。理由：
1. 改动只在 `export` feature 内部，不污染上游 renderer 语义
2. 与现有 stitch/grid 的 isolate 模式 1:1 对齐，新成员一眼就能理解
3. 修完后 UI 已经流畅，冗余 decode/encode 是「再优化」议题而非「修 bug」议题——
   后续若 profile 显示瓶颈仍在，再单独立 Approach C 的优化任务

> 选 A 的话本任务无需拆 subtask（一个 PR 内可完成）。
> 选 C 的话建议拆 2-3 个 subtask（每个 renderer 单独 1 个，外加最终接线 1 个）。

## Decision (ADR-lite)

**Context**：
导出页面 `SaveActionButton` 触发的 `ExportRepositoryImpl._processOne` 在主
isolate 同步执行 `applyWatermark` + `encodeForExport`，每张图 2 次 decode +
2 次 encode；9 宫格场景累计 18 次。主 isolate 长帧导致 `isSaving` loading 态
无机会重绘，用户感知为「点了就卡到弹窗出来」。spec
（`.trellis/spec/frontend/directory-structure.md` → Isolate-safe rasterizer in
`data/`）已经定义了「caller 通过 `compute(...)` 调用」的契约，但当前 caller 未
遵守。

**Decision**：选用 **Approach A** — 在 `ExportRepositoryImpl` 内新增 top-level
`_processOneInIsolate` 入口函数 + `_ProcessOneRequest` DTO，将 `_processOne`
改造为 `compute(_processOneInIsolate, request)`，沿用 stitch/grid renderer
现有的 "compute + 单测 fallback" 模式。

**Consequences**：
- ✅ 主 UI isolate 立刻让出，第一帧即可渲染 isSaving loading 态
- ✅ 改动仅限 `export` feature 内 1 个仓库实现文件 + 1 个 DTO + 1 个测试文件
- ✅ 与 `stitch_image_renderer` / `grid_image_renderer` 的 isolate 模式 1:1 对齐
- ⚠️  保留「主 iso 拿到 renderer bytes → 新 iso decode/encode」的冗余拷贝；
  若后续 profile 显示 isolate 序列化开销显著，再立独立任务做 Approach C
- ⚠️  spec 措辞仍是 "may invoke through compute" 而非 "MUST"；不在本任务收紧，
  依赖 PR review + 本次 incident 文档作为非正式约束

## Research References

> _（无需外部研究，所有上下文均来自 repo 与 spec。）_

## Technical Notes

### 关键文件

- `lib/features/export/data/repositories/export_repository_impl.dart` —
  `_processOne`（line 140-143）是改动核心
- `lib/features/export/data/watermark_renderer.dart` — 已 isolate-safe，不需改
- `lib/features/export/data/image_encoder.dart` — 已 isolate-safe，不需改
- `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart:34` —
  既有 compute 模式参考
- `lib/features/grid/data/renderers/grid_image_renderer.dart:43` — 同上
- `test/features/export/data/watermark_renderer_test.dart` — 现有 snapshot/确定性
  测试，新方案不能破

### 待新增/调整测试

- `test/features/export/data/repositories/export_repository_impl_test.dart`
  （若不存在则新建）覆盖：
  - `_processOne` 走 compute 路径（依据 spec validation #2，新增一个 isolate-path 测试）
  - 字节确定性：相同 input/config 多次调用产生相同 output
- 既有 `watermark_renderer_test.dart` / `image_encoder_test.dart` 全部继续通过

### Spec 更新（视情况）

若选定 Approach A 后想固化「`data/` isolate-safe rasterizer **必须**通过 compute
调用」的约定，更新 `.trellis/spec/frontend/directory-structure.md` 的对应小节，
把现有"Callers may invoke through `compute(...)`"措辞收紧为"Callers MUST"。
