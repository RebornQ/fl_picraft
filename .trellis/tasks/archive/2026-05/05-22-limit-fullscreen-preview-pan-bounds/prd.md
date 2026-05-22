# limit-fullscreen-preview-pan-bounds

## Goal

修复 `PreviewFullScreenDialog` 全屏预览中 `InteractiveViewer` 的 pan 无限制问题：用户反馈放大后可以把图片完全 pan 出 viewport，体验糟糕。期望行为是**图片边缘贴住容器（viewport）边缘时停止 pan**——主流照片查看器（iOS Photos / Google Photos）的标准行为。

## What I already know

* 目标文件：`lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
* 当前实现（行 754）：
  ```dart
  InteractiveViewer(
    boundaryMargin: const EdgeInsets.all(double.infinity),  // ← 无限制
    minScale: 1.0,
    maxScale: 4.0,
    panEnabled: _zoomed,
    child: Center(child: Image.memory(..., fit: BoxFit.contain)),
  )
  ```
* `boundaryMargin` 语义：child 的边缘可以超出 viewport 的最大距离
  * `EdgeInsets.zero` → child 边缘不能离开 viewport（**这就是期望行为**）
  * `EdgeInsets.all(double.infinity)` → 无限制（当前 bug）
* InteractiveViewer 的 child 是 `Center widget`，占据整个 viewport 大小（不是 Image 的实际像素矩形）
* 联动影响：ADR-0001 中 `_ImmersivePageScrollPhysics` 的"边缘触底检测"依赖 matrix translation 的边界：boundaryMargin 改为 zero 后 InteractiveViewer 会自动 clamp，touchBoundary 公式仍可用（甚至更可靠）

## Assumptions

* 选择 **M-α 方案**（视觉等价 L-β + 实现简单 + 无对抗 Flutter 内部硬编码）：
  * 保留 `constrained: true`（默认），InteractiveViewer 的 child 强制为 viewport size
  * child 内部 `Center(SizedBox(renderedSize, Image(fill)))` 渲染图片矩形居中
  * `boundaryMargin: EdgeInsets.zero` 限制 pan 到 child（viewport）边缘
  * 因为 dialog 背景是 `Colors.black`，letterbox 黑区与外层背景视觉等价 → 用户感知 pan 限制在图片像素边缘
* （历史）放弃 L-β 严格"图片像素边缘"语义：trellis-implement 首次尝试 `constrained: false + alignment: center + SizedBox(renderedSize) + boundaryMargin: zero` 后出现居中丢失 bug——Flutter `InteractiveViewer.alignment` 是传给内部 `Transform.alignment` 的（matrix 锚点），不是 child 在 viewport 中的对齐；`constrained: false` 时硬编码 `OverflowBox(alignment: Alignment.topLeft)`（见 `interactive_viewer.dart:1123-1141`），无 API 可让 child 在 viewport 居中
* `_PreviewPage` 已通过 `ImageStreamListener` 拿到 `_imageSize`（trellis-implement 已实现）
* `MemoryImage` 解码通常在第一帧前后完成，imageSize 缺失的时间窗口极短

## Requirements

* `InteractiveViewer.boundaryMargin` 改为 `EdgeInsets.zero`
* `InteractiveViewer.constrained` 保持默认（`true`），不显式传值（也不传 `alignment`）
* `InteractiveViewer.child` 改为 `Center(SizedBox.fromSize(size: renderedSize, child: Image.memory(fit: BoxFit.fill)))`
  * `renderedSize = applyBoxFit(BoxFit.contain, imageSize, viewport).destination`
  * 因为 SizedBox 已经匹配图片宽高比，内部 `Image(fit: fill)` 在 SizedBox 内无 letterbox
  * 外层 `Center` 让 SizedBox 在 viewport-sized child 内居中
* `imageSize` 尚未解码完成时的 fallback：`renderedSize = viewport`（让 `Center > SizedBox > Image(fill)` 结构跨越 pre-resolve / post-resolve 两个 build 保持稳定，避免 `InteractiveViewer` 重建丢 transformation）
* 放大态 pan：child（= viewport）边缘贴 viewport 边缘 → 停止 pan（InteractiveViewer 自动 clamp）
* **视觉等价性**：dialog 背景 `Colors.black`，letterbox 黑区与背景视觉不可分辨，用户感知 pan 限制 = 图片像素边缘
* 不破坏 ADR-0001 边缘弹切：触底检测公式 `maxTx = (rect.width * scale - rect.width) / 2` 仍正确（基于图片像素 rect，与 child 结构无关）
* 不破坏 ADR-0002 5 手势分层

## Acceptance Criteria

* [x] `InteractiveViewer.boundaryMargin == EdgeInsets.zero`
* [x] `InteractiveViewer.constrained == true`（默认，不显式传）
* [x] `InteractiveViewer.child` 是 `Center > SizedBox.fromSize(size: renderedSize) > Image.memory(fit: BoxFit.fill)`，其中 `renderedSize` 来自 `applyBoxFit(BoxFit.contain, imageSize, viewport).destination`
* [x] imageSize 未解码时 `renderedSize = viewport`，`Center > SizedBox > Image(fill)` 结构不变
* [x] 放大态下尝试 pan 超出 child 边缘 → matrix translation 被 clamp，再 drag 不再变化
* [x] 现有测试中 `boundaryMargin == EdgeInsets.all(double.infinity)` 已改为 `EdgeInsets.zero`
* [x] 测试覆盖：
  * (a) `constrained == true` + child 是 `Center > SizedBox > Image(fill)`
  * (b) 放大 + pan 到边缘后再 pan，translation.x / .y 不再变化
  * (c) **居中回归测试**：identity 状态下 image rect 覆盖 viewport 中心
* [x] ADR-0001 边缘弹切仍工作（公式不变）
* [x] `flutter analyze` 干净；`dart format .` 应用

## Definition of Done

* `flutter test` 通过
* `flutter analyze` clean
* `dart format .` 应用过
* dartdoc 同步更新（提及 boundaryMargin 改动 + 为什么）
* ADR-0001 文档注脚更新：boundaryMargin: zero 与边缘弹切公式的兼容性说明

## Out of Scope

* 不把 child 改为只占图片像素的 widget（即不解决 letterbox 边缘语义差异）
* 不调整 minScale / maxScale
* 不动 ADR-0001 / ADR-0002 的核心架构
* 不动 panEnabled 动态切换契约

## Technical Approach

### 主改动（`_PreviewPage.build`）— M-α 方案

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final viewport = Size(constraints.maxWidth, constraints.maxHeight);
    final imgSize = _imageSize;

    // imageSize 未解码完成时 → renderedSize = viewport（让结构保持一致跨 build）
    final renderedSize = imgSize == null
        ? viewport
        : applyBoxFit(BoxFit.contain, imgSize, viewport).destination;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () => _handleDoubleTap(viewport),
      child: InteractiveViewer(
        transformationController: _tc,
        // constrained: true (默认，省略，不传)
        // alignment: 不传（默认即 null，仅对 constrained: false 有意义）
        panEnabled: _zoomed,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: kMaxScale,
        boundaryMargin: EdgeInsets.zero,   // ← child 不能 pan 出 viewport
        child: Center(                     // ← SizedBox 在 viewport-sized child 中居中
          child: SizedBox.fromSize(
            size: renderedSize,
            child: Image.memory(
              widget.bytes,
              fit: BoxFit.fill,            // ← SizedBox 已对齐图片宽高比
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  },
);
```

### 测试更新

* 既有 `iv.boundaryMargin == const EdgeInsets.all(double.infinity)` 改为 `iv.boundaryMargin == EdgeInsets.zero`
* 既有 `iv.constrained == isFalse` 改为 `iv.constrained == isTrue`（默认值）
* 既有 `iv.alignment == Alignment.center` 断言**删除**（不再显式传 alignment）
* 既有 child 结构断言：从"SizedBox + Image(fill)"扩展为"Center > SizedBox > Image(fill)"
* 新增"居中回归测试"：identity 状态下 image 的 painted rect 必须包含 viewport 中心点
* 既有"pan 到边缘后停止"测试保留

### 边缘弹切兼容性

`_reportGestureState` 中 `maxTx = (rect.width * scale - rect.width) / 2` 仍正确：
* `rect.width = _imageDisplayRect(viewport).width`（图片像素显示宽，BoxFit.contain 计算结果）
* `rect.width * scale = imageRenderedWidth`（缩放后的图片像素宽）
* `maxTx = (imageRenderedWidth - rect.width) / 2`（图片像素中心的最大平移距离）

**注意**：M-α 下 InteractiveViewer 物理上允许的 max translation 是 `(viewport.w * scale - viewport.w) / 2 = viewport.w * (scale-1)/2`，**大于** ADR-0001 公式给出的 `maxTx`（基于图片像素宽 ≤ viewport 宽）。这意味着 `atLeftEdge / atRightEdge` 会**提前**在图片像素贴 viewport 边时触发——但此时用户感知就是"图片到边缘了"（letterbox 黑区与背景视觉等价），边缘弹切发生在正确的时机。

## Decision (ADR-lite)

* **Context**: 当前 `boundaryMargin: infinity` 让用户可以把图片完全 pan 出 viewport，违背主流相册体验
* **Initial attempt (L-β, superseded)**: trellis-implement 首次尝试 `constrained: false + alignment: center + SizedBox(renderedSize) + boundaryMargin: zero` 期望"图片像素边缘"严格 clamp。结果引入**居中丢失** bug：Flutter `InteractiveViewer.alignment` 是传给内部 `Transform.alignment` 的（matrix 锚点），不是 child 在 viewport 中的对齐；`constrained: false` 时硬编码 `OverflowBox(alignment: Alignment.topLeft)`（见 `interactive_viewer.dart:1123-1141`），**无 API 可让 child 居中**
* **Decision (M-α, final)**: 保留默认 `constrained: true`，用 `Center > SizedBox(renderedSize) > Image(fill)` child 结构 + `boundaryMargin: EdgeInsets.zero`
* **Consequences**:
  * 用户体验对齐 iOS Photos / Google Photos（视觉等价 L-β 严格语义）
  * Letterbox 黑区在 viewport 内 vs 在 viewport 外用户感知不到（dialog 背景是 `Colors.black`）
  * ADR-0001 边缘弹切的"触底"判定基于图片像素 rect 不变（公式无关 child 结构）
  * 实现简单可靠，无需对抗 Flutter 内部 `constrained: false + OverflowBox(topLeft)` 硬编码
  * Trade-off：letterbox 区域算作 InteractiveViewer 可 pan 范围（理论上用户可 pan 一小段 letterbox 才被 clamp）—— 在全黑背景下用户无法感知

## Open Questions

* (none)

## Technical Notes

* 不需要 trellis-research：单点 API 改动，不引入新 API
* 触底判定算法不变（ADR-0001 公式仍正确）
* 注入 spec 与上一任务相同
