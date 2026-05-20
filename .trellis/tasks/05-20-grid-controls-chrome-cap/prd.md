# 宫格切图：compact chrome slot 改 Flexible + ConstrainedBox

> **Parent**: [`05-20-mobile-control-bar-compact`](../05-20-mobile-control-bar-compact/prd.md)

## Goal

宫格切图编辑器的 compact / medium 单列骨架下，控制面板 chrome slot 当前用 `Expanded`
与画布**平分**剩余高度——这正是用户感觉"控制栏偏大"的根因。改为
`Flexible(fit: FlexFit.loose) + ConstrainedBox(maxHeight: math.min(screenHeight * 0.36, 380))`，
让画布通过 `Expanded` 继续抢占剩余高度，把多出来的空间还给预览。

## Requirements

* `grid_editor_screen.dart` 中 compact / medium 路径（line 393–424 周边的 `Padding +
  Column` 骨架）：
  * 第二个 `Expanded(child: _buildControlsPanelChrome(...))` 改为：
    ```dart
    Flexible(
      fit: FlexFit.loose,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(screenHeight * 0.36, 380),
        ),
        child: _buildControlsPanelChrome(
          context,
          bottomPadding: hasSource ? 80 : 16,
        ),
      ),
    )
    ```
  * `screenHeight` 通过 `MediaQuery.sizeOf(context).height` 读取（在 `build` 内部）。
* `_buildControlsPanelChrome` 内部 `SingleChildScrollView` 不动 —— 上限以内的内容滚动行为
  保持现状。
* 不动：左侧 canvas `Expanded`、`_SourceSizeWarning` banner、FAB clearance（80 dp）。
* 不动：expanded / large 路径（侧边面板分支 line 266–349）。
* 同步更新文件顶部相关 Dartdoc 注释（描述 compact 骨架的那段）。

## Acceptance Criteria

* [ ] compact (360×900 dp) 下控制面板 chrome 高度 ≈ 318 dp（容差 ±15 dp），
  约为可用空间（≈ 796 dp）的 2/5；canvas slot 拿到 3/5（≈ 478 dp）。
* [ ] medium (720×1200 dp) 下 chrome 高度 ≈ 438 dp（容差 ±20 dp），
  内部滚动正常，不出现 RenderFlex overflow。
* [ ] expanded / large 视觉无变化（侧边面板路径未触碰）。
* [ ] FAB 仍在 chrome 之上浮动，按钮命中区不被画布占据。
* [ ] 顶部 Dartdoc "Layout breakdown" 段落更新：说明 chrome 改用 `Expanded(flex: 2)` +
  canvas `Expanded(flex: 3)`；并附 ADR 修正说明（先前 Flexible+ConstrainedBox 失败原因）。
* [ ] `flutter analyze` 干净；现有 grid editor widget 测试不破。
* [ ] 重写 responsive 测试覆盖 3:2 flex 契约（compact / medium 各一条）。

## Technical Approach

**Diff 预估**：`grid_editor_screen.dart` 单文件 ~10 行（结构 + import math + 注释）+
测试 ~1 个文件新增/修改。

```dart
// Before (line 413–421)
Expanded(
  child: _buildControlsPanelChrome(
    context,
    bottomPadding: hasSource ? 80 : 16,
  ),
),

// After
final screenHeight = MediaQuery.sizeOf(context).height;
final controlsMaxHeight = math.min(screenHeight * 0.36, 380.0);
// ... in the Column children:
Flexible(
  fit: FlexFit.loose,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxHeight: controlsMaxHeight),
    child: _buildControlsPanelChrome(
      context,
      bottomPadding: hasSource ? 80 : 16,
    ),
  ),
),
```

**注意**：`grid_editor_screen.dart` 当前**没有** `import 'dart:math' as math;`，需要新增。

## Out of Scope

* `GridControlsPanel` / `GridParameterCards` / `GridTypeSelector` 内部 padding / 高度
* expanded / large 侧边面板
* canvas `AspectRatio` 行为
* 控件功能 / 排序变更

## Technical Notes

* 关键文件：`lib/features/grid/presentation/screens/grid_editor_screen.dart`
* 不需要触碰：`grid_controls_panel.dart`、`grid_type_selector.dart`、`grid_parameter_cards.dart`
* `_buildControlsPanelChrome` 已经把 `SingleChildScrollView` 包在 chrome 内部，因此
  `ConstrainedBox` 限高后超出部分继续滚动，无溢出风险。
* Spec：`.trellis/spec/frontend/responsive-layout.md`「side-panel variant」段强调 compact
  路径应让 canvas 用 `Expanded` 抢占高度；本次改动正是落实这条 spec 的进一步收敛。

## Decision (ADR-lite, revised)

**Context**: 原 PRD 选择 `Flexible(fit: FlexFit.loose) + ConstrainedBox(maxHeight:
min(screenHeight * 0.36, 380))` 来让 chrome 让出空间给 canvas。实机验证发现：
chrome 收缩到内部控件的 intrinsic 高度，在 chrome 下方暴露一条页面背景条
（高度 ≈ `cap − intrinsic_panel_h`）。该症状正是
`.trellis/spec/frontend/responsive-layout.md` "Chrome-wrapped panel wrapped in
Flexible(loose)" 失配警告所描述的，最早的"chrome 让位"实现误把 `Flexible(loose)`
当作通用工具，没有意识到 chrome decoration 只画到内容 intrinsic 高度。

**Decision**: 保留 `Expanded(chrome)` 不让 chrome 收缩；改用两侧 `Expanded` 的
**flex 权重倾斜**调整画布/控制栏比例：

* `Expanded(flex: 3, ...)` 包 canvas → 拿到约 60 % 列剩余高度
* `Expanded(flex: 2, ...)` 包 chrome → 拿到约 40 % 列剩余高度（chrome 背景仍
  填满整个 slot，无泄漏）

并辅以**轻量控件压缩**让 chrome 在 40 % 的份额里不显拥挤：

* `_BentoCard.height`：128 → 104（节省 24 dp）
* `GridTypeSelector` 横向 ListView 高度：104 → 92（节省 12 dp）

**Consequences**:
* chrome 背景永远画满 `Expanded` slot —— 无页面背景泄漏（修复原本想解决但走错路的问题）。
* canvas 在 compact (360×900) 上从原 1:1 split 的 ~398 dp slot 提升到 ~478 dp slot。
  在 1:1 width-bounded 的窄屏上 canvas 仍 ≈ 328 dp（被列宽限制），但 chrome 收缩到
  ~318 dp，让画布周围视觉空间更显宽松。
* 控件压缩共节省 ~36 dp 内部 intrinsic 高度，cancels out 大部分由 flex 1:1 → 3:2
  导致的 chrome 收缩压力。
* 不再依赖 `MediaQuery` 读屏高 + `math.min` 公式，依赖更少。
* spec 中"Chrome-wrapped panel + cap" 第三变体被回滚（属于错误工具）；新增 Lesson
  "tune flex weight, not ConstrainedBox-on-chrome" 沉淀经验。

**Supersedes**: 本 PRD 原 Technical Approach 中的 Flexible+ConstrainedBox 方案。
原方案在文件内仍保留作为历史记录，但实现以本节为准。

## Addendum: GridTypeSelector 默认选中可见性修复

**Context**: 默认 `gridType = GridType.g3x3`（九宫格）位于 `kGridTypeSelectorOrder` 末位
（index 4 / 5）；`GridTypeSelector` 原本是无 ScrollController 的 ListView.separated，初始
挂载时列表停在 index 0，用户首屏看不到选中状态。

**Decision**: 把 `GridTypeSelector` 转为 StatefulWidget，持有 ScrollController；
initState + didUpdateWidget 中通过 PostFrameCallback 触发 animateTo，把选中卡片滑入
可见区域。卡片步长按 `minWidth(120) + separator(12) = 132 dp` 估算
目标 offset = `index * 132`，再 `clamp(0, maxScrollExtent)` 防止越界；动画 300 ms /
`Curves.easeOut`。

**Additional AC**:
* [ ] 默认 gridType = g3x3 时，editor 首屏 pumpAndSettle 后 ScrollController.offset > 0
  （或选中卡片对应 Finder 在视口内）

**Implementation note**: 改动仅 `lib/features/grid/presentation/widgets/grid_type_selector.dart`
一个文件 + 对应测试新增 3 条（auto-scroll on g3x3 / no-scroll on g1x2 / didUpdateWidget
on value change）。
