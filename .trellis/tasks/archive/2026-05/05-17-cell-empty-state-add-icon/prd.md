# 宫格空态加 Icons.add_circle_outline 提示可替换

## Goal

在每个宫格（无论空态还是已替换态）上叠加一枚 `Icons.add_circle_outline`，作为「此格可替换图片」的常驻视觉提示，提升 affordance discoverability——目前空态完全透明，用户不知道这块区域可点击。

## What I already know

* `cell_overlay.dart` 已在 Subtask C 落地，每个宫格挂一个 `CellOverlay`
* 空态 `_EmptyCellTarget` 当前是 `SizedBox.expand()` 透明 hit target，肉眼看不到任何提示
* 已替换态 `_ReplacedCell` 用 `GestureDetector(behavior: opaque)` + `Stack > Positioned Image.memory` 渲染替换图，支持 pinch/pan/longpress 菜单
* 手势竞技场约束：空态 `HitTestBehavior.translucent`（canvas drag 穿透）；已替换态 `HitTestBehavior.opaque`（per-cell 手势独占）

## Requirements

### R1 图标始终可见
* 空态 `_EmptyCellTarget`：在透明 hit target 上叠加 `Icons.add_circle_outline`
* 已替换态 `_ReplacedCell`：在用户图片之上叠加同一图标
* 切换 GridType / 任何 state 变化时不消失

### R2 视觉规格
* 图标：`Icons.add_circle_outline`
* 颜色：`Colors.white`
* 阴影：通过 `Icon.shadows` 属性叠一层柔和阴影（`Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))`）确保任何背景图都看得清
* 尺寸：32 dp（固定值，足够小不喧宾夺主，但足够大可识别）
* 位置：`Center`

### R3 纯装饰不介入手势
* 已替换态：图标包一层 `IgnorePointer`，pinch/pan/longpress 透过图标继续作用于 `_ReplacedCell` 的 `GestureDetector`
* 空态：图标无需 IgnorePointer——空态的 `GestureDetector` 已是 `translucent`，canvas drag 仍能穿透；图标的存在不破坏单击交互（单击仍唤起 picker）

### R4 a11y
* 图标本身不挂 `Semantics`（父 `CellOverlay` 已提供 cell-level 标签）
* `excludeSemantics: true` 可加可不加——若 Flutter 默认将装饰 Icon 当作合并子节点，本小姐倾向加 `ExcludeSemantics` 以避免重复读屏

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format` clean
* [ ] `flutter test` clean（更新 `cell_overlay_test.dart`：断言空态和替换态都能找到 `Icons.add_circle_outline`）
* [ ] 空态宫格 tap 仍正常唤起 picker（既有交互回归通过）
* [ ] 已替换态宫格 pinch/pan/longpress 不受图标影响（既有 drag-isolation 测试不退化）
* [ ] 五种宫格类型（g1x2 / g1x3 / g2x2 / g2x3 / g3x3）的空态都肉眼可见图标

## Definition of Done

* 单元测试覆盖：空态有图标、替换态也有图标
* 现有 `grid_editor_drag_isolation_test.dart` / `cell_overlay_test.dart` 全部通过
* `dart format` + `flutter analyze` + `flutter test` 三件套 clean

## Out of Scope

* 图标响应式尺寸（小宫格自动缩小）——MVP 用固定 32 dp
* 图标动画 / pulse / fade-in
* 图标在用户已替换过的格上长按显示「换 / 删」hint（沿用现有 longpress 菜单语义）
* 替换图标为别的 Material icon（用户已锁 add_circle_outline）

## Technical Approach

单文件改动：`lib/features/grid/presentation/widgets/cell_overlay.dart`

1. 定义一个私有 widget `_CellAddHint`：
   ```dart
   class _CellAddHint extends StatelessWidget {
     const _CellAddHint();
     @override
     Widget build(BuildContext context) => const ExcludeSemantics(
       child: Center(
         child: Icon(
           Icons.add_circle_outline,
           size: 32,
           color: Colors.white,
           shadows: [
             Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
           ],
         ),
       ),
     );
   }
   ```
2. `_EmptyCellTarget.build`：把当前 `SizedBox.expand()` 换成 `Stack(children: [SizedBox.expand(), _CellAddHint()])`，外层 `GestureDetector(behavior: translucent, onTap: …)` 不变
3. `_ReplacedCell.build`：在 `ClipRect > Stack(children: [Positioned Image.memory, _CellAddHint()])` 末尾追加图标层；外层 `GestureDetector(behavior: opaque)` 不变。图标用 `IgnorePointer` 包裹以确保 hit-test 不被截走（虽然 `Icon` 没有内建 hit target，但显式 `IgnorePointer` 让意图清晰）

测试 (`test/features/grid/presentation/cell_overlay_test.dart`)：
* 新增：空态宫格 `find.byIcon(Icons.add_circle_outline)` matchesOneWidget
* 新增：替换后宫格 `find.byIcon(Icons.add_circle_outline)` 仍可找到
* 既有测试不调整

## Decision (ADR-lite)

**Context**: 空态宫格当前完全透明，用户无 affordance 提示「这格可点」。

**Decision**: 在每个宫格的两种状态都叠加 `Icons.add_circle_outline`（白色 + 阴影、无背景、`IgnorePointer` 装饰），不响应自身的 tap 事件——单击空态仍走外层 GestureDetector 唤起 picker，已替换态保持原有 pinch/pan/longpress 不变。

**Consequences**:
* 优点：UX 一致性强，所有格都有 affordance；零手势冲突；改动局限单文件
* 缺点：替换后用户图片中心被图标覆盖，可能轻微影响预览精度（已与用户确认接受）
* 风险：小宫格（如 2×3 phone 横屏）32 dp 占比偏大——MVP 接受，未来若投诉再做响应式

## Technical Notes

* 关键文件：`lib/features/grid/presentation/widgets/cell_overlay.dart`
* 关键测试：`test/features/grid/presentation/cell_overlay_test.dart`
* `Icon.shadows` 属性来自 Flutter 3.0+，本项目 Flutter 3.10+ 已经支持
* 现有手势契约：empty=translucent / replaced=opaque，本次改动不动这两个 behavior
