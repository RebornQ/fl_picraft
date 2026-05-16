# grid editor reactive canvas height and side-panel chrome fill

## Goal

在桌面端 grid editor 的 expanded / large 双栏布局下，做两件事：
1. **验证 + 补测试**：画布尺寸必须随窗口拖拽缩放实时变化（LayoutBuilder + Row(stretch) 已经做了这件事，但需要补一个动态改 viewport 后画布尺寸跟着变的测试）。
2. **右侧控制栏背景铺满高度**：给右列加一个 surface 容器背景（`surfaceContainerLow` + `outlineVariant` 边框 + 16dp 圆角），从顶部贴到底部铺满 row 高度，内部 GridControlsPanel 仍按内容高度顶部对齐 + SingleChildScrollView 溢出可滚动。

## What I already know

### 需求 1 的当前实现

`lib/features/grid/presentation/screens/grid_editor_screen.dart:165-222`:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    // ...
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GridPreviewCanvas(),
                  ),
                ),
              ),
              if (sourceTooSmall) ...[...],
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: panelWidth,
          child: const SingleChildScrollView(
            child: GridControlsPanel(),
          ),
        ),
      ],
    );
  },
)
```

`LayoutBuilder` 在窗口大小变化时会重建并提供新的 `constraints.maxWidth` / `constraints.maxHeight`。Flutter 框架在 platform 上报 viewport 变化（Window.onMetricsChanged）时会触发 `WidgetsBinding.handleMetricsChanged → markNeedsLayout`，整个树（含 LayoutBuilder）都会重新 layout。所以理论上画布已经实时响应。

但是测试套件中**没有覆盖动态改 viewport 后画布尺寸跟着变**这条 path——现有 expanded / large 用例都是一次性 `_setViewportSize` + `pumpWidget`，不能验证"原窗口下渲染一次后改窗口大小，画布尺寸是否跟着变"。补一条测试可以把这条 path 显式锁死，避免未来意外引入 widget 之间的 LayoutBuilder 短路。

### 需求 2 的当前实现

`grid_editor_screen.dart:213-218` 右列：

```dart
SizedBox(
  width: panelWidth,
  child: const SingleChildScrollView(child: GridControlsPanel()),
),
```

- `SizedBox(width: panelWidth)` 的 height 由父级（Row stretch）决定 = row 高度。SizedBox 高度本身已经撑满 row，但**视觉上看不到**——因为 GridControlsPanel 是 bare（spec convention "panel has no outer padding"，无 chrome），所以右列看起来就是控件本身的高度。
- 用户希望右列**视觉上**有一个完整的 column 范围，从顶部贴到底部。

`GridControlsPanel` (`lib/features/grid/presentation/widgets/grid_controls_panel.dart`) 的 build 是裸 `Column(stretch, [NineGridSocialRow, SizedBox(16), GridTypeSelector, SizedBox(16), GridParameterCards])`，没有任何 Material/Container 包装。

### Spec convention

`.trellis/spec/frontend/responsive-layout.md` 中：
- "Convention: panel has **no** outer padding" — panel 本身保持 bare，**caller 负责装饰**。本次改动符合该 convention：在 caller (grid_editor_screen) 处加 Container chrome，而不是改 GridControlsPanel 内部。

### 其他相关位置

- `stitch_editor_screen.dart` 的 expanded / large 也是 `SizedBox(width, SingleChildScrollView(StitchControlsPanel))` 无 chrome。本任务**不强制改 stitch**（避免越权；stitch 编辑器的视觉风格留给用户自己后续决定）。

## Confirmed Decisions (user-approved 2026-05-17)

- ✅ **需求 1**: 仅补测试覆盖（LayoutBuilder 已实时响应），不动代码。测试要新增一条「动态改 viewport 后画布尺寸跟着变」。
- ✅ **需求 2**: 采用 Approach A — 右列加 surface 背景容器：
  - `color: colorScheme.surfaceContainerLow`
  - `border: Border.all(color: colorScheme.outlineVariant)`
  - `borderRadius: BorderRadius.circular(16)`
  - 内部 padding 16dp 给 SingleChildScrollView(GridControlsPanel)
  - 背景容器高度撑满 Row stretch（与 SizedBox 等高）
  - GridControlsPanel 仍顶部对齐 + 内容超过时 SingleChildScrollView 内部滚动
- ⚠️ stitch_editor 的对应布局**不动**（不在本任务范围）。

## Requirements

- 替换 `grid_editor_screen.dart:213-218` 的右列结构：
  ```dart
  SizedBox(
    width: panelWidth,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(child: GridControlsPanel()),
      ),
    ),
  ),
  ```
  Container/DecoratedBox 二选一——`DecoratedBox` 更轻量（不引入 padding 包装），但需要 `Padding` 子节点；`Container(decoration, padding, child)` 更紧凑。实施时挑可读性更好的写法。
- `colorScheme` 已经在 `_GridEditorBody.build` 第 146 行获取（用于 `_SourceSizeWarning`），可以直接复用，无需额外传递。
- 测试新增一条 `flutter test` 用例：
  - `_setViewportSize(tester, Size(1280, 800))` → pump → 测一次 canvas size
  - 改 viewport 到 `Size(1600, 900)` → pump → 测 canvas size 比之前**大**（高度更高）
  - 再改回 `Size(1280, 800)` → pump → canvas size 回到原值
  - 用同一个 `pumpWidget` 实例，模拟窗口拖拽
  - 也断言右列的 DecoratedBox 在所有阶段都铺满 row 高度
- 测试新增一条断言：右列 `DecoratedBox` 的 size.height == row 容器高度（约 viewport.height - AppBar - top padding - bottom padding）。

## Acceptance Criteria

- [ ] 在 1280×800 / 1920×1080 / 2560×1440 三尺寸下：
  - 画布正方形 + 居中 + 高度 ≤ row 高度（已有断言）
  - 右列背景容器 (`DecoratedBox` 或 `Container`) 的渲染高度 == row 高度（== 画布 + warning 占据的总高度）
  - 背景可见：`surfaceContainerLow` 颜色 + `outlineVariant` 边框 + 16dp 圆角
- [ ] 动态改 viewport 后画布尺寸跟随变化（新增测试覆盖）
- [ ] GridControlsPanel 内容仍顶部对齐，溢出时 SingleChildScrollView 在背景容器内部滚动
- [ ] compact / medium 无回归
- [ ] grid overlay / GridLayout / Painter 数学无回归
- [ ] `dart format` / `flutter analyze` / `flutter test` 全绿

## Definition of Done

- Tests 已新增 viewport 动态变化 + panel chrome 高度断言
- 三红线全绿
- `grid_editor_screen.dart` 的 doc-comment 同步描述 panel chrome（surface 背景容器）
- spec 沉淀：在 `responsive-layout.md` 中添加一条 convention 「Grid editor side-panel uses a surface chrome container; stitch editor still uses bare panel」（或扩展现有 "Convention: panel has no outer padding" 的 caller decoration 说明），明确不同 editor 的视觉决策可以不同。

## Out of Scope

- 不改 `GridControlsPanel` 内部（保持 bare per spec convention）
- 不改 stitch_editor 的 panel 视觉（留给后续 task 决定）
- 不改 panel 宽度 clamp 公式
- 不改 compact / medium 的 panel 处理（compact 内嵌在 `Flexible(loose) + SingleChildScrollView`，不加 chrome）
- 不改 grid overlay / GridLayout / Painter

## Technical Notes

- 关键文件：
  - `lib/features/grid/presentation/screens/grid_editor_screen.dart`（右列 chrome）
  - `test/features/grid/presentation/grid_editor_responsive_test.dart`（新增测试）
  - `.trellis/spec/frontend/responsive-layout.md`（panel chrome convention 说明）
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md`（widget composition / 主题颜色用法）
  - `.trellis/spec/frontend/responsive-layout.md`（panel chrome decoration）
  - `.trellis/spec/frontend/quality-guidelines.md`（三红线）
