# JPG 质量滑块仅释放时重新生成

## Goal

优化导出页面 JPG 质量滑块的交互逻辑：拖动过程中**不**触发预览的重新生成（避免拖动中
不断进入 `PreviewLoading` 与频繁 isolate 任务排队），仅在用户**按压松开**滑块拇指
时才提交质量值并触发一次重新生成。拖动过程中的数字百分比 / 滑块拇指位置仍然实时
跟随用户的手指，保持视觉响应性。

同时把这种"昂贵预览的滑块在 onChangeEnd 提交"的模式沉淀到
`.trellis/spec/frontend/component-guidelines.md`，约束未来新增的滑块控件统一遵循。

## Requirements

- [R1] 拖动滑块时**不调用** `notifier.setQuality`（即不让 `PreviewController` 的
  `_scheduleRender` 被触发）
- [R2] 用户按压松开（`onChangeEnd`）时，提交最终值到 `setQuality`，触发**一次**
  预览重新生成
- [R3] 拖动过程中数字百分比文字 + 滑块拇指位置**实时跟随**用户手指
- [R4] 外部 `value`（即 controller 的 quality）发生变化时（例如 PNG → JPG 切换
  令 state.quality 回到 100，或父组件 rebuild），`_QualitySlider` 内部草稿值需
  同步刷新
- [R5] 在 `.trellis/spec/frontend/component-guidelines.md` 的 `## Props Conventions`
  下新增一节："Convention: 重渲染昂贵的预览滑块应在 `onChangeEnd` 提交"

## Acceptance Criteria

- [ ] 拖动滑块过程中，`exportControllerProvider` 的 `quality` 字段**保持不变**
- [ ] 拖动滑块过程中，数字百分比文字与滑块拇指位置**实时跟随**手指
- [ ] 用户松开滑块时，`setQuality` 被调用恰好一次，参数为最终落点的整数值
- [ ] 当用户拖动到一半放弃（拖出 → 拖回原值后松开），松开时由 `setQuality` 内部
      `if (state.quality == clamped) return;` 短路，不触发不必要的预览重渲
- [ ] 切换 PNG → JPG 后再次显示 slider，本地草稿与 controller 同步
- [ ] 既有测试 `format_quality_card_test.dart` 全部通过
- [ ] 新增 widget 测试：模拟拖动期间断言 `setQuality` 未被调用，松开后才被
      调用一次
- [ ] `component-guidelines.md` 新增 convention，标题、Rationale、Example 三段
      齐全

## Definition of Done

- Tests added/updated（widget 测试覆盖"拖动不提交 / 松开才提交"）
- `flutter analyze` 干净
- `dart format .` 通过
- `flutter test` 全绿
- spec 新增 convention 后，未来 reviewer 能从文档中查到此约束

## Technical Approach

**核心改造**：把 `_QualitySlider` 从 `StatelessWidget` 改为 `StatefulWidget`，内部
维护 `_draftValue`：

```dart
class _QualitySlider extends StatefulWidget {
  const _QualitySlider({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  State<_QualitySlider> createState() => _QualitySliderState();
}

class _QualitySliderState extends State<_QualitySlider> {
  late int _draftValue = widget.value;

  @override
  void didUpdateWidget(_QualitySlider old) {
    super.didUpdateWidget(old);
    // External value updates (e.g. PNG→JPG re-show, or future preset
    // resets) win over an unmounted draft. While the user is actively
    // dragging, _draftValue is already in sync via setState, so this
    // branch only fires on real external mutations.
    if (widget.value != old.value && widget.value != _draftValue) {
      _draftValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... uses _draftValue for "$value%" text and Slider.value
    return Slider(
      value: _draftValue.toDouble().clamp(...),
      min: kMinExportQuality.toDouble(),
      max: kMaxExportQuality.toDouble(),
      divisions: kMaxExportQuality - kMinExportQuality,
      onChanged: (v) => setState(() => _draftValue = v.round()),
      onChangeEnd: (v) => widget.onChanged(v.round()),
    );
  }
}
```

**为什么不改 Controller 加 `commit` 参数**：会破坏 `ExportState` 不可变契约，且
让 controller 知道"拖动中"这种 UI 概念，违反 clean architecture。本地化在
widget 内更符合 SRP。

**为什么不改 PreviewController 的 debounce 策略**：debounce 在拖动中仍会同步把
state 切到 `PreviewLoading`（`preview_controller.dart:218-220`），加长 debounce 反而
让用户感觉"卡"。从源头不触发 `setQuality` 是更干净的解。

## Decision (ADR-lite)

**Context**: 当前 `_QualitySlider.onChanged` 每次值变化都立刻调用 `notifier.setQuality`，
触发 `PreviewController._scheduleRender` 把 state 切到 `PreviewLoading` + 排队 300ms 后
的 isolate 任务。拖动一次会产生数十次 state 写入与 UI 重绘，用户感觉"预览在闪"。

**Decision**: 把 `_QualitySlider` 改为 StatefulWidget，本地维护 `_draftValue`，
`Slider.onChanged` 仅 setState 本地草稿，`Slider.onChangeEnd` 才向上提交。
PreviewController / ExportController / ExportState 全部不动。
同时在 spec 中沉淀这条"昂贵预览的滑块应在 onChangeEnd 提交"的约定。

**Consequences**:
- ✅ 拖动期间零次跨层 state 写入，预览不再闪烁
- ✅ 不破坏 controller / state 不可变契约
- ✅ 模式可复用：spec 记录后，未来其他滑块可按需照此模式迁移
- ⚠️ 引入本地 state，但仅限单 widget 内（10 行级别），可控
- ⚠️ widget 测试需要新增"拖动不提交"用例，覆盖 onChangeEnd 行为

## Out of Scope

- 不改 `ExportController` / `ExportState` 的接口或语义
- 不调整 `PreviewController` 的 debounce 时间或调度逻辑
- 不修改 `Slider` 的视觉样式（颜色 / 高度 / divisions）
- 不为长图编辑器（字幕高度、图片间距、外边距、圆角）和栅格编辑器
  （`_SliderSheet`）的其他滑块做同类改造——它们走的是同步重建管线，本次先不
  扩散；spec 一旦记录后未来需要时再分别迁移

## Technical Notes

- 受影响文件：
  - `lib/features/export/presentation/widgets/format_quality_card.dart`
    （`_QualitySlider` Stateless → Stateful）
  - `test/features/export/presentation/format_quality_card_test.dart`
    （新增拖动断言）
  - `.trellis/spec/frontend/component-guidelines.md`（新增 convention）
- 参考链路：
  - `Slider.onChangeEnd` Flutter 官方 API
  - 既有 spec 章节：`component-guidelines.md` → `## Props Conventions` →
    `### Convention: Require a typed mode parameter when a widget feeds a .family provider`
    （格式参考）
  - 现存预览管线 debounce：`lib/features/export/presentation/providers/preview_controller.dart`
    `kPreviewDebounce = 300ms`
- 范围决策来源：用户在 brainstorm 中选择"仅导出 JPG 质量滑块 + 沉淀到 spec/frontend"

## Implementation Plan

单 PR 实现（小改动 + spec 沉淀），分 3 个 commit 序列：
1. **PR-step-1**: 改造 `_QualitySlider` 为 StatefulWidget + 调整既有测试以兼容
   行为变化
2. **PR-step-2**: 新增 widget 测试覆盖"拖动期间不提交 / onChangeEnd 提交一次"
3. **PR-step-3**: 在 `component-guidelines.md` 新增 convention 章节
