# 改进长图拼接模式 UX

## Goal

收紧长图拼接编辑器的交互细节：让"已选图片"板块更易整理（一键清空 + 折叠），底部导航
图标与功能语义更贴合，预览画布在可用空间中铺满容器，整体体验向"专业、克制"的设计基调
靠拢。

## Background

长图拼接是 Fl PiCraft 的核心场景之一（`/stitch` 一级 Tab）。当前编辑器虽然功能齐全
（拼接模式切换、间距/边框/圆角调节、字幕模式），但若干 UX 细节让本小姐看了想皱眉：

* 已选图片 ≥1 张后想全部清空，必须**逐张点叉**，没有快捷出口。
* 已选图片板块占用 ~140 dp 固定高度，预览空间被挤压，且无法折叠节省纵向像素。
* 底部导航条里 `长图拼接 = Icons.photo_library`（相册图标）→ 这是"相册集合"语义，
  和"把多张图片拼成一张长图"不太对位。
* 预览画布容器（surface 灰底）当前由内层画布尺寸决定高度——短图比例时容器没撑满
  `Expanded`，下方露出 Scaffold body 的默认色；视觉断层明显。

## Decisions (locked, ADR-lite)

| # | 决策 | 选项 | 备注 |
| --- | --- | --- | --- |
| D1 | 底部导航图标改造范围 | **仅替换长图拼接**：`photo_library_outlined/photo_library` → `view_agenda_outlined/view_agenda` | 最小改动，语义最贴近"竖向条带堆叠" |
| D2 | 清空交互形式 | **二次确认弹窗**：`AlertDialog` → 确认后调用 `clear()` | 不引入 SnackBar 状态，避免缓存"已清空"图片字节 |
| D3 | 折叠/展开默认状态 | **默认展开** | 仅 `imageCount > 0` 时显示折叠按钮；空状态保持原 hint 卡片 |
| D4 | 画布铺满策略 | **保留滚动 + 宽贴满 + 容器撑满 Expanded** | 短图时灰底 surface 充满整个 Expanded（画布在 surface 内居中）；长图时通过 SingleChildScrollView 滚动查看 |

## Requirements (final)

### R1. 已选图片头部「清空」按钮（D2）

* 位置：`StitchImageStrip` 头部行，与「添加」按钮同行；`imageCount > 0` 时可见。
* 视觉：`TextButton.icon` 或 `IconButton`，本小姐倾向 `TextButton.icon(Icons.delete_sweep_outlined, '清空')`。
* 行为：点击 → `AlertDialog`（标题"清空已选图片"、内容"将移除当前 N 张图片，此操作不可撤销"、
  确认按钮"清空"为 destructive 风格）→ 确认后 `ref.read(stitchEditorControllerProvider.notifier).clear()`。
* 取消对话框不做任何状态变更。

### R2. 已选图片板块折叠/展开（D3）

* 位置：`StitchImageStrip` 头部行右侧，紧邻「清空」按钮。
* 触发：仅 `imageCount > 0` 时可见；空状态不显示。
* 视觉：`IconButton(Icons.expand_less / Icons.expand_more)`，附 `Tooltip`（收起/展开）。
* 行为：折叠 → 隐藏 `ReorderableRow` 卡片行（仅保留头部 + 计数）；展开 → 恢复原 140 dp 卡片行。
* 状态归属：`StatefulWidget` 内的 `bool _expanded`（**不污染**领域 state）。
* 默认值：`true`（展开）。

### R3. 底部导航图标替换（D1）

* `lib/core/widgets/bottom_nav_bar.dart` 第 49–54 行：
  * `icon: Icons.photo_library_outlined` → `Icons.view_agenda_outlined`
  * `selectedIcon: Icons.photo_library` → `Icons.view_agenda`
* 其余 3 个 destinations 一字不动。

### R4. 画布铺满容器（D4）

* `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`：
  * compact / medium 分支：`Expanded(child: SingleChildScrollView(child: StitchPreviewCanvas()))`
    保留；但 `StitchPreviewCanvas` 自身要在 Expanded 给的高度内**撑满**灰底 surface。
  * expanded / large 分支同理。
* `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart`：
  * 把外层 `Container(decoration: ...)` 用 `LayoutBuilder` + `ConstrainedBox(minHeight)`
    包裹，让灰底 surface 至少撑满 viewport 高度。
  * 内层 `Center(child: _PreviewSurface)` 不变；`_PreviewSurface` 的 `LayoutBuilder`
    现有 fallback `maxWidth / aspect` 行为继续生效。
  * 结果：
    * 短图比例 → 灰底铺满 Expanded，画布在容器内居中，上下有灰底；不出现滚动条。
    * 长图比例 → 灰底铺满 Expanded（同时画布高度也超过 viewport），通过 ScrollView 滚动查看。

## Acceptance Criteria

* [ ] AC1 – `imageCount > 0` 时，「已选图片」头部出现「清空」`TextButton.icon`；点击后
      弹出 `AlertDialog`；确认后图片列表清零；取消则保持原列表（widget test 覆盖）。
* [ ] AC2 – `imageCount > 0` 时，「已选图片」头部出现折叠按钮；切换时卡片行
      `ReorderableRow` 在 widget 树中相应隐藏/出现；图标在 `expand_less` / `expand_more`
      间切换（widget test 覆盖）。
* [ ] AC3 – `imageCount == 0` 时，清空按钮和折叠按钮均不可见；只显示「添加」按钮和
      空状态 hint（widget test 覆盖）。
* [ ] AC4 – `AppBottomNavBar.destinations[1]` 的 `icon` 为 `Icons.view_agenda_outlined`、
      `selectedIcon` 为 `Icons.view_agenda`；其余三项 `IconData` 保持不变（widget test 覆盖）。
* [ ] AC5 – compact / medium 布局下，`StitchPreviewCanvas` 父容器灰底 surface 高度等于
      Expanded 提供的高度（即与 controls sheet 顶部对齐，无下方异色断层）；画布在容器内
      居中（widget test：检查 surface 高度 ≈ viewport 高度）。
* [ ] AC6 – expanded / large 布局下，画布所在左列灰底 surface 同样撑满；右侧 controls
      panel 不受影响（widget test）。
* [ ] AC7 – 长图比例下仍可通过滚动查看完整画布（不退化为 fit contain 强制压扁）。

## Definition of Done

* `dart format .` / `flutter analyze` / `flutter test` 全部通过。
* 新增/调整组件附带 widget test，至少覆盖：
  * `stitch_image_strip_test.dart`：清空确认流程（确认/取消）、折叠切换、空状态隐藏。
  * `bottom_nav_bar_test.dart`：图标 IconData 断言（已有 test 文件则扩展）。
  * `stitch_preview_canvas_test.dart`：surface 撑满 viewport 的回归。
* 必要时更新 `.trellis/spec/frontend/` 中 long_stitch 模块的 UX 笔记（如有现有 spec）。
* journal 记录改动要点 + screenshot（可选）。

## Out of Scope

* 重做整套长图拼接 UI / 重排控件面板。
* 折叠状态的跨会话持久化（仅会话内的本地 UI 状态）。
* 改动宫格切图、导出、设置等其他 feature。
* 国际化 / 多语言文案。
* 新增非 `material` 内置 icon 包依赖。
* 双击大图预览 / 缩放手势（D4 选项 C 已排除）。
* 清空操作的 undo / redo / 历史栈。

## Technical Notes

* Clean Architecture + Riverpod；`StitchEditorController.clear()` 已经接好 import
  controller（line 150–156），UI 只需调用并 confirm。
* 折叠态是纯本地 UI 状态：用 `StatefulWidget` 的 `bool _expanded`，避免污染
  `StitchEditorState`。
* 画布父容器撑满 Expanded 的实现模式：
  ```dart
  LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Container(
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
            padding: const EdgeInsets.all(16),
            child: Center(child: _PreviewSurface(state: state)),
          ),
        ),
      );
    },
  );
  ```
  注意要把 `Container` 的高度撑到 viewport，所以把外层的 `Expanded(child: SingleChildScrollView(...))`
  改为 `Expanded(child: StitchPreviewCanvas())`，由 canvas 自己用 LayoutBuilder 处理。

## Implementation Plan (single PR, 3 steps)

* Step 1 – 已选图片板块改造（R1 + R2）：编辑 `stitch_image_strip.dart`，新增清空按钮 +
  折叠按钮 + AlertDialog；写/扩 widget test。
* Step 2 – 底部导航图标（R3）：编辑 `bottom_nav_bar.dart`，替换 `destinations[1]` 的
  icon / selectedIcon；写/扩 widget test。
* Step 3 – 画布铺满（R4）：移动 `SingleChildScrollView` 到 `stitch_preview_canvas.dart`
  内部、加 `LayoutBuilder` + `ConstrainedBox(minHeight)`；同步修改
  `stitch_editor_screen.dart` 移除外层 ScrollView；写回归 widget test。

每个 step 完成后跑 `flutter analyze` + 相关 widget test；全部 step 结束后跑全量
`flutter test` + `dart format .`。
