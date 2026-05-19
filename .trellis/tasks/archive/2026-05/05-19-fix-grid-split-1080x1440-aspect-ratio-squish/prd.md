# fix: 宫格切图导入 1080×1440 图片显示被压扁

## Goal

修复**宫格切图（Grid Split）**预览中、特定尺寸（典型 1080×1440 等含 EXIF 旋转 tag 的竖拍 JPEG）图片显示被横向/纵向压扁的视觉缺陷，并保证导出结果与预览一致、方向正确。

## What I already know

### 故障链路（已经在代码中确认）

1. **导入元数据来源** — `lib/features/image_import/data/utils/image_normalizer.dart::decodeImageMetadata`
   - 使用 `image` 包 `decoder.startDecode(bytes)` 仅读取文件 header 中的 SOF 维度
   - **不会**应用 EXIF Orientation tag — 因此对一张实际是「1440×1080 + Orientation=6（顺时针 90°）」的相机 JPEG，得到的是 raw `width=1440, height=1080`，与「用户看到的」竖图方向相反
   - 对 1080×1440 这种值，最常见的就是相机/手机拍摄的竖图（很多设备的输出格式）
2. **预览渲染** — `lib/features/grid/presentation/widgets/grid_preview_canvas.dart`
   - `sourceAspect = source.width / source.height` 取自 metadata（错误方向）
   - `Positioned(width: imgWidth, height: imgHeight) → Image.memory(fit: BoxFit.fill)`
   - **Flutter 的 `Image.memory` 走 `ui.instantiateImageCodec`，会自动应用 EXIF Orientation**——把图旋转回正
   - 结果：被旋转过的图被强行填进一个用「未旋转 raw 维度」算出来的矩形 → **视觉上压扁**
3. **导出渲染** — `lib/features/grid/data/renderers/grid_image_renderer.dart`
   - 用 `img.decodeImage(sourceBytes)` 解码 → **默认也不应用 EXIF**
   - 在 raw 坐标系下裁切并切片，导出的 cell PNG 是「未旋转」方向
   - 在 Flutter 端 `Image.memory` 显示导出 cell 时又会重新按 EXIF 旋转 → **导出结果方向异常 + 与预览不一致**（这是同一根因的另一个表现）
4. `image_picker.pickMultiImage` 默认不重编码，EXIF 完整保留；`file_picker` / 剪贴板 / 拖拽路径同理。
5. `image: ^4.3.0` 已提供 `img.bakeOrientation(...)` 工具，可一次性把 EXIF Orientation 烘焙进像素并清除 tag。

### 同一根因影响范围

- **宫格切图（Grid Split）预览** — 压扁（用户报的现象）
- **宫格切图导出 cells** — 方向错误 + 与预览不一致（隐性 bug，应一并修复）
- **长图拼接（Long Stitch）预览 / 导出** — 同样使用 `ImportedImage.width/height` + `Image.memory`，同根因，同样需要修
- **每格替换图（per-cell replacement）** — `cell_overlay.dart` 同样用 `replacement.width/height` + `BoxFit.fill`；如果替换图也是带 EXIF 的相机原片，也会压扁

## Assumptions (temporary)

- 修复点放在导入归一化层（`ImageNormalizer`）—— 把 orientation 烤进字节、并改写 metadata —— 是最小变更、影响范围最广、能修复**所有**下游用例的方式。
- 烘焙 orientation 后输出 JPEG/PNG 字节，体积变化基本可忽略；额外耗时仅在 orientation ≠ 1 的图片上发生（一次性 import 时刻）。
- 现有自动化测试都是 PNG/无 EXIF 路径，不会因此回归（待验证）。

## Open Questions

1. **修复范围** — 见下方 Approach 选项。

## Root Cause Summary (one line)

`ImportedImage.width/height` 来自不应用 EXIF 的 `image.startDecode`，而 Flutter `Image.memory` 显示时会应用 EXIF → 元数据与实际显示方向不一致，被 `BoxFit.fill` + 显式宽高拉伸成压扁。

## Feasible Approaches

### Approach A：在 import 归一化层 bake EXIF orientation（**Recommended**）

- 改动 `image_normalizer.dart`：
  - decode header 时**额外读取 orientation**（JPEG 走 `JpegDecoder` 的 `exif`；其他格式无影响）
  - 当 orientation ∉ {未设置, 1} 时：
    - 用 `img.decodeImage(bytes)` 全像素解码 → `img.bakeOrientation(image)` → 重新 `img.encodeJpg/encodePng` 出新字节
    - 新字节不再含 orientation tag，width/height 取自烘焙后图像
  - 因为全像素解码较重，沿用现有 `kDecodeIsolateThresholdBytes = 2MB` 阈值：≥2MB 走 `compute`，否则同步
- 影响范围：
  - 所有下游（预览/导出/替换图/长图）**自动修复**，无需各 feature 各自处理
  - `ImportedImage.bytes` 现在是「已正向化」的字节，metadata 与显示完全一致
- ✅ Pros：一处修复全员受益；预览与导出 byte-for-byte 对齐这一现有契约得以保持；与 Spec 中「`data/` 层负责解码归一化」的职责划分一致
- ⚠️ Cons：orientation ≠ 1 时多一次解码+编码；JPEG 重编码会有极轻微画质损失（可通过最高质量参数控制）

### Approach B：仅修复 metadata 维度（**不推荐**）

- 只读 orientation、swap `width/height`，不改字节
- 预览能修好（`Positioned` 给的是正确显示尺寸 + `Image.memory` 自动转）
- ❌ **导出 broken**：渲染器走 `img.decodeImage` 不应用 EXIF，仍在 raw 坐标系裁切，导出 cell 方向错乱
- 会留下「预览对、导出歪」的更糟的不一致

### Approach C：在各 feature 显示层用 `ui.Image` 实际尺寸做布局（**不推荐**）

- 在 `_PreviewSurface` 改为先异步 `decodeImageFromList(bytes)` 拿到正向化后的 `ui.Image`，用它的 `width/height` 而非 `ImportedImage.width/height`
- 还要把同步的 `cropRect` 计算改为异步
- ❌ 改动面广（grid preview / stitch preview / cell overlay / 渲染器都要改），新增异步态，且导出层仍要单独处理 → 复杂度爆炸

## Recommendation

**Approach A**。理由：
1. 一处归一化彻底消除「EXIF 在哪一层应用」的歧义，与现有「data 层归一化 / domain 层只信 metadata」的架构一致
2. 预览与导出共享同一份「已烤」字节，**不需要任何下游 feature 改代码**（也就不会回归）
3. 同时修复了用户未察觉的导出方向 bug

## Requirements

- R1：导入时若图片含 EXIF Orientation tag 且非 1，归一化层必须把方向烘焙进像素，输出 `ImportedImage.bytes`/`width`/`height` 均已正向化。
- R2：归一化输出对**所有**导入源（gallery / camera / clipboard / drag-drop）一致生效。
- R3：JPEG 重编码使用接近无损/高质量参数（避免画质退化）；PNG 走 PNG 重编码。
- R4：>= 2MB 的图片，烘焙仍在 isolate (`compute`) 内执行，不阻塞 UI。
- R5：宫格切图预览导入 1080×1440 竖图（带 Orientation=6）后，图片以正确长宽比显示，不再压扁。
- R6：宫格切图导出的 cell 图像方向与预览一致，且各 cell 的逻辑切分与用户在预览中看到的几何位置完全对应。
- R7：原本无 EXIF / orientation=1 的图片走快路径（不解码全像素、不重新编码）—— 零额外开销。

## Acceptance Criteria

- [ ] AC1：从相册导入一张「1080×1440 + EXIF Orientation=6」JPEG 到宫格切图，预览中图片纵横比为 1080:1440（或 1440:1080，取决于实际显示方向），**不出现压扁**。
- [ ] AC2：上述图片导出 2×2 cell，每个 cell 方向正确（与预览一致），任意 cell 用系统图库打开方向不歪。
- [ ] AC3：长图拼接（Long Stitch）导入同一张图，预览与导出方向一致、纵横比正确。
- [ ] AC4：宫格切图「点击 cell 替换」流程导入带 EXIF 的竖图，替换的 cell 不压扁。
- [ ] AC5：导入一张**无 EXIF** 的 PNG，import 耗时和修复前一致（不引入额外解码）。
- [ ] AC6：单元测试覆盖：(a) 带 orientation=6 的 JPEG → 烘焙后 width/height 已 swap、字节不再含 orientation tag；(b) orientation=1 的 JPEG → 字节未变、metadata 同旧；(c) PNG → 字节未变、metadata 同旧。
- [ ] AC7：`flutter analyze` 0 警告，`flutter test` 全绿，`dart format .` 已应用。

## Definition of Done

- 所有现有 grid / stitch / image_import widget test 通过
- 新增 normalizer EXIF 烤入测试（≥3 用例）
- 新增 grid preview 集成回归测试（mock 一张「方向错位」的 ImportedImage → 验证 layout 不压扁）
- 手动验证：在真机/模拟器导入实拍 EXIF 竖图，宫格预览与导出均正确
- PR 描述附压扁前后截图对比

## Out of Scope (explicit)

- 不修改 `image_picker` / `file_picker` / `super_clipboard` 等三方包配置项
- 不引入新的图像处理依赖（仅用现有 `image: ^4.3.0`）
- 不重构 `ImportedImage` schema（保持 `width/height` 字段语义不变，仅修正其值的来源）
- 不优化非压扁相关的渲染性能（例如 `Image.memory` 走 `MemoryImage` 缓存等议题）

## Technical Approach (initial sketch)

1. 扩展 `decodeImageMetadata` → 返回 `(width, height, mimeType, orientation)` 四元组
   - 对 `img.JpegDecoder`，读取 `info.exif.imageIfd.orientation`（image 包 4.x 接口）
   - 其他格式默认 1（无影响）
2. 新增 `ImageNormalizer._bakeOrientationIfNeeded(bytes, mimeType, orientation)`
   - orientation ∈ {2..8}：
     - `img.decodeImage(bytes)` → `img.bakeOrientation(image)`
     - 若 jpeg：`img.encodeJpg(baked, quality: 95)`；若 png：`img.encodePng(baked)`
     - 返回新字节 + 新 width/height
   - 否则原样返回
3. `normalize(...)` 内：先 metadata → 若 orientation ≠ 1，走 isolate-aware bake → 用最终结果填 `ImportedImage`
4. 测试：构造 EXIF 写入的 JPEG fixture（用 `image` 包写入 orientation tag）做 round-trip 验证

## Subtasks (proposed)

经评估**保持单任务**推进 —— 核心代码改动只集中在 `image_normalizer.dart`，拆 subtask 反而增加上下文切换成本。实现内部仍按以下三步推进（不拆 task，写在 PRD 作为执行清单）：

1. **Step 1 · normalizer 骨架** — `decodeImageMetadata` 返回 orientation；新增 `_bakeOrientationIfNeeded` 顶层函数（必须满足 isolate-safe 约定）+ 配套单元测试（无 UI 依赖）。
2. **Step 2 · normalize 接入** — `ImageNormalizer.normalize(...)` 串起「读 metadata → 必要时 isolate-aware bake → 输出新 bytes/width/height」；新增跨导入源 e2e 用例。
3. **Step 3 · 回归验证** — grid / stitch widget 测试新增「方向错位 ImportedImage」回归用例；本地真机/模拟器手动复测 1080×1440 实拍 JPEG；PR 截图归档。

> 若 Step 1 完成后发现 image 包 EXIF API 比预期复杂，再考虑独立 subtask；目前不拆。

## Decision (ADR-lite)

- **Context**：宫格切图导入 1080×1440 等含 EXIF Orientation tag 的竖图后显示被压扁；同根因还会引发导出 cell 方向错误。需要选择修复点的层级。
- **Decision**：采纳 Approach A —— 在 `image_normalizer.dart` 一处烘焙 EXIF Orientation 并改写 metadata。
- **Consequences**：
  - ✅ 所有下游 feature（grid 预览/导出、long stitch、cell 替换）零改动自动受益
  - ✅ 预览与导出共享同一份已正向化字节，保持现有 byte-for-byte 对齐契约
  - ⚠️ orientation ≠ 1 的 JPEG 需要全像素解码 + 重编码（沿用 `kDecodeIsolateThresholdBytes = 2MB` 阈值走 `compute`，UI 不阻塞）
  - ⚠️ JPEG 重编码使用 `quality: 95` 以最小化画质损失（仍非无损，已纳入 Out-of-Scope 的「画质优化」议题外）
  - 🔒 烘焙函数必须遵守 `.trellis/spec/frontend/directory-structure.md` → "Pattern: Isolate-safe rasterizer in `data/`" —— 顶层函数 / 不依赖 Flutter binding / 不访问 BuildContext

## Technical Notes

- 文件清单（实际需要触碰）：
  - `lib/features/image_import/data/utils/image_normalizer.dart`（主要改动）
  - `test/features/image_import/data/utils/image_normalizer_test.dart`（新增/扩展）
  - `test/features/grid/presentation/widgets/grid_preview_canvas_test.dart`（新增回归用例）
- 关键 API：
  - `img.bakeOrientation(Image image) → Image`（image: ^4.3.0）
  - `img.JpegDecoder().startDecode(bytes)` → `JpegInfo`，含 `exif.imageIfd.orientation`
- 参考：`image_picker` issue 帖一般推荐 `requestFullMetadata: false`，但那不解决 EXIF 旋转问题（仅减少 PHAsset 元数据查询）——此处对策必须在解码层做。
- 未读但可能相关：`cell_overlay.dart` 的 `_ReplacedCell` 也用 `Image.memory + BoxFit.fill`，逻辑同；Approach A 会自动覆盖到。

## Research References

（本任务为明确的技术 bug，根因分析全部基于代码 + Flutter / `image` 包公开文档，无需委派 trellis-research。如用户需要竞品对比可再补。）
