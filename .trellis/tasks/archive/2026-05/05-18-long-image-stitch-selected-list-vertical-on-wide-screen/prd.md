# 长图拼接已选列表改版 - 宽屏下纵向列表置于控制栏上方

## Goal

宽屏（expanded / large，≥ 840 dp）下，把长图拼接编辑器的「已选图片」列表从
顶部全宽横向条带改造成右侧侧栏的纵向列表，并垂直置于控制栏（`StitchControlsPanel`）
之上。目的是把宽屏纵向空间还给 canvas（左列），同时把「图片管理 + 参数控制」
聚拢到右侧同一列，匹配桌面 / 平板用户对单列工具栏的心智预期。

## What I already know

* 入口屏：`lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
  * `_StitchEditorBody.build()` 用 `windowSizeClassOf(context)` 切换布局
  * **compact / medium**：`Column(StitchImageStrip, Expanded(StitchPreviewCanvas), StitchControlsSheet)`
  * **expanded / large**（现状）：`Column(StitchImageStrip, Expanded(Row(Expanded(canvas), SizedBox(panelWidth, SingleChildScrollView(StitchControlsPanel)))))`
  * 侧栏宽度 `clamp(380, container * 0.25, 480) dp`
* 已选列表：`lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart`
  * `ReorderableRow`（`package:reorderables`）+ `needsLongPressDraggable: true`
  * `_ImageCard` 宽 110 dp、高 140 dp：方形 thumbnail + 尺寸文本 + 右上角 × 按钮
  * Header：`已选图片 (x/N)` + 清空 + 折叠/展开
  * 空状态 `_EmptyHint`：高 140 dp 卡片，两个 CTA（从相册 / 剪贴板）
  * **唯一**的图片导入入口（AppBar 没有「导入图片」按钮，不像 `grid_editor_screen.dart`）
* 控制栏：`lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart`
  * mode segmented、字幕开关、若干 slider、边框色板
  * 宽屏 caller 已经把它包在 `SingleChildScrollView` 里
* 图片导入：编辑器 body 已被 `ImageDropZone` 包裹（拖拽导入仍可用）；
  `StitchEditorController` 暴露 `addFromGallery / pasteFromClipboard / clear / reorder / removeImage`
* Spec：
  * `.trellis/spec/frontend/responsive-layout.md` 记录了 stitch 编辑器的现有宽屏布局
    （表格 + 「Sheet → Panel dual-form extraction」示例）；改版后需要同步更新
  * 「side panel 内容必须自带 SingleChildScrollView，否则会 RenderBox overflow」

## Requirements (locked)

* **R1**：宽屏（`WindowSizeClass.expanded` || `WindowSizeClass.large`）下，
  `StitchImageStrip` 从顶部全宽位置移除；右侧侧栏内自上而下渲染：
  纵向已选列表 → `StitchControlsPanel`。
* **R2**：列表方向由横向改为纵向；reorder 改用 `ReorderableColumn`
  （`package:reorderables` 的 API 对称替换），保留 `needsLongPressDraggable: true`。
* **R3**：单卡形态改为**横向 row**——左缩略图（约 56×56 dp）+ 中间尺寸文本
  `${width}×${height}` + 右侧 × 删除按钮 + 末尾 `Icon(Icons.drag_indicator)` 作为
  「这里可拖」的视觉手柄提示（长按整张卡片均可拖，drag_indicator 仅为视觉提示，
  不引入独立的 short-press 手势）。行高约 72 dp。
* **R4**：列表与控制栏在右列内对半分——
  `Column(Expanded(flex:1, 列表区), Expanded(flex:1, StitchControlsPanel))`，
  各自内部 `SingleChildScrollView` 独立滚动。
* **R5**：列表 Header 保留「图标 + `已选图片 (x/N)` + 添加 + 清空」；
  **去掉**折叠/展开按钮（半屏限高 + 内部滚动后，折叠语义失效）。
  「添加」按钮始终显示（与现有 `StitchImageStrip` 一致），是非空状态下的
  追加导入入口，触发 `addFromGallery()`；「清空」仅 `hasImages` 时显示。
* **R6**：列表为空时，列表区内显示完整 `_EmptyHint`（保留两个 CTA）；
  AppBar 不变（不引入额外的「导入图片」按钮）。
* **R7**：窄屏（compact / medium）布局完全不变。
* **R8**：保留 reorder / 单项删除 / 清空（行为与现有横向条带一致）。
* **R9**：抽取「清空确认对话框」逻辑为 module-private helper
  （如 `Future<bool> _confirmStitchClear(BuildContext, int count)`），
  供 `StitchImageStrip`（窄屏）与新 `StitchVerticalImageList`（宽屏）共用，
  避免对话框文案 / 行为两端漂移。
* **R10**：`.trellis/spec/frontend/responsive-layout.md` 同步更新——
  「响应式行为表」中 stitch_editor 行的 expanded / large 单元格，
  以及若现有「Sheet → Panel dual-form extraction」代码示例引用了顶部 strip，
  也需对应调整。

## Acceptance Criteria

* [ ] **AC-1**：宽屏（≥ 840 dp）下，编辑器顶部不再渲染 `StitchImageStrip`；
      右侧侧栏内自上而下渲染：纵向已选列表 + `StitchControlsPanel`，
      两者各占 50% 高度，各自内部可滚动。
* [ ] **AC-2**：纵向列表中每行采用横向 row 形态（缩略图 + 尺寸 + × + 拖拽提示），
      行高约 72 dp，支持长按拖拽 reorder。
* [ ] **AC-3**：列表 Header 包含图标 + 计数文本 + 添加按钮 + 清空按钮；无折叠/展开按钮。
* [ ] **AC-4**：列表为空时显示 `_EmptyHint`（两个 CTA 可点）；
      非空时显示 reorderable 行列表。
* [ ] **AC-5**：窄屏（< 840 dp）下，编辑器布局完全不变
      （顶部 `StitchImageStrip` 横向条带 + 底部 `StitchControlsSheet`）。
* [ ] **AC-6**：reorder、单项删除、清空行为与窄屏一致（调用同一组 controller 方法）。
* [ ] **AC-7**：列表区与控制栏的滚动相互独立；不出现 RenderBox overflow / 页面整体滚动。
* [ ] **AC-8**：抽取共享的「清空确认」helper，`StitchImageStrip` 也切换到该
      helper 使用；两端清空行为一致（同一份对话框文案、同一份调用路径）。
* [ ] **AC-9**：`.trellis/spec/frontend/responsive-layout.md` 的响应式行为表
      与 stitch_editor 入口屏 class-level 文档同步更新。
* [ ] **AC-10**：新增 widget 测试覆盖：宽屏顶部不渲染 strip、侧栏内同时存在
      列表 + 控制栏、reorder 正确、空状态显示 _EmptyHint、Header 不再含折叠按钮。
* [ ] **AC-11**：`dart format .` / `flutter analyze` / `flutter test` 全绿。

## Definition of Done

* Tests added/updated（widget 测试，覆盖宽屏布局 + 纵向 reorder + 空状态 + Header）
* Lint / typecheck / tests green
* `responsive-layout.md` 响应式表格与入口屏 class-level 文档同步
* 没有 hard-coded magic width 数字（沿用 `WindowSizeClass` dispatch）

## Out of Scope

* 窄屏（compact / medium）布局改造
* AppBar 增加「导入图片」按钮（保留宽屏 `_EmptyHint` 作唯一入口的现状）
* 多选 / 批量删除
* 列表项加 letterbox / 字幕预览缩略图等额外信息
* `reorderables` → Flutter 内置 `ReorderableListView` 的全面切换（仅替换 Row→Column）

## Technical Approach

### 入口屏拆分

`stitch_editor_screen.dart` 的 `_StitchEditorBody.build()` 现有结构：

```dart
if (useSidePanel) {
  return Column(
    children: [
      const StitchImageStrip(),               // ← 改：移除顶部 strip
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = (constraints.maxWidth * 0.25).clamp(380.0, 480.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: StitchPreviewCanvas()),
                SizedBox(
                  width: panelWidth,
                  child: const SingleChildScrollView(  // ← 改：换为 Column(Expanded+Expanded)
                    child: StitchControlsPanel(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
```

目标结构：

```dart
if (useSidePanel) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final panelWidth = (constraints.maxWidth * 0.25).clamp(380.0, 480.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: StitchPreviewCanvas()),
          SizedBox(
            width: panelWidth,
            child: Column(
              children: [
                Expanded(child: StitchVerticalImageList()),     // 新组件
                Expanded(child: SingleChildScrollView(child: StitchControlsPanel())),
              ],
            ),
          ),
        ],
      );
    },
  );
}
```

窄屏分支完全不动。

### 新组件 `StitchVerticalImageList`

新增 `lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart`：

* `ConsumerStatefulWidget` —— 持有 reorder / image state 订阅
* 结构（自上而下）：
  * Header `Row`：`Icon(photo_library_outlined)` + `Text('已选图片 (x/N)')` +
    `Spacer()` + `TextButton.icon('清空')`（hasImages 才显示）
  * Content：
    * `state.images.isEmpty` → `_EmptyHint`（复用现 widget 或抽取到共享文件）
    * 非空 → `Expanded(SingleChildScrollView(ReorderableColumn(...)))`，
      每项为新 `_StitchVerticalImageRow`（横向 row + 拖拽手柄图标）
* 行卡片设计（`_StitchVerticalImageRow`）：
  * `Row(crossAxisAlignment: center, children: [
      thumbnail 56×56, sizeText Expanded, × IconButton, Icon(drag_indicator),
    ])`
  * 卡片 padding 6 dp、圆角 12 dp、`outlineVariant` border、`surface` 背景
  * 行高约 72 dp（具体由 padding + 56dp thumbnail 自然计算）

### Header 子组件抽取（重构机会）

「清空确认」helper 抽取（**已纳入 MVP**，见 R9 / AC-8）：
* 当前 `StitchImageStrip._confirmClear` 是 `StitchImageStrip` 的实例方法，
  返回 `Future<void>`；改造时抽取为模块顶层私有函数（如
  `Future<bool> _confirmStitchClear(BuildContext context, int count)`，
  返回 `true` 表示用户确认清空，外层根据返回值再调用 `controller.clear()`），
  放置在 `stitch_image_strip.dart`（或新建 `stitch_clear_confirm.dart`）。
  `StitchImageStrip` 与 `StitchVerticalImageList` 都通过该函数触发清空。

Header 行不强行共享 —— 两端按钮集合不同（窄屏含折叠按钮，宽屏没有），
各自直接写 Row 反而更清晰。

### `responsive-layout.md` 更新

* 表格里 stitch_editor 行的 expanded / large 单元格从
  「image strip 在顶部；canvas + 右侧 380-480 dp 控制面板」
  改为
  「右侧 380-480 dp 侧栏内对半分：纵向已选列表 + 控制面板」
* 「Sheet → Panel dual-form extraction」示例若引用了顶部 strip 配置，
  同步删除（实际看下来该 spec 示例只演示了 controls 部分，不一定需要改）

### 测试策略

* 复用 `tester.view.physicalSize` viewport override 模式（`responsive-layout.md`
  推荐的写法）
* 新增测试文件：`test/features/long_stitch/presentation/widgets/stitch_vertical_image_list_test.dart`
* 主要用例：
  1. 宽屏（1280×800）下 `StitchVerticalImageList` 存在、`StitchImageStrip` 不存在
  2. 窄屏（420×900）下 `StitchImageStrip` 存在、`StitchVerticalImageList` 不存在
  3. 列表为空时 `_EmptyHint` 渲染、两个 CTA 可点
  4. 列表非空时显示 `_StitchVerticalImageRow` × N
  5. 长按拖拽触发 `reorder(oldIndex, newIndex)` controller 调用
  6. 单项 × 按钮调用 `removeImage(i)`
  7. 清空按钮触发确认对话框 → 调用 `clear()`
  8. Header 不渲染折叠按钮

## Decision (ADR-lite)

**Context**：宽屏下顶部全宽图条占据纵向空间，左下 canvas 被压扁；同时
「图片管理」与「参数控制」分散在屏幕上下两端，与桌面用户对侧边工具栏的
心智不符。

**Decision**：宽屏（≥ 840 dp）下把已选列表迁入右侧侧栏，垂直置于控制栏之上，
两者各占侧栏一半高度并独立滚动。卡片形态从方形 thumbnail 改为横向紧凑 row，
取消折叠按钮（在限高 + 内部滚动的环境下失去意义），保留所有现有行为
（reorder / × 删除 / 清空 / 空状态 CTA）。窄屏布局不动。

**Consequences**：
* 正面：canvas 在宽屏拿到更多纵向空间；右侧侧栏工具感更强；与窄屏共用
  controller 不引入新状态；改造范围限于 1 个屏 + 1 个新 widget。
* 负面：响应式分支的视觉差异加大（窄屏方形卡 ↔ 宽屏横向 row），用户在
  调整窗口大小时会看到形态切换；新组件与现有 `StitchImageStrip` 有少量
  代码重复（清空确认对话框）。
* 后续可改进：未来若引入「批量选中」「letterbox 预览」等高级功能，纵向
  列表是天然容器，比横向条带扩展性更好。

## Technical Notes

* 文件清单（预计）：
  * 新增：`lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart`
  * 修改：`lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
    （`_StitchEditorBody`、class-level doc-comment、`_kStitchControlsPanelMinWidth`
    周边引用）
  * 修改（可选）：`lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart`
    —— 抽取共享的「清空确认」helper，避免对话框文案漂移
  * 新增测试：`test/features/long_stitch/presentation/widgets/stitch_vertical_image_list_test.dart`
  * 修改测试（可能）：`test/features/long_stitch/presentation/screens/stitch_editor_screen_test.dart`
    —— 新增宽屏分支断言
  * 更新文档：`.trellis/spec/frontend/responsive-layout.md`
* 相关约定：side panel `SingleChildScrollView` 强制（spec 已说明）、
  `WindowSizeClass` enum dispatch（spec 已说明）

## Implementation Plan

单一 PR 可完成（任务比较紧凑、改动范围聚焦在 1 个 feature 模块）。
按以下顺序提交（commit-by-commit）：

1. **新组件骨架**：新增 `stitch_vertical_image_list.dart`，
   实现 Header + 空态 + 非空 ReorderableColumn 行列表；
   暂不接入屏幕。
2. **入口屏切换**：`stitch_editor_screen.dart` 中宽屏分支改为新结构
   （Row(canvas, Column(Expanded列表, Expanded控制面板))），
   class-level doc-comment 同步。
3. **共享 helper（可选）**：抽取 `_confirmStitchClear` helper 给两端共用。
4. **Spec / 测试 / 文档**：更新 `responsive-layout.md` 响应式表格；
   新增 / 调整 widget 测试；跑 `dart format` / `flutter analyze` / `flutter test`。
