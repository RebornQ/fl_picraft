# 长图拼接：StitchControlsSheet 高度上限收紧

> **Parent**: [`05-20-mobile-control-bar-compact`](../05-20-mobile-control-bar-compact/prd.md)

## Goal

在 compact / medium 窗口下，把 `StitchControlsSheet` 的高度上限从
`max(200, min(screenHeight * 0.28, 360))` 调整为
`max(200, min(screenHeight * 0.22, 320))`，把多出的垂直空间还给预览画布。

## Requirements

* `StitchControlsSheet.build` 中的 `maxHeight` 计算改为
  `math.max(200, math.min(screenHeight * 0.22, 320))`。
* 不动：sheet 内部 `SingleChildScrollView` + `padding: EdgeInsets.only(bottom: 80)`、
  `StitchControlsPanel` 本身、Material elevation / 圆角等 chrome。
* 不动：expanded / large 路径（`stitch_editor_screen.dart` 内的右侧面板分支）。
* 同步更新 sheet 文件顶部的 Dartdoc 注释（描述高度上限的那一段）。

## Acceptance Criteria

* [ ] `stitch_controls_sheet.dart` 中 `maxHeight` 公式更新为 `min(0.22h, 320)` / floor 200。
* [ ] 顶部 Dartdoc 中 "caps its own height at `min(screenHeight * 0.28, 360)`" 改为新数值。
* [ ] compact (360×800 dp 测试窗口) 下 sheet 高度 = **200 dp**（`800 * 0.22 = 176 < 200`，
  floor 200 兜底；比例分支只在 viewport 高度 ≥ 909 dp 时才生效）。
* [ ] medium (720×412 dp 横屏) 下 sheet 高度 = **200 dp**（`412 * 0.22 ≈ 91 < 200`，
  floor 200 兜底）—— **floor 必须保留**，确保超短窗口仍可用。
* [ ] tall viewport (≥ 909 dp 高) 下 sheet 高度命中比例分支：例如 1000 dp → 220 dp；
  ≥ 1455 dp 触发 ceiling 320 dp。三个分支（floor / ratio / ceiling）都要被测试覆盖。
* [ ] expanded / large 视觉无变化（侧边面板路径未触碰）。
* [ ] `flutter analyze` 干净；现有 stitch editor widget 测试（若有 sheet 高度断言）同步更新。
* [ ] 新增 widget 测试：用 `MediaQuery` 模拟 800 dp / 412 dp 高度，断言 `ConstrainedBox`
  的 `maxHeight` 计算正确（或断言渲染高度上限）。

## Technical Approach

**Diff 预估**：`stitch_controls_sheet.dart` 单文件 ~3 行（公式 + 注释）+ Dartdoc 描述
更新；测试 ~1 个文件新增/修改。

```dart
// Before
final maxHeight = math.max(200.0, math.min(screenHeight * 0.28, 360.0));

// After
final maxHeight = math.max(200.0, math.min(screenHeight * 0.22, 320.0));
```

## Out of Scope

* `StitchControlsPanel` 内部 padding / SizedBox / Divider 调整
* `StitchImageStrip` 高度
* expanded / large 侧边面板
* 控件功能 / 排序变更

## Technical Notes

* 关键文件：`lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart`
* 不需要触碰：`stitch_controls_panel.dart`、`stitch_editor_screen.dart`
* 历史决策：`archive/2026-05/05-18-long-image-stitch-toolbar-and-subtitle-mode/prd.md`
  曾把上限从 0.4 → 0.28；本次再调一档到 0.22。
