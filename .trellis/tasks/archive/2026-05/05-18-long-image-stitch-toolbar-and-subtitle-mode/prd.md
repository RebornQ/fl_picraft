# 长图拼接：工具栏可滚动 + 电影台词模式优化

## Goal

收紧长图拼接编辑器的两块体验：

1. **工具栏腾出空间** — 让 compact/medium 屏的控制面板 Sheet 限定最大高度（≈ 屏幕 40%），
   并加纵向滚动兜底，给预览画布留出更多视觉面积（不压缩控件密度，最小风险且立即降高）。
2. **电影台词模式精修** — 在「仅保留字幕」开启后：隐藏无意义的「图片间距」slider、把字幕高
   度从绝对像素改成相对**首图缩放后高度**的百分比、并新增「自动剪裁黑边」能力（仅字幕模式
   可用、默认 OFF）。

## Background

* 当前工具栏在 compact/medium 屏（手机竖屏）上是 `StitchControlsSheet` → 直接嵌入
  `StitchControlsPanel`，**没有 `SingleChildScrollView` 包裹**，当所有 sliders 全显示时会被
  溢出截断或导致 Column 报 RenderFlex 异常。
* expanded/large 屏（平板/桌面）右侧面板已经在 `SingleChildScrollView` 中（见
  `stitch_editor_screen.dart:159`），compact 路径漏了。
* 电影台词模式（`_layoutMovieSubtitle`）中 `spacing` 被忽略（"bands butt up against each
  other"），UI 仍显示「图片间距」slider —— 用户看到的控件不会生效，会产生困惑。
* 字幕高度 `subtitleBandHeight` 当前是绝对像素（`50–500`，默认 `120`）。Bilibili 长截图风格
  里字幕条高度通常是「第一张图高度的 10%–15%」，绝对像素需要用户根据每组素材分辨率手动调
  整，体验差。
* 「黑边」现象在电影台词模式特别明显：源帧常带 letterbox（电影画幅 21:9，源帧 16:9 时上下有
  黑边），拼出的长图字幕条上下夹着两道黑色横带，需要手动后处理。当前 repo 没有任何黑边检测
  的代码（`grep "letterbox\|blackBar"` 无结果）。

## What I already know

### 现状代码
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` — 工具栏主体
  （模式 segmented / 字幕 toggle / 字幕高度 slider / 图片间距 / 边框宽度 / 边框颜色 / 圆角）
* `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart` — compact/medium
  外壳（Material elevation + 圆角，**不滚动**）
* `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` — 响应式布局
* `lib/features/long_stitch/domain/entities/stitch_editor_state.dart` — 状态字段：
  `spacing`, `border`, `cornerRadius`, `subtitleOnlyMode`, `subtitleBandHeight`
* `lib/features/long_stitch/domain/usecases/stitch_layout.dart` — `_layoutMovieSubtitle()` 即
  字幕模式 layout 算法（subtitleOnlyMode + vertical + ≥2 张图触发）
* `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart` — 真渲染走 `image`
  包（CPU/Dart，可在 isolate 跑 `compute`），预览画布的 `srcCrops` 已支持每张图独立裁剪 →
  黑边裁剪可挂在 layout 上而无需改渲染管线主流程。
* `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart` — 预览画布（基于
  CustomPainter 绘制 layout 结果）

### 关键常量
* `kMinSubtitleBandHeight = 50`，`kMaxSubtitleBandHeight = 500`，`kDefaultSubtitleBandHeight = 120`
* `kMaxStitchSpacing = 50`，`kMaxStitchBorderWidth = 10`，`kMaxStitchCornerRadius = 48`

## Decisions Log

### 2026-05-18 · Q1 工具栏高度策略 → **「限定 Sheet 最大高度 + 滚动」**（修订）
* **决策**：compact/medium 屏的 `StitchControlsSheet` 限定最大高度为
  `min(screenHeight * 0.4, 360 dp)`（最低保底 200 dp，避免极小屏被压扁），内嵌
  `SingleChildScrollView`，超出部分滚动；不动控件本身的 padding/SizedBox/字号。
* **理由**：用户明确要"降低 Sheet 高度，给画布更多展示空间"；限定最大高度是最直接的方式，
  立即降高且实现风险低。控件密度保持不变以减少视觉返工。
* **落地点**：
  * `StitchControlsSheet.build` 用 `LayoutBuilder` 拿 `MediaQuery.sizeOf(context).height`
    算出 `maxHeight`，外层套 `ConstrainedBox(maxHeight: ...)`
  * 内部嵌 `SingleChildScrollView`（child: `StitchControlsPanel`）
  * expanded/large 路径**不动**（仍走 `stitch_editor_screen.dart` 内现有的右侧面板 +
    `SingleChildScrollView`）

### 2026-05-18 · Q2+Q3 字幕高度百分比方案 → 「基准=首图高度，state 改存百分比」
* **决策**：
  * state 字段 `subtitleBandHeight` (px) → 重构为 `subtitleBandHeightPercent` (0.05–0.50)
  * 范围 5%–50%，默认 12%（≈ 原 120 px 在 1000 px 高图上的表现）
  * `_layoutMovieSubtitle` 入参仍是 `bandHeight` (px)，由 controller 在调用前计算：
    `bandHeight = (firstImageScaledHeight * percent).round()`
  * `firstImageScaledHeight = first.height`（首图 width 即 targetWidth，所以 H_full = 首图原
    高度）
* **理由**：基准与算法中"完整呈现的那张图"语义一致；state 字段语义清晰，避免 px ↔ percent
  双单位带来的混乱。
* **常量变更**：
  * 新增 `kMinSubtitleBandHeightPercent = 0.05`
  * 新增 `kMaxSubtitleBandHeightPercent = 0.50`
  * 新增 `kDefaultSubtitleBandHeightPercent = 0.12`
  * 旧的 `kMin/Max/DefaultSubtitleBandHeight` (px) 删除

### 2026-05-18 · Q4+Q5 自动剪裁黑边方案 → 「仅字幕模式可用，默认 OFF」
* **决策**：
  * 新增 state 字段 `autoTrimBlackBars: bool`（默认 `false`）
  * UI：「自动剪裁黑边」toggle 仅当 `subtitleEffective` 为 true 时显示
  * 算法：对每张源图独立扫描上下两端（不扫左右，因为字幕模式宽度由首图决定，左右黑边不影响
    带状区域），亮度阈值用 `luminance < 16/255`，扫描容差 `< 99% of row pixels meet threshold`
  * 性能：检测结果按 `imported_image identity hash` 缓存（防止 slider 拖动重算），如果计算耗
    时 > 50 ms 移入 isolate
* **触发口径**：toggle 开启后，layout 算法在 `_layoutMovieSubtitle` 内对每张图的 `srcCrop`
  上下边界做内缩；首图全显示的部分一样剪掉上下黑边。
* **理由**：用户主动开启更安全，首次开启可以 snackbar 提示「可能误判，请检查预览」。

## Requirements

### A. 工具栏腾出空间（compact/medium 路径）
* **A1**: `StitchControlsSheet` 内嵌的 `StitchControlsPanel` 用 `ConstrainedBox` +
  `SingleChildScrollView` 包裹：最大高度 `min(screenHeight * 0.4, 360 dp)`，最低保底 200 dp。
  超出部分纵向滚动；不修改 Panel 内部 padding/SizedBox/字号。
* **A2**: expanded/large 路径不动（右侧面板的 `SingleChildScrollView` 已在
  `stitch_editor_screen.dart:159` 内）。

### B. 电影台词模式专属

* **B1（隐藏图片间距）**: 在 `StitchControlsPanel.build` 中，当 `subtitleEffective == true`
  时不渲染「图片间距」slider 那一行（隐藏而非禁用）。其前后的 Divider/SizedBox 也需要联动调
  整以避免视觉断层。
* **B2（字幕高度百分比）**:
  * `StitchEditorState.subtitleBandHeight: double` → `subtitleBandHeightPercent: double`
  * `StitchEditorState.copyWith` / `initial()` 同步更新
  * `StitchEditorController.setSubtitleBandHeight(double px)` → `setSubtitleBandHeightPercent(double pct)`
  * UI 显示 `valueText: '${(percent * 100).round()}%'`，slider 范围 0.05–0.50
  * `StitchRenderRequest.fromState` 内换算：`subtitleBandHeight = (state.images.first.height * state.subtitleBandHeightPercent).round()`（fallback 处理空图列表）
  * `stitch_layout.dart` 内 `_layoutMovieSubtitle` 签名保持不变（仍接 `bandHeight: int`）
  * 已有「图片高度 < 字幕条高度」snackbar 警告逻辑迁移到 controller / panel 内的换算路径
* **B3（自动剪裁黑边）**:
  * 新增 `StitchEditorState.autoTrimBlackBars: bool`（default `false`）
  * `StitchEditorController.setAutoTrimBlackBars(bool)`
  * 新增 domain usecase `lib/features/long_stitch/domain/usecases/detect_letterbox.dart`：
    * 入参：`Uint8List bytes` 或 `img.Image`
    * 出参：`LetterboxInsets { topPx, bottomPx }`（仅检测上下）
    * 实现：`image` 包逐行扫描像素亮度，找到第一行/最后一行「非黑像素占比 > 1%」的位置
  * `_layoutMovieSubtitle` 接收可选的 `List<LetterboxInsets>` 入参，按图修正 `srcCrops` 上下
    边界
  * UI：toggle 仅在 `subtitleEffective` 时显示；首次开启 snackbar 提示
  * 单测：覆盖纯黑图、上下黑边、无黑边、单像素噪声等场景

## Acceptance Criteria

* [ ] compact 屏（< 600 dp）下打开编辑器，导入 ≥ 6 张图触发各种 sliders 全显，工具栏 Sheet
      高度不超过屏幕高 40%（或 360 dp），其内容仍可完整滚动浏览，画布肉眼比当前明显更宽敞。
* [ ] 极小屏（屏幕高 < 500 dp，如折叠屏外屏）下 Sheet 不被压扁到 < 200 dp。
* [ ] expanded 屏（≥ 840 dp）行为不退化：右侧面板继续可滚动，控件位置不漂移。
* [ ] 开启「仅保留字幕」后「图片间距」slider 立即从面板上消失（隐藏，非禁用），关闭后回来。
* [ ] 字幕高度控件以百分比显示（如 `12%`），调整时预览实时跟随；默认 12% 渲染表现近似历史
      120 px 在 1000 px 高图上的结果。
* [ ] 开启「自动剪裁黑边」toggle 后，渲染结果中字幕条上下不再夹无效黑边；关闭后回到原样。
* [ ] `flutter analyze` / `flutter test` 全绿；新增单测：
  * 百分比 ↔ px 换算（首图为 1000 px / 800 px 时 12% 的结果）
  * `detect_letterbox` 覆盖纯黑、纯白、上下黑边、单像素噪声场景
  * `_layoutMovieSubtitle` 接收 letterboxInsets 时的 srcCrop 修正

## Definition of Done

* 涉及 layout 算法的改动有单测（`test/features/long_stitch/...`）
* lint / typecheck / `flutter test` 全绿
* PRD + implement.jsonl + check.jsonl 齐备
* 触及 spec 文件（responsive-layout、component-guidelines、state-management）的约定均无回归

## Technical Approach

### 文件变更清单

#### 修改
* `lib/features/long_stitch/domain/entities/stitch_editor_state.dart`
  * 删除 `subtitleBandHeight`、`kMin/Max/DefaultSubtitleBandHeight`
  * 新增 `subtitleBandHeightPercent`、`autoTrimBlackBars`
  * 新增 `kMin/Max/DefaultSubtitleBandHeightPercent`
  * `copyWith` / `initial()` 同步
* `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
  * 重命名 `setSubtitleBandHeight` → `setSubtitleBandHeightPercent`
  * 新增 `setAutoTrimBlackBars`
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart`
  * **不再加** `SingleChildScrollView`（由 sheet 那侧加）
  * 字幕高度 slider 切百分比（label/value/range）
  * 隐藏「图片间距」slider when `subtitleEffective`
  * 新增「自动剪裁黑边」toggle when `subtitleEffective`
* `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart`
  * 用 `ConstrainedBox(maxHeight: min(screenHeight * 0.4, 360)) + SingleChildScrollView`
    包裹内嵌的 panel，最低保底 200 dp
* `lib/features/long_stitch/domain/usecases/stitch_layout.dart`
  * `_layoutMovieSubtitle` 接收可选 `List<LetterboxInsets>?`
* `lib/features/long_stitch/domain/usecases/stitch_render_request.dart`
  * `fromState` 内做 percent → px 换算
  * （可选）新增字段保存 letterbox insets，否则 layout 入参时即时传
* `lib/features/long_stitch/data/renderers/stitch_image_renderer.dart`
  * 在 decode 完成后、compose 前，若 `autoTrimBlackBars=true` 计算 insets 传给 layout

#### 新增
* `lib/features/long_stitch/domain/usecases/detect_letterbox.dart`（含 `LetterboxInsets`）
* `test/features/long_stitch/domain/usecases/detect_letterbox_test.dart`
* `test/features/long_stitch/domain/usecases/stitch_layout_letterbox_test.dart`（layout 接收
  letterbox insets 时的行为）
* `test/features/long_stitch/presentation/widgets/stitch_controls_panel_test.dart`（验证字幕
  模式下隐藏 spacing、显示百分比、显示 trim toggle）

### 实现顺序（PR-able stages）

* **Stage 1（A：工具栏限高+滚动）** — `StitchControlsSheet` 加 `ConstrainedBox` +
  `SingleChildScrollView`，最大高度 = `min(screenHeight * 0.4, 360 dp)`，最低保底 200 dp。
  独立可合。
* **Stage 2（B1：隐藏图片间距 + B2：字幕高度百分比）** — state 字段重命名、controller 改
  名、panel UI 切百分比并联动隐藏 spacing。一并合更顺，因为它们都触及 panel 同一段逻辑。
* **Stage 3（B3：自动剪裁黑边）** — 算法 + state + UI + 渲染器集成。这是最重的一块，单独
  合便于回滚。

## Out of Scope

* 工具栏布局的大改版（如改成 tabs / 抽屉 / 折叠区块）
* 横排（horizontal）模式下的字幕逻辑变更
* 多张首图（首图选择器）等更上游的产品改动
* 控件密度压缩（保留现有 padding/SizedBox/字号；只通过限高 + 滚动来"降低 Sheet 高度"）

## Technical Notes

* `_layoutMovieSubtitle` 算法签名保持向后兼容：`List<LetterboxInsets>?` 为可选参数，未传时
  行为完全等同当前。
* state 字段重命名属于 breaking change，但本 repo 未对编辑器状态做持久化（每次进入编辑器
  都从 `StitchEditorState.initial()` + 当前 import session 起手），所以不需要写迁移逻辑。
* 黑边检测在 isolate 中跑——已有 `StitchImageRenderer._shouldUseIsolate` 路径，且
  `_renderInIsolate` 已经 decode 一遍源图，可顺手做 letterbox 扫描。考虑把 detection 结果
  随 layout 一起算，避免重复 decode。

## Subtasks

> 经评估**不拆 subtasks**：三个改动逻辑相关、工作量 Small-Medium、可在同任务下通过 Stage 1
> / 2 / 3 三个 PR 分批合并。
