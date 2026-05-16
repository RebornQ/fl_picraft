# extend grid canvas height-first fit to expanded and large

## Goal

修复宫格切图编辑器在 **expanded / large** 窗口（桌面端全屏、ultra-wide 显示器、平板横屏）下画布依然按宽度撑成正方形从而超过屏幕可用高度的问题。让画布在所有 size class 下都以容器可用高度为主进行铺满。

## What I already know

### 上一轮 task 的判断失误

`05-16-grid-canvas-height-first-fit` 任务（已 archive）的 PRD 把 expanded / large **明确放进了 Out-of-Scope**，理由是「旁边面板对滚动需求不同，画布列宽受 Row 约束，高度优先在两列模式下意义不大」。这个判断是**错的**：

- 在 1920×1080 桌面端全屏下，左列 `Expanded` 拿到约 1404 dp 宽度（1920 - 32 padding - 16 gap - 468 panel）；
- 当前实现是 `Expanded > SingleChildScrollView > Column(stretch) > AspectRatio(1, Canvas)`；
- `SingleChildScrollView` 给子 widget unbounded 纵向约束，`Column(stretch)` 把宽度拉到 1404 dp，`AspectRatio(1)` 按宽度算高度 → 画布 1404×1404；
- 但屏幕可用高度只有约 ~980 dp（1080 - AppBar 56 - padding 40）→ 画布溢出 ~424 dp，整页必须滚动才能看完画布。

用户原话: **"宫格切图模式在桌面端全屏时画布依然高度过大, 我想要铺满容器高度即可"**。

### 当前 expanded / large 实现位置

`lib/features/grid/presentation/screens/grid_editor_screen.dart:147-205`：
```dart
return Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final available = (constraints.maxWidth - 16).clamp(0.0, double.infinity);
      final panelWidth = (available * 0.25).clamp(380, 480);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(           // ← 根因：unbounded 纵向约束
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AspectRatio(aspectRatio: 1, child: GridPreviewCanvas()),
                  if (sourceTooSmall) ...[...],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: panelWidth, child: const SingleChildScrollView(child: GridControlsPanel())),
        ],
      );
    },
  ),
);
```

### 需要同步更新的 spec / doc-comment

- `lib/features/grid/presentation/widgets/grid_preview_canvas.dart:34-38` 的 doc-comment 写着「expanded / large screens fit by **width**」——这恰恰是问题所在，要改成「fit by **height** (uniform)」。
- `lib/features/grid/presentation/screens/grid_editor_screen.dart:53-54` 顶部 doc-comment 写着「preview (wrapped in `AspectRatio(1)`) + optional warning on the left」——也要更新为 height-first 表述。
- `.trellis/spec/frontend/responsive-layout.md` 的「Compact-mode editor body — height-first Column skeleton」pattern 段落只针对 compact / medium，需要扩写或新增 expanded / large 的 height-first 变体。
- responsive behavior table 中 grid_editor 行的 expanded / large 列需要更新。

### 受影响测试

`test/features/grid/presentation/grid_editor_responsive_test.dart`：
- 现有 expanded / large 用例只断言「右侧面板 ∈ [380, 480]」+「画布存在」，不断言画布高度受限。
- 需要新增「expanded / large 模式下 canvas 高度 ≤ 容器可用高度」断言。
- 现有用例若依赖「画布按宽度撑满」的具体数值（如 `canvas.size.width >= panelWidth * 3` 等）需要审视。

## Confirmed Decisions (user-approved 2026-05-17)

- ✅ **采用 Approach A: 左列同样采用 Column + Expanded 高度优先骨架**。
- expanded / large 的 useSidePanel 分支左列从 `SingleChildScrollView > Column(stretch) > AspectRatio(1, Canvas)` 重构为 `Column(Expanded(Center(AspectRatio(1, GridPreviewCanvas))) + warning)`。
- `_SourceSizeWarning` 紧贴画布下方，固定高度（与 compact 一致）。
- 不再用 `SingleChildScrollView` 包左列——左列不滚动（warning 只有一行，不会引起溢出）。
- 右侧 `SizedBox(width: panelWidth, child: SingleChildScrollView(GridControlsPanel))` **不变**（继续内部滚动）。
- 双栏左右 width 计算（`panelWidth = clamp(380, container * 0.25, 480)`）**不变**。

## Requirements

- expanded / large 模式 body 改为：
  ```dart
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxWidth - 16).clamp(0.0, double.infinity);
        final panelWidth = (available * 0.25).clamp(
          _kGridControlsPanelMinWidth,
          _kGridControlsPanelMaxWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,  // ← 改成 stretch 让左列拿到 row 高度
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: const GridPreviewCanvas(),
                      ),
                    ),
                  ),
                  if (sourceTooSmall) ...[
                    const SizedBox(height: 12),
                    _SourceSizeWarning(...),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: panelWidth,
              child: const SingleChildScrollView(child: GridControlsPanel()),
            ),
          ],
        );
      },
    ),
  );
  ```
- `Row.crossAxisAlignment` 从 `CrossAxisAlignment.start` 改为 `CrossAxisAlignment.stretch`，确保左列高度等于 Row 高度（Row 拿到 `LayoutBuilder` 的 maxHeight，即 Padding 之后的容器可用高度）。
- 这样 `Expanded > Center > AspectRatio(1)` 的画布：
  - 容器可用高度 < 左列宽度 → 按高度 fit（正方形边长 = 可用高度 - warning 高度）
  - 容器可用高度 ≥ 左列宽度 → 按宽度 fit（正方形边长 = 左列宽度）
  - 永不超出容器，永不需要外层滚动

## Open Questions

(无 — 方案已确认)

## Acceptance Criteria (evolving)

- [ ] 在 1280×800（典型 expanded）/ 1920×1080（典型 large）/ 2560×1440（4K）三种尺寸下，画布高度 ≤ 容器可用高度（容器高度 = 屏幕高度 - AppBar - padding），不出现整页垂直滚动条。
- [ ] 画布 width == height（正方形）居中显示。
- [ ] 右侧 GridControlsPanel 仍 docked 在右侧、宽度 ∈ [380, 480] dp、内部 SingleChildScrollView 可滚动。
- [ ] compact / medium 体验**无回归**（已通过 task 2 测试覆盖）。
- [ ] grid overlay 在调间距 / 切 GridType 时表现不变。
- [ ] `grid_editor_responsive_test.dart` 中针对 expanded / large 新增「画布尺寸为正方形 + 高度 ≤ 容器可用高度 + 不存在外层垂直 OverflowError」断言并通过。
- [ ] `dart format` / `flutter analyze` / `flutter test` 全部干净。

## Definition of Done

- Tests 覆盖 expanded / large 模式下「正方形 + 不超高 + 不滚动」。
- 三红线全绿。
- `grid_preview_canvas.dart` / `grid_editor_screen.dart` 头部 doc-comment 同步更新。
- spec 沉淀：
  - `responsive-layout.md` 中现有「Compact-mode editor body」pattern 扩写为「Editor body — height-first Column skeleton (compact + side-panel variants)」或新增一个 expanded/large variant 节。
  - responsive behavior table 中 grid_editor 行的 expanded / large 列更新为 height-first 表述。
  - Update or remove 现有 GridPreviewCanvas doc-comment 中「expanded/large fits by **width**」的误导性段落。

## Research Notes

### Cause analysis

`SingleChildScrollView > Column(stretch) > AspectRatio(1)` 给画布一个 `(maxWidth=W, maxHeight=∞)` 的约束，`AspectRatio(1)` 在两个约束都有限时取较小值，但在一个无界时退化为「按有限那一边算另一边」。所以 maxWidth 决定 canvas 边长。要让 height 起作用，必须**给左列一个有限的纵向约束**。

### Feasible approaches

**Approach A: 左列也用 Column + Expanded(Center(AspectRatio(1, Canvas))) 高度优先骨架** (Recommended)

- How it works: 把左列从 `SingleChildScrollView > Column(stretch)` 改成 `Column(Expanded(Center(AspectRatio(1, Canvas))) + warning)`，与 compact 模式的左列对称。`Expanded` 给 `Center` 一个有限的高度约束，`AspectRatio(1)` 在两个约束都有限时取较小边 → 画布为 `min(leftColWidth, availableHeight)` × 同值。warning 用 Flexible(loose) 或固定高度。
- Pros:
  - 与 compact / medium 骨架对称（"统一是 height-first Column"），spec 沉淀更干净
  - 真正解决根因（unbounded → bounded）
  - 自动适配 ultra-wide：宽度大时画布按高度 fit；宽度小时画布按宽度 fit
- Cons:
  - 牺牲掉 expanded 模式下 warning 也可滚动的便利（不过 warning 只有一行，影响小）
  - 既有测试用例中如果依赖「画布按 maxWidth 撑满」的尺寸断言需要调整

**Approach B: 给画布的 AspectRatio 外层加 maxHeight 上限（screen height − chrome）**

- How it works: 维持 SingleChildScrollView 结构，在 AspectRatio 外层包 ConstrainedBox(maxHeight: MediaQuery.sizeOf(context).height - kAppBarHeight - 40)。
- Pros: 改动量最小
- Cons: 估算耦合 AppBar/padding 常量；跨字号/a11y 缩放会失真；不是真正的"height-first"，只是叠加上限

**Approach C: LayoutBuilder 显式算正方形尺寸 + SizedBox**

- How it works: 用 LayoutBuilder 拿 maxWidth + maxHeight，算 `square = min(maxWidth, maxHeight)`，给画布套 SizedBox(width: square, height: square)。
- Pros: 显式表达「正方形 = min(W, H)」语义
- Cons: 需要手动写 LayoutBuilder + SizedBox 逻辑；AspectRatio 已经能做同样的事，多此一举

### Recommendation

倾向 Approach A，与 compact/medium 对称，spec 沉淀也更整洁。

## Out of Scope

- 不引入「按源图实际比例」显示画布（保持 1:1）。
- 不改右侧 GridControlsPanel 的内部排版或宽度 clamp 公式。
- 不改 grid overlay / painter / GridLayout 数学。
- 不改 stitch_editor 的对应布局（虽然概念类似，但 stitch 用的是 sheet 而非 panel，不在本 fix 范围）。
- 不改 \_3\_宫格切图/code.html 等 design mock。

## Technical Notes

- 关键文件：
  - `lib/features/grid/presentation/screens/grid_editor_screen.dart`（核心改动：useSidePanel 分支左列骨架）
  - `lib/features/grid/presentation/widgets/grid_preview_canvas.dart`（doc-comment "fit by width" 描述更新）
  - `test/features/grid/presentation/grid_editor_responsive_test.dart`（新增 expanded/large 不超高断言）
  - `.trellis/spec/frontend/responsive-layout.md`（pattern 扩写 + table 更新）
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/responsive-layout.md`
  - `.trellis/spec/frontend/quality-guidelines.md`
