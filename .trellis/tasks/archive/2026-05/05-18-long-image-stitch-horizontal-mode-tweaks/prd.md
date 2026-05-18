# 长图拼接 · 横向模式细节修复

## Goal

长图拼接（`features/long_stitch`）当前在横向模式（`StitchMode.horizontal`）下有两个明显的体验断层：

1. **工具栏底下挂着一根孤立的 Divider**：那根 Divider 原本是用来在「仅保留字幕」字幕模块和后续通用 sliders（图片间距 / 边框 / 圆角）之间做视觉分割。横向模式下整个字幕模块都被隐藏（`subtitleApplicable = state.mode == StitchMode.vertical`），但 Divider 仍然无条件渲染，导致看上去像是「模式选择器和后面的 sliders 之间被无缘无故割开」。
2. **画布在横向模式下高度被压缩**：当前 preview canvas 用 `FittedBox(fit: BoxFit.contain)` 把 `canvasWidth × canvasHeight` 等比缩放到 viewport 内。横向模式下 canvas 通常是「短而宽」（高度 ≈ 第一张图高度，宽度 = 多张图横向拼接，aspect width≫height），contain 模式会先把它缩到 maxWidth → 高度也跟着等比缩到很小 → 大量灰色 dead space。用户预期的行为是「**画布高度铺满 viewport**，宽度超出 viewport 时**横向滚动**查看」。

## Requirements

### R1 — Divider 仅在字幕模块可见时显示
* 文件：`lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart`
* 当前 line 127 的 `const Divider(height: 24)` 是无条件的。
* 改为 `if (subtitleApplicable) const Divider(height: 24)` —— 与 line 74 的 subtitle toggle 共用同一个 `subtitleApplicable = state.mode == StitchMode.vertical` 条件。
* 边界含义：
  * 纵向模式下：subtitle toggle 至少会出现 → Divider 保留，分隔语义不变。
  * 横向模式下：subtitle 模块整体隐藏 → Divider 一起消失，工具栏从 mode segmented 直接过渡到 sliders。

### R2 — 横向模式画布铺满高度 + 横向滚动
* 文件：`lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart`
* 期望行为：
  * **纵向模式**（保持现状）：外层 `SingleChildScrollView` 走 `Axis.vertical`；`ConstrainedBox(minHeight: maxHeight)` 让灰色背景铺满 viewport 高度；`_PreviewSurface` 用 `FittedBox(fit: BoxFit.contain)` 把 canvas 等比缩放到可用区域；当 canvas 自然高度大于 viewport 时由外层纵向滚动承接。
  * **横向模式**（新增）：外层 `SingleChildScrollView` 改走 `Axis.horizontal`；`ConstrainedBox(minWidth: maxWidth)` 让灰色背景铺满 viewport 宽度；`_PreviewSurface` 计算 `displayHeight = 可用高度 - padding` 并按 `displayWidth = displayHeight * aspect` 撑出实际宽度；当 `displayWidth > maxWidth` 时由外层横向滚动承接。
* 对齐：当横向模式下拼图总宽度小于 viewport 时 → **水平居中**（沿用既有 `Center` widget；与纵向模式短画布居中行为一致）。
* 视觉保留：阴影 / 圆角 / 边框 / 内白底，三套样式与纵向模式一致。
* 切换流畅：用户点击 mode segmented 切到横向时，画布应该立即重新布局；切回纵向时也要立即恢复。Riverpod state 已经驱动整个 `build` 重建，所以这里不需要额外的 listenable。

## Acceptance Criteria

* [ ] 横向模式下面板不再渲染 `Divider`（DOM-level 通过 widget test `find.byType(Divider)` 验证：`hasZero` when horizontal, `hasOne` when vertical）。
* [ ] 纵向模式下 Divider 行为保持不变（vertical + subtitle toggle off + <2 images → 仍然出现，分隔 subtitle toggle 和 spacing slider）。
* [ ] 横向模式下，当拼图总宽度 > viewport 时，画布可以通过横向手势滚动（widget test 用 `Scrollable.of` + `ScrollPosition.maxScrollExtent > 0` 验证）。
* [ ] 横向模式下，画布在垂直方向上铺满 viewport（test：`tester.getRect(find.byType(_PreviewSurface 包裹的 SizedBox)).height` ≈ `viewportHeight - padding*2`，容差 1px）。
* [ ] 横向模式下，当拼图总宽度 < viewport 时，画布水平居中（test：左右 padding 等距）。
* [ ] 纵向模式下，所有现有的滚动/缩放/字幕模式行为完全不变（已有 widget test 仍然 green）。
* [ ] 模式切换：横向 → 纵向 → 横向连续切换，无 RenderFlex / overflow 异常。
* [ ] `dart format .` / `flutter analyze` / `flutter test` 三件套通过。

## Definition of Done

* 上述 Acceptance Criteria 全部勾掉。
* 至少新增 1 个 widget test 文件，覆盖：
  * R1：vertical/horizontal 下 Divider 的可见性。
  * R2：horizontal 下画布铺满高度、宽度溢出时可横向滚动、宽度不溢出时居中。
* 不破坏现有的 `test/features/long_stitch/...` 任何用例。
* 在仓库根目录跑 `flutter analyze` 无新增 warning。

## Out of Scope

* **不**改 `_layoutMovieSubtitle` 或任何 layout 算法（横向模式没有字幕子算法）。
* **不**改 export pipeline / `StitchImageRenderer`（导出物的像素与预览一致，渲染管线本来就独立于预览的缩放策略）。
* **不**改纵向模式的滚动行为（避免 regress 已通过的 05-18-subtitle-reset-on-reselect / 05-18-long-image-stitch-toolbar-and-subtitle-mode 任务）。
* **不**新增 Scrollbar widget（与纵向模式无 Scrollbar 的现状保持一致；如未来要加，应一并加在两个方向上，留到后续任务）。
* **不**做 mode segmented 的过渡动画（属于 polish 任务）。

## Technical Approach

### R1 — Divider 条件化

```dart
// stitch_controls_panel.dart, around line 127
- const Divider(height: 24),
+ if (subtitleApplicable) const Divider(height: 24),
```

### R2 — 双轴滚动 + 模式相关的 fit

```dart
// stitch_preview_canvas.dart
class StitchPreviewCanvas extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      stitchEditorControllerProvider.select((s) => s.mode),
    );
    final state = ref.watch(stitchEditorControllerProvider);
    final isHorizontal = mode == StitchMode.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
          child: SingleChildScrollView(
            scrollDirection: isHorizontal ? Axis.horizontal : Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: isHorizontal ? constraints.maxWidth : 0,
                minHeight: isHorizontal ? 0 : constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: state.hasImages
                      ? _PreviewSurface(state: state, fillAxis: isHorizontal ? Axis.vertical : null)
                      : _EmptyHint(...),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.state, this.fillAxis});
  final StitchEditorState state;
  /// When set to [Axis.vertical], the surface fills the available HEIGHT
  /// (height-driven sizing — used by horizontal stitch mode). When null,
  /// falls back to the legacy contain behavior (vertical stitch mode).
  final Axis? fillAxis;

  @override
  Widget build(BuildContext context) {
    // ...existing layout math...
    final aspect = canvasWidth / canvasHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double displayHeight;
        final double displayWidth;
        if (fillAxis == Axis.vertical) {
          // Height-driven: fill height, derive width from aspect.
          // maxHeight is finite because the outer ScrollView is
          // horizontal, so vertical constraints propagate normally.
          displayHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : canvasHeight;
          displayWidth = displayHeight * aspect;
        } else {
          // Legacy contain behavior (vertical mode).
          // ...existing maxWidth/maxHeight clamp...
        }

        return SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(/* unchanged shadow + radius */),
            child: FittedBox(fit: BoxFit.contain, child: clipped),
          ),
        );
      },
    );
  }
}
```

### 关键约束 / 风险

* `LayoutBuilder` 嵌套：外层 LayoutBuilder 给出 viewport constraints；内层 LayoutBuilder（在 _PreviewSurface）给出去掉 padding 后的 constraints。横向滚动模式下，内层 maxWidth 是 infinity（因为 SingleChildScrollView 是 horizontal），但 maxHeight 来自 ConstrainedBox 之上的链路，应该保持 finite。务必在改完后 `flutter run` 实测一次，避免 LayoutBuilder unbounded constraints assert。
* FittedBox 的角色：横向模式下 SizedBox 已经是 displayHeight × displayWidth，FittedBox(fit: contain) 把自然 canvas 等比 fit 进去，aspect 不会失真 → 安全保留。
* Mode 切换时的 `SingleChildScrollView` 重建：scrollDirection 变化会让 ScrollController 失效，但本组件没有暴露 controller、也没用 PageStorageKey，所以 framework 默认行为是「丢弃旧 position 新建一个」，对用户来说滚动位置归零是合理预期（用户切换模式后画布尺寸完全变了，旧位置无意义）。

## Decision (ADR-lite)

**Context**: 横向模式下的两个体验问题——孤立 Divider 和高度被压缩。需要决定：
1. Divider 是「彻底删除」还是「条件化」？
2. 横向模式是「另起一个完全独立的预览组件」还是「在现有 `StitchPreviewCanvas` 内基于 mode 切换」？
3. 横向滚动需不需要 Scrollbar？

**Decision**:
1. Divider **条件化**（`if (subtitleApplicable)`）—— 纵向模式下它仍有分隔语义，不该删。
2. **在现有组件内基于 mode 切换** —— 两种模式共用大部分代码（灰底、shadow、padding、border、radius、empty hint），独立组件会带来重复。
3. **不加 Scrollbar** —— 与纵向模式现状保持一致；如未来要加应该两个方向一起补，留到后续任务。
4. 横向滚动时拼图不足宽度 → **居中**（用户偏好确认，与纵向模式短画布居中行为统一）。

**Consequences**:
* `StitchPreviewCanvas.build` 多一个 `state.mode` 的 watch，会因为 mode 变更触发 rebuild —— 但 mode 切换本来就是低频操作，性能可忽略。
* `_PreviewSurface` 多一个 optional `fillAxis` 参数，分支稍多但每个分支语义独立，可读性可接受。
* 未来若要新增第三种 fit 模式（例如「按 viewport 中心 1:1 显示」），需要把 `fillAxis?` 升级成 enum。这个升级路径直接、不会被现状阻塞。

## Technical Notes

### 涉及代码
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart:127` — Divider 行
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart:60` — `subtitleApplicable` 计算（不动，复用）
* `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart:32-62` — `StitchPreviewCanvas.build`
* `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart:93-231` — `_PreviewSurface.build`
* `lib/features/long_stitch/domain/entities/stitch_mode.dart` — `StitchMode.horizontal`（已存在，不动）

### 测试位置
* 新增/扩展：`test/features/long_stitch/presentation/widgets/stitch_preview_canvas_test.dart`
* 新增/扩展：`test/features/long_stitch/presentation/widgets/stitch_controls_panel_test.dart`
* （若两个文件其中一个不存在，新建。已有同名 widget test 框架优先扩展，不重复 setup。）

### 参考
* 相关历史任务（已归档）：
  * `.trellis/tasks/archive/2026-05/05-18-long-image-stitch-toolbar-and-subtitle-mode/` — 工具栏和字幕模式（建立了 subtitleApplicable / subtitleEffective 的语义）
  * `.trellis/tasks/archive/2026-05/05-18-subtitle-reset-on-reselect/` — 字幕高度重置（确认 mode 切换的相关行为）
* spec：`.trellis/spec/frontend/component-guidelines.md`, `responsive-layout.md`, `quality-guidelines.md`

## Implementation Plan (single PR, no subtasks)

两个改动都是 UI 调整 + 同一个 feature，不拆 subtasks。建议一次性提交一个 PR：

1. **改 panel**：`stitch_controls_panel.dart` Divider 条件化（约 1 行）。
2. **改 canvas**：`stitch_preview_canvas.dart` 双轴滚动 + 模式相关 fit（约 30-40 行）。
3. **加测试**：覆盖 Acceptance Criteria 的所有勾选项。
4. **跑三件套**：`dart format .` / `flutter analyze` / `flutter test`。
