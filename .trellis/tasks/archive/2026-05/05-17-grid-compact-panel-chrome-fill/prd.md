# extend side panel chrome to compact and medium

## Goal

修复 grid editor 在 compact / medium 模式（手机竖屏、平板竖屏、窄窗口）下控制栏下方出现大片留白的问题。把 expanded/large 已经用上的 surface chrome 容器扩展到 compact/medium，并把 `Flexible(loose)` 改为 `Expanded(fit=tight)`——chrome 强制填满 Column 剩余空间，原本暴露的纯白区被 chrome 背景覆盖；内部 GridControlsPanel 仍保持顶部对齐 + SingleChildScrollView 内部滚动。

## What I already know

### 当前 compact / medium 实现 (`grid_editor_screen.dart:290-310`)

```dart
return Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),  // 96 = FAB clearance
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Expanded(
        child: Center(child: AspectRatio(aspectRatio: 1, child: GridPreviewCanvas())),
      ),
      if (sourceTooSmall) ...[const SizedBox(height: 12), _SourceSizeWarning(...)],
      const SizedBox(height: 16),
      const Flexible(
        fit: FlexFit.loose,
        child: SingleChildScrollView(child: GridControlsPanel()),
      ),
    ],
  ),
);
```

### 留白根因 (Flex algorithm)

Column 的 `Expanded(flex=1, fit=tight)` 与 `Flexible(flex=1, fit=loose)` 都参与 flex 分配：
- Total free space = container_h - inflexible_size
- Each flex child 被分配 `free_space * 1 / 2`
- Expanded(tight) 强制占据它的 share = `free/2`
- Flexible(loose) 取 `min(intrinsic, share)`

当 viewport 高（如 360×900 手机或 768×1024 iPad 竖屏）时：
- `share = free/2 ≈ 400+ dp`
- `panel intrinsic ≈ 350 dp`
- Flexible(loose) 取 350，剩下的 (share - 350) ≈ 50+ dp 留在 Column 底部（mainAxisAlignment=start）
- 这段空白没有任何 chrome 覆盖，就是裸的页面背景，**用户看到的"控制栏下方大片留白"**

### Expanded/large 已经解决 (`grid_editor_screen.dart:213-260`)

上一轮 task `05-17-grid-reactive-canvas-and-panel-chrome` 已经给 expanded/large 右列加了：
- `Container(decoration: BoxDecoration(color: colorScheme.surfaceContainerLow, borderRadius: 16, border: outlineVariant), clipBehavior: antiAlias)`
- 内部 `SingleChildScrollView(padding: 16, child: GridControlsPanel())`
- key: `kGridControlsPanelChromeKey`

本任务把同样的 chrome 扩展到 compact/medium，使两个分支视觉一致。

### Spec contracts to refresh

`.trellis/spec/frontend/responsive-layout.md`：
- "## Pattern: Editor body — height-first Column skeleton (single-column + side-panel variants)" 中 compact / medium 代码示例 (line ~196) 使用 `Flexible(fit: FlexFit.loose)` —— 要改为 Expanded + chrome
- "### Gotcha: use `Flexible(loose)` — **not** `Expanded` — for the controls slot in a height-first `Column`" (line ~390) —— 这条 Gotcha 是在**无 chrome 时**才正确（避免画布与控件之间的视觉裂缝）。**加 chrome 后** Gotcha 反转：应该用 Expanded + chrome 填满，避免下方裸留白
- "### Convention: Caller decoration variants" —— 已经存在，需要补充「无论 compact 还是 side-panel variant，grid editor 都使用 surface chrome；stitch 仍 bare」

### 受影响测试

`test/features/grid/presentation/grid_editor_responsive_test.dart`：
- 现有 compact 测试 `compact body uses height-first Column skeleton (no outer ListView)` 断言：
  - `find.ancestor(of: GridControlsPanel, matching: SingleChildScrollView) → findsOneWidget`
  - canvas square + `canvas.size.height <= 640`
  - 加 chrome 后 GridControlsPanel 的祖先链是 `SingleChildScrollView → Container(chrome) → Expanded → Column → Padding`，断言仍然 pass
- 新增测试: compact / medium 模式下 chrome 高度 = canvas slot 之外的所有剩余（Column 中 chrome 的 Expanded 占据 free_space - canvas Expanded share = free_space/2，约 200+ dp，与 chrome 是 Container 包装的 panel 内容应当一致，但 chrome 视觉高度等于 Expanded 分配）

## Confirmed Decisions (user-approved 2026-05-17)

- ✅ **采用 Approach A**: compact / medium 也加 surface chrome + `Expanded` 填满剩余空间。
- chrome 装饰参数与 expanded/large **完全一致**: `surfaceContainerLow` + `outlineVariant` + 16 dp 圆角 + `clipBehavior: antiAlias` + 内部 `SingleChildScrollView(padding: 16, child: GridControlsPanel())`。
- 复用 **同一个** `kGridControlsPanelChromeKey`（任意时刻只有一个 chrome 会被渲染，因为 compact 与 useSidePanel 分支互斥）。
- `_SourceSizeWarning` 仍保持画布与 chrome 之间作为固定高度提示条，不被 chrome 包裹。
- bottom 96 dp FAB clearance 保留不变；chrome 距 viewport 底部仍是 96 dp（FAB 在 chrome 之上不重叠）。
- ⚠️ **反转 spec gotcha**: 「use `Flexible(loose)` — not `Expanded` — for the controls slot」在**裸 panel** 场景才正确；加了 chrome 后改为「use `Expanded` — not `Flexible(loose)` — when the controls slot has chrome (to avoid bare background leaks below the chrome)」。spec 文档要明确**两种场景**的不同选择。

## Requirements

- compact / medium 分支 (`_GridEditorBody.build` 中 `useSidePanel == false` 分支) 改为：
  ```dart
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(
          child: Center(child: AspectRatio(aspectRatio: 1, child: GridPreviewCanvas())),
        ),
        if (sourceTooSmall) ...[
          const SizedBox(height: 12),
          _SourceSizeWarning(colorScheme: colorScheme, textTheme: textTheme),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            key: kGridControlsPanelChromeKey,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: GridControlsPanel(),
            ),
          ),
        ),
      ],
    ),
  );
  ```
- doc-comment (内部 layout breakdown line ~283-290) 同步更新：把 `Flexible(loose)` 段落改为 `Expanded + Container(surface chrome)` + 解释「加 chrome 反转了 Flexible vs Expanded 的取舍」。
- 顶部 doc-comment 表格 compact / medium 行同步 chrome 描述。
- 抽取 chrome decoration 为私有 `BoxDecoration _panelChromeDecoration(ColorScheme cs)` helper（或 `Widget _panelChromeContainer({required Widget child, required ColorScheme cs})`），让两个分支复用，避免 decoration 字段在两处漂移。

## Acceptance Criteria

- [ ] compact 360×900 / medium 768×1024 / iPad 竖屏下：控制栏下方**无任何裸白色留白**；chrome 背景从画布之下 16 dp 一直延伸到 FAB 上方 96 dp。
- [ ] chrome 与 expanded/large 视觉一致（颜色、圆角、边框、内 padding 完全一致）。
- [ ] GridControlsPanel 仍顶部对齐；内容超过 chrome 高度时 SingleChildScrollView 在 chrome 内部滚动。
- [ ] canvas 仍正方形、居中、按 `min(maxWidth, available_height/2)` fit（Column 分配机制不变）。
- [ ] expanded / large 视觉无回归（chrome 装饰参数复用 helper 后表现一致）。
- [ ] 现有 compact / medium 测试不破坏；新增 compact / medium 模式 chrome 高度 + decoration 断言。
- [ ] `dart format` / `flutter analyze` / `flutter test` 全绿。

## Definition of Done

- 三红线全绿。
- doc-comment 完整反映新结构。
- spec 沉淀：
  - `responsive-layout.md` 的 "Pattern: Editor body" 中 compact / medium 代码示例更新为 Expanded + chrome
  - 反转 "Gotcha: use Flexible(loose) — not Expanded" 为「**双模 Gotcha**」: 无 chrome → Flexible(loose); 有 chrome → Expanded
  - "Convention: Caller decoration variants" 补充说明: grid editor 在所有 size class 都加 chrome（不只 expanded/large）

## Out of Scope

- 不改 stitch_editor 的 compact / medium 视觉（stitch 用 sheet，与 grid 不一样）
- 不改 panelWidth clamp / GridLayout / Painter / GridPreviewCanvas
- 不改 chrome 装饰参数（颜色/圆角/边框/padding 与 expanded/large 完全一致）
- 不引入 `IntrinsicHeight` 等可能引发布局性能问题的 widget

## Technical Notes

- 关键文件：
  - `lib/features/grid/presentation/screens/grid_editor_screen.dart`（compact/medium 分支重构 + 抽 helper）
  - `test/features/grid/presentation/grid_editor_responsive_test.dart`（新增 compact 模式 chrome 断言）
  - `.trellis/spec/frontend/responsive-layout.md`（pattern 代码 + Gotcha 反转 + Caller decoration variants 扩写）
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md`（theme color usage）
  - `.trellis/spec/frontend/responsive-layout.md`（Pattern + Gotcha + Caller decoration variants）
  - `.trellis/spec/frontend/quality-guidelines.md`（三红线）
