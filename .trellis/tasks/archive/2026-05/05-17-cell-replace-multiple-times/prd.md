# 宫格支持反复替换图片

## Goal

修复用户报告的「宫格只能覆盖一次」问题。根因是 `_ReplacedCell` 的 `GestureDetector` 没有 `onTap` handler——替换后单击宫格无任何反应，用户必须发现并使用长按菜单才能二次替换。本任务给已替换的宫格加一个 tap 入口，让 tap 行为在空态/替换态两边对齐：「点哪儿换哪儿」。

## What I already know

### 调查结论

* **Controller 端无 bug**：`setCellImage` 始终 `next[cellIndex] = CellReplacement(image: image)`，多次调用会正常覆盖（`grid_editor_provider.dart:169–178`）
* **`pickCellImage` 也正确**：每次都通过 `imageImportRepositoryProvider.pickFromGallery` 拿新图后调 `setCellImage`
* **UI 端的「只能一次」错觉**：
  * 空态 `_EmptyCellTarget` 有 `onTap: pickCellImage` → 第一次替换 OK
  * 替换后切到 `_ReplacedCell`，其 `GestureDetector` 只挂了 `onScaleStart/Update/End` + `onLongPressStart` → tap 落入手势竞技场无人认领 → 无任何反馈
  * 唯一的二次替换路径：longpress → 菜单 → "替换图片"——发现性极差
* 已替换态保留 `behavior: HitTestBehavior.opaque`，pinch / pan / longpress 仍归 cell 独占

### 单文件影响范围

* `lib/features/grid/presentation/widgets/cell_overlay.dart` (`_ReplacedCell.build`)
* `test/features/grid/presentation/cell_overlay_test.dart`（追加替换-tap 二次替换 widget test）

## Requirements

### R1 已替换格的 tap 直接唤起 picker
* `_ReplacedCell` 的 `GestureDetector` 新增 `onTap: () => ref.read(gridEditorControllerProvider.notifier).pickCellImage(cellIndex)`
* 单击后立即打开图库（不弹中间确认框、不走 longpress 菜单）

### R2 既有手势不退化
* `onScaleStart/Update/End`、`onLongPressStart` 保留不变
* Flutter 手势竞技场自动区分：
  * 单击（down + up 无位移）→ `onTap` 胜出
  * 按住 + 双指或拖动 → `onScale*` 胜出
  * 长按不动 → `onLongPressStart` 胜出
* `behavior: HitTestBehavior.opaque` 不变（per-cell 独占）

### R3 空态行为不变
* `_EmptyCellTarget` 已有 `onTap: pickCellImage`，本次不动

### R4 controller / state 无改动
* `setCellImage` / `pickCellImage` 的实现保持现状（已正确支持反复覆盖）

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format` clean
* [ ] `flutter test` clean
* [ ] 新增 widget test：已替换格 tap → mock picker 被调用 / state 更新为新图
* [ ] 既有 `cell_overlay_test.dart` 中的 pinch / longpress 菜单 / drag-isolation 测试全部仍通过
* [ ] 手动复测：1×2 / 2×2 / 3×3 任一格连续替换 ≥ 3 次，每次都生效

## Definition of Done

* 修复 + 新增 1 个 widget test
* `dart format` + `flutter analyze` + `flutter test` 三件套 clean

## Out of Scope

* 改变 longpress 菜单的项（保留「替换 / 重置 / 移除」）
* 改变 add-circle hint 图标的交互（仍是装饰）
* 改变空态交互
* 增加 controller 层 unit test 验证「连续 setCellImage」（controller 本就正确，且会被 widget test 覆盖到）

## Technical Approach

单点 patch：在 `_ReplacedCell` 的 `GestureDetector` 上挂 `onTap`：

```dart
return GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => ref
      .read(gridEditorControllerProvider.notifier)
      .pickCellImage(widget.cellIndex),
  onLongPressStart: ...
  onScaleStart: ...
  ...
);
```

Widget test 追加：
* 准备一个 mock `ImageImportRepository`，让两次 `pickFromGallery` 分别返回 imageA、imageB
* 先 `setCellImage(idx, imageA)` 把格设为已替换态 → pump
* 再 tap 该 cell → `pumpAndSettle`
* 断言：mock 的 `pickFromGallery` 被再次调用；`state.cellReplacements[idx].image == imageB`

或者更简单：覆盖现有 `tap on replaced cell triggers picker` 测试场景，使用现有 harness 的 picker fake。

## Decision (ADR-lite)

**Context**: 当前已替换格无 tap 入口，二次替换必须走 longpress 菜单——发现性差到被误认为 bug。

**Decision**: 在 `_ReplacedCell.GestureDetector` 上挂 `onTap` → 直接 `pickCellImage`。tap 路径在空态 / 替换态语义统一为「点 = 换」。

**Consequences**:
* 优点：UX 一致；无需扩 controller / state；3 行内修复
* 风险：误触——用户原本想拖动调整但触发了 tap → picker 弹出。Flutter 手势竞技场会区分 tap（无位移）vs scale（带位移），实际误触概率低
* 替代方案 longpress 菜单仍存在 → 用户还能走「替换 / 重置 / 移除」三选一

## Technical Notes

* 关键文件：
  * `lib/features/grid/presentation/widgets/cell_overlay.dart`（`_ReplacedCell.build` 第 169 行起）
  * `test/features/grid/presentation/cell_overlay_test.dart`
* Flutter `GestureDetector` 自带 tap vs scale vs longpress 仲裁，不需要额外 `RawGestureDetector`
* 现有 longpress 菜单中的「替换图片」项保留——某些场景用户可能更喜欢菜单的明示
