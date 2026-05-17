# fix: grid spacing color uses divider color when adjusting

## Goal

修复宫格切图模式（`/grid`）调整"宫格间距"参数时，预览画布上 cell 之间的 gap 区域**保持为原图透出（视觉等效"透明"）**的问题。期望：gap 区域应该被填充为与 grid 边框线一致的颜色（白色半透明）或可见的间隔填充色，让用户在预览端立刻看到 spacing 的视觉效果，并与导出端"真实切片有间距分隔"的结果保持视觉一致。

## What I already know

### 当前实现（`grid_preview_canvas.dart`）

`_PreviewSurface` 的 `Stack` 结构（line 186–256）：

```
Stack(clipBehavior: hardEdge, fit: expand)
├ [底层] Positioned(完整 source 图，按 sourceOffset/sourceScale 投影到 viewport)
├      → Image.memory(source.bytes, fit: BoxFit.fill)  ← 整张原图，没有"挖洞"
├ [手势层] Positioned.fill(GestureDetector)
├ [覆盖层] AnimatedOpacity(IgnorePointer(CustomPaint(_GridOverlayPainter)))
└ [中心 cell 覆盖层（社交模式）] _PositionedCenterOverlay
```

`_GridOverlayPainter.paint` (line 362–397)：

```dart
final stroke = Paint()
  ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1;
// 仅对每个 cell rect 画 stroke 边框（drawRect / drawRRect），
// 没有任何 fill。
```

### 渲染层 (`grid_image_renderer.dart` line 115–128)

```
for cell in layout.rects:
  cell.width <= 0 || cell.height <= 0 → 1×1 transparent PNG
  else → 按 rect 从 cropped square 中裁剪并 encode 为 PNG
```

→ **导出端确实有间距**（每个 PNG 之间不共享像素，gap 区域被丢弃）。

### Root Cause

预览端 `_GridOverlayPainter` 仅画 cell 边框 stroke，**未对 gap 区域做任何 fill**，导致：

1. 底层 `Image.memory` 原图整张铺在 viewport 上
2. 上层 stroke 只描线，不填色
3. ⇒ Cell 之间的 gap 区域**原图原样透出** → 用户看不到 spacing 调整的视觉变化（除非边框 stroke 颜色与原图对比明显，但 stroke 仅 1px、且半透白，对大间距完全不足以表达）

### 现有边框颜色

- **预览 stroke**: `Color(0xFFFFFFFF).withValues(alpha: 0.6)`（白色 60% alpha 半透明）
- **画布背景**: `colorScheme.surfaceContainer`（在 `GridPreviewCanvas` 的 `Container` decoration）

## Requirements

- 调整 `spacing > 0` 时，预览画布中每对相邻 cell 之间的 gap 区域可见（不再让底层原图原样透出）
- Gap 填充颜色使用 `colorScheme.surfaceContainer`（M3 token，与画布外层 `Container` 背景一致，确保深浅色主题切换自动跟随）— 见 Decision
- `spacing == 0` 时无任何额外视觉变化（painter 行为退化为原状，不触发 saveLayer）
- 圆角（`cornerRadius > 0`）情况下，gap fill 与 cell 圆角边界正确衔接（gap = viewport - 所有 RRect cell 区域）
- 手势进行中 (`_isGesturing == true`) 时，painter 通过 `AnimatedOpacity` 一起淡出（与现有 R-DRAG-04 行为一致）
- 性能要求：painter 实现路径必须是 O(rects)，不引入 SaveLayer / Path.combine 等性能开销过大的 API（即 `flutter analyze` 与 `flutter test` 全绿，编辑流畅度无肉眼可见下降）

## Acceptance Criteria

- [ ] 调整 `spacing` slider 从 0 → 较大值（如 30 px）时，画布上每对相邻 cell 之间出现可见的填充间距条
- [ ] 9 种 grid type（3x3 / 2x2 / 4x4 / …）下，gap 填充都正确覆盖 cell 之间的所有水平 + 垂直分隔区
- [ ] `cornerRadius > 0` 时，gap fill 不溢出到圆角内部（cell 圆角处不出现"啃"边的色块）
- [ ] `spacing == 0` 时，painter 输出与现有实现像素等价（无 fill 像素生成）
- [ ] 拖动 / 缩放手势进行中时，painter 整体淡出（gap fill 与 stroke 一起隐藏）
- [ ] 现有 `_GridOverlayPainter` 相关测试通过（如有），新增 painter 单元测试覆盖 `spacing > 0` 时 fill 区域计算正确
- [ ] `flutter analyze` / `dart format .` / `flutter test` 三红线全绿

## Definition of Done

- 单文件改动（`grid_preview_canvas.dart`），不拆 subtask（painter-only 修改、紧密耦合）
- 新增/更新 painter 测试（如 painter 输出 verification 或 widget golden-style 断言）
- `flutter analyze` / `flutter test` 全绿
- Spec 暂不需要新增（painter 内的颜色/绘制策略属实现细节，不构成跨模块 contract）
- 不创建 git commit（除非用户主动要求）

## Open Questions

（已全部解决，见 Decision）

## Technical Approach

### Approach A: Painter 内扩展，画"差集" gap fill（Recommended）

修改 `_GridOverlayPainter.paint`：

1. 计算 viewport size（即 painter 的 `size` 参数，对应整个画布矩形）
2. 用 `canvas.saveLayer` 包裹绘制（仅在 `spacing > 0` 时启用）
3. 整片 fill viewport：`canvas.drawRect(Offset.zero & size, fillPaint)`
4. 用 `BlendMode.clear` paint 把每个 cell rect 挖空（drawRect / drawRRect with `BlendMode.clear`）
5. `canvas.restore()` 把 saveLayer 合成回主 canvas
6. 之后再画现有 stroke 边框（保持视觉一致）

**Pros**:
- 一次 saveLayer，性能可控
- 圆角自动正确（直接用 RRect.fromRectAndRadius 挖空）
- 复用现有 `rects` 数据，无需引入额外 layout 计算

**Cons**:
- `saveLayer` 比单纯 drawRect 有一定开销（但 painter 每帧只跑一次，rects 数 ≤ 25，可接受）

### Approach B: 计算 gap 区域并直接 drawRect

通过 `colWidths` + `rowHeights` + `gap` 反推 gap bands：

1. 水平 gap：在每两行 cell 之间画一条宽 = `viewportWidth`、高 = `gap * scaleY` 的 rect
2. 垂直 gap：在每两列 cell 之间画一条宽 = `gap * scaleX`、高 = `viewportHeight` 的 rect

**Pros**:
- 无 saveLayer，纯 drawRect 性能最优
- 实现简单直观

**Cons**:
- 圆角 cell 时，gap fill 与 cell 圆角的边界**不会自动避让**——gap 矩形会"穿过"圆角缺口，视觉上看到圆角处仍有原图透出（这是与 Approach A 的关键差异）
- 需要额外保存 gap rect 列表传入 painter，扩展点更多

### Approach C: ImagePath 路径减法（Path.combine difference）

构造 viewport path 减去所有 cell rrect 的差集 path，再 fill。

**Pros**:
- 圆角完美处理
- 代码意图最直白

**Cons**:
- `Path.combine` 在 rects 较多（如 25 cell）时性能不如 saveLayer + BlendMode.clear

### Decision (ADR-lite)

**Context**: 当前 painter 仅画 stroke 边框，gap 区域无 fill，导致预览看不到 spacing 视觉效果。需要在 painter 中增加 gap 填充，且要正确处理圆角 cell 情况。

**Decision**: 采用 **Approach A — saveLayer + BlendMode.clear 挖空**。

**颜色选择**：使用 **`colorScheme.surfaceContainer`**（与 `GridPreviewCanvas` 外层 `Container` 装饰背景一致的 M3 token）。这样 gap 区域呈现的视觉效果，与导出后真实切片所看到的"画布背景透出"等价 — 预览端 = 导出端，是三个候选里"所见即所得"程度最高的选项。

**实现要点**：
- 由于颜色是不透明的 surfaceContainer，gap fill 会**完全遮蔽**底层 `Image.memory` 的原图像素
- painter 需要拿到 `Color` 值 → 通过新增 `final Color gapColor` 字段从构造点传入 `Theme.of(context).colorScheme.surfaceContainer`
- `saveLayer + integral fill + 逐 cell BlendMode.clear (RRect)` 路径保留 ← 这是圆角下唯一不"啃边"的实现

**Consequences**:
- ✅ 预览端 spacing 视觉立刻可见，且与导出 PNG 列表的真实间距视觉**完全等价**
- ✅ 圆角自动正确（BlendMode.clear 沿 RRect 路径挖空，cell 圆角内仍可见原图）
- ✅ surfaceContainer 是 M3 token，主题切换 / 深色模式自动跟随
- ✅ Painter 接口仅增加一个 `Color gapColor` 字段，最小侵入
- ⚠️ saveLayer 一次帧成本，但 rects ≤ 25 + 每帧只跑一次 → 实测可忽略
- ⚠️ Gap 区域底层 `Image.memory` 完全被遮蔽（这是设计意图，与导出视觉一致）

## Out of Scope (explicit)

- 导出端 (`grid_image_renderer.dart`) 行为变更（导出已经正确处理间距）
- Slider UI、spacing 取值范围、`kMaxGridSpacing` 等参数调整
- Cell 圆角 painter 重构（已在 line 388–395 正确处理）
- 长图拼接、社交九宫格、字幕拼图等其他模式的类似排查（视情况另开任务）
- 性能基准测试（painter 改动可控、肉眼无感即视为达标）
- Subtask 拆分（单文件单 painter 改动）

## Implementation Plan (small PRs)

单 PR 单文件：

1. **修改 `_GridOverlayPainter`**：
   - 增加 `final double spacing` 字段（painter 内分支判断条件）
   - 增加 `final Color gapColor` 字段（接收 `colorScheme.surfaceContainer`）
   - 在现有 stroke 绘制**之前**插入 gap fill 分支：
     ```
     if (spacing > 0) {
       canvas.saveLayer(Offset.zero & size, Paint());
       canvas.drawRect(Offset.zero & size, Paint()..color = gapColor);
       final clearPaint = Paint()..blendMode = BlendMode.clear;
       for r in rects:
         drawRRect(RRect.fromRectAndRadius(rect, scaledRadius), clearPaint);
         // 或 drawRect(rect, clearPaint) when radius == 0
       canvas.restore();
     }
     ```
2. **更新构造点** (`grid_preview_canvas.dart:241-247`)：
   - 在 `_PreviewSurface.build` 中通过 `Theme.of(context).colorScheme.surfaceContainer` 拿到颜色
   - 传入 `spacing: state.spacing, gapColor: colorScheme.surfaceContainer`
3. **更新 `shouldRepaint`** (line 400-405)：补充 `old.spacing != spacing || old.gapColor != gapColor` 判断
4. **新增 painter 测试**（`test/features/grid/presentation/widgets/grid_preview_canvas_test.dart` 或同级新建）：
   - `spacing == 0` 时输出与现有等价（painter 走 stroke-only 路径，无 saveLayer / fill 调用）
   - `spacing > 0` 时 painter 触发 saveLayer + 1 次整片 fill + N 次 clear-blend draw（N = rects.length）
   - 可使用 `flutter_test` 的 `goldens` 或自定义 `MockCanvas` 拦截调用计数
5. **手动验证**（笨蛋手动检查 + 本小姐 build 一次）：
   - 调整 spacing slider 从 0 → 30，gap 应该明显可见、颜色与画布外环一致
   - 调整 cornerRadius，cell 圆角内底层 image 可见，圆角外 gap 区为 surfaceContainer
   - 主题切深色模式，gap 颜色自动变深

## Research References

（无需额外研究：painter / saveLayer / BlendMode.clear 是 Flutter 标准 API，社区文档充分；本任务 root cause 与方案在代码内可完整推导）

## Technical Notes

### Affected files

- `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` —— `_GridOverlayPainter` 类（line 349–406）+ 构造点（line 241–247）
- 测试文件（如有 painter 单元测试）—— 同步新增 spacing 相关断言

### Related historic tasks

- `.trellis/tasks/archive/2026-05/05-17-grid-canvas-drag-overwrite/` —— 引入手势 + grid 淡出
- `.trellis/tasks/archive/2026-05/05-08-grid-split/` —— 引入原始 grid 切图功能
- `.trellis/tasks/archive/2026-05/05-08-regular-grid/` —— 引入 spacing / cornerRadius 参数

### Constraints

- 不可改变 `computeGridLayout` 返回结构（其他模块依赖）
- 不可改变 `_GridOverlayPainter` 已有 `rects` / `cornerRadius` / `scaleX` / `scaleY` 字段语义
- `IgnorePointer` + `AnimatedOpacity` 包裹必须保留（painter 不能突破手势/淡出 contract）
