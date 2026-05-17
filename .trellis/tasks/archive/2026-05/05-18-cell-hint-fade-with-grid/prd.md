# 宫格 add-icon 跟随网格线一起淡出

## Goal

修复视觉一致性 bug：拖动源图时网格线随 `_isGesturing` 状态 `AnimatedOpacity` 淡出，但 `CellOverlay` 内的 `_CellAddHint` 图标依旧不动。让 hint 图标与网格线严格同步淡出 / 淡入。

## What I already know

### 调查结论

* `grid_preview_canvas.dart::_PreviewSurface` 持有 `bool _isGesturing` 状态：
  * `onScaleStart` → `setState(() => _isGesturing = true)`
  * `onScaleEnd` → `setState(() => _isGesturing = false)`
* 网格线 fade（已实现）：
  ```dart
  AnimatedOpacity(
    opacity: _isGesturing ? 0.0 : 1.0,
    duration: Duration(milliseconds: 150),
    child: IgnorePointer(child: CustomPaint(painter: _GridOverlayPainter(...))),
  )
  ```
* `CellOverlay` 作为 sibling 位于网格线层下方，没有 fade 包裹；其内部 `_CellAddHint`（`Icons.add_circle_outline`）始终满透明度可见
* **不能** 把整个 `CellOverlay` 包进 `AnimatedOpacity`——会把替换格的用户图一起淡出，用户在拖动源图时还要靠替换图判断位置

### 文件影响范围

* `lib/features/grid/presentation/widgets/cell_overlay.dart` — `CellOverlay` 加 `isGesturing` 参数；`_CellAddHint` 包 `AnimatedOpacity` 消费它
* `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` — `for` 循环里把 `_isGesturing` 透传给每个 `CellOverlay`

## Requirements

### R1 hint 图标随源图拖动同步淡出
* `_CellAddHint` 用 `AnimatedOpacity(opacity: isGesturing ? 0.0 : 1.0, duration: 150 ms)` 包裹
* `duration` 与网格线的 fade 一致（150 ms）
* `_isGesturing` 状态来源与网格线相同（同一个 `_PreviewSurfaceState`）

### R2 API 透传
* `CellOverlay` 新增 `final bool isGesturing` 参数（必填，无默认值——防止调用方忘传）
* `_PreviewSurface` 的 `for` 循环将 `_isGesturing` 传入每一个 `CellOverlay`

### R3 替换格的用户图不受 fade 影响
* `_ReplacedCell` 渲染的用户图始终满透明度
* 只有 `_CellAddHint` 透明度跟随 `isGesturing`
* 替换格的 fade 不影响 hit-test / 手势接收（`AnimatedOpacity` 不拦截手势；`IgnorePointer` 已在 `_CellAddHint` 内部保证装饰性）

### R4 空态格行为
* 空态格也叠着 hint 图标——同样 fade
* 拖源图时，空格变成「裸源图切片」（图标隐藏），用户能看清裁剪区域
* 拖动结束 → 图标淡入恢复

## Acceptance Criteria

* [ ] `flutter analyze` clean
* [ ] `dart format` clean
* [ ] `flutter test` clean
* [ ] `CellOverlay` 构造函数 `isGesturing` 参数必填
* [ ] 新增 widget test：构造 `isGesturing: true` 时 `_CellAddHint` 的 `AnimatedOpacity.opacity` 为 `0.0`
* [ ] 新增 widget test：`isGesturing: false` 时 opacity 为 `1.0`
* [ ] 既有 `cell_overlay_test.dart` 测试全部仍通过（构造时补传 `isGesturing: false`）
* [ ] 既有 `grid_preview_canvas_drag_test.dart` / `grid_editor_drag_isolation_test.dart` 等不退化

## Definition of Done

* 单文件 `cell_overlay.dart` 加属性；单文件 `grid_preview_canvas.dart` 改循环；2 个新 widget test
* `dart format` + `flutter analyze` + `flutter test` 三件套 clean

## Out of Scope

* per-cell pinch/pan 时也 fade（已与用户确认严格只随源图拖动）
* fade duration 改为非 150 ms 的值
* 自定义 fade curve / animation 曲线
* 替换格用户图的 fade

## Technical Approach

**1. `cell_overlay.dart` 修改**

```dart
class CellOverlay extends ConsumerWidget {
  const CellOverlay({
    super.key,
    required this.cellIndex,
    required this.rows,
    required this.cols,
    required this.cellWidth,
    required this.cellHeight,
    required this.sourceCellWidth,
    required this.sourceCellHeight,
    required this.isGesturing,  // 新增
  });
  // ... 既有字段 ...
  final bool isGesturing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ... 既有 Semantics 包裹 ...
    return Semantics(...
      child: SizedBox(...
        child: replacement == null
            ? _EmptyCellTarget(
                onTap: ...,
                isGesturing: isGesturing,  // 透传
              )
            : _ReplacedCell(
                ...
                isGesturing: isGesturing,  // 透传
              ),
      ),
    );
  }
}
```

**2. `_EmptyCellTarget` / `_ReplacedCell` 接收并传给 `_CellAddHint`**

只有 `_CellAddHint` 需要 `isGesturing`；它把 `Icon` 包在 `AnimatedOpacity`：

```dart
class _CellAddHint extends StatelessWidget {
  const _CellAddHint({required this.isGesturing});
  final bool isGesturing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: isGesturing ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: const Center(
            child: Icon(
              Icons.add_circle_outline,
              size: 32,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}
```

**3. `grid_preview_canvas.dart` 循环传参**

```dart
for (var i = 0; i < layout.rects.length; i++)
  Positioned(
    ...
    child: CellOverlay(
      ...
      isGesturing: _isGesturing,  // 新增
    ),
  ),
```

**4. 测试**

* 现有 `cell_overlay_test.dart` 中所有 `CellOverlay(...)` 构造调用需补 `isGesturing: false`
* 新增两个 widget test：
  * `add-circle hint fades to opacity 0 when isGesturing is true`
  * `add-circle hint shows at opacity 1 when isGesturing is false`
  * 通过 `tester.widget<AnimatedOpacity>(find.ancestor(of: find.byIcon(Icons.add_circle_outline), matching: find.byType(AnimatedOpacity)))` 拿到 widget 断言 opacity

## Decision (ADR-lite)

**Context**: 拖源图时网格线已 fade，但 hint 图标依旧满透明度，违反视觉一致性。

**Decision**: 把 `_PreviewSurface._isGesturing` 通过 `CellOverlay` 的新 `isGesturing` 属性透传到 `_CellAddHint`，`_CellAddHint` 内用 `AnimatedOpacity(duration: 150ms)` 与网格线严格同步淡出。替换图用户图本身不受 fade 影响。

**Consequences**:
* 优点：视觉一致；改动局限 2 个文件；fade duration 与网格线对齐用户无感
* 风险：`isGesturing` 必填会破坏既有 `cell_overlay_test.dart` 中所有 `CellOverlay(...)` 构造调用——需要批量补 `isGesturing: false`（已在 AC 列出）
* 替代方案考虑过「内部 listen 一个共享 notifier」，但当前 `_isGesturing` 是 `_PreviewSurfaceState` 本地状态，提升到 Riverpod provider 是过度工程

## Technical Notes

* 关键文件：
  * `lib/features/grid/presentation/widgets/cell_overlay.dart`
  * `lib/features/grid/presentation/widgets/grid_preview_canvas.dart`
  * `test/features/grid/presentation/cell_overlay_test.dart`
* fade duration 来源：`grid_preview_canvas.dart:262` 现有 `Duration(milliseconds: 150)`
* `AnimatedOpacity` 不拦截 hit-test，外层 `IgnorePointer` 是双保险——保留即可
* `_CellAddHint` 必须接收 `isGesturing`，不能从 `Provider` 读因为它是 `StatelessWidget` 且与外部状态解耦更易测试
