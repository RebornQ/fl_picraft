# 长图拼接移动端画布空间重设计

## Goal

在 compact 屏宽（手机竖屏，<600 dp）下重新设计长图拼接编辑器界面，
让**预览画布成为视觉与交互的主角**，把目前挤占大量垂直空间的「已选图片列表」和「参数控制面板」
改为按需调起的工具层；同时**完整保留原有功能**（图片增删 / 重排 / 模式切换 / 字幕模式 /
间距 / 边框 / 圆角 / 颜色 / 导出）。

medium / expanded / large 屏宽的布局**不变更**。

---

## What I already know

### 当前实现量化分析（假设 800 dp 高的手机竖屏）

| 区块 | 占用高度 | 占比 |
|---|---|---|
| AppBar | ~56 dp | 7% |
| Status bar + SafeArea top | ~24 dp | 3% |
| `StitchImageStrip`（已选图片，展开时） | ~208 dp（header 60 + cards 148） | 26% |
| **预览画布**（`StitchPreviewCanvas`） | **~232 dp** | **~29%** |
| `StitchControlsSheet`（参数面板） | ~200 dp（受 floor 兜底） | 25% |
| Bottom Nav（`AppShell` 拥有） | ~80 dp | 10% |

**结论：画布只占屏幕 ~29%，确实「挤压得所剩无几」**。即便用户主动点 strip 上的「收起」
按钮，header 仍要占 ~60 dp；sheet 已经做了 max(200, min(0.22 * screen, 320)) 三层封顶
但 floor 200 dp 仍是硬地板。

### 关键文件 / 实体

* `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` — 入口屏，
  内含 `_StitchEditorBody` 的响应式分支（compact / medium → 单列 Column；expanded / large → Row）。
* `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart` — 顶部横向图片条（compact）。
* `lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart` — 侧栏纵向图片列表（expanded）。
* `lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart` — 底部参数 sheet（compact）。
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` — 参数面板核心组件
  （compact / expanded 共用，由不同壳容器包裹）。
* `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart` — 预览画布；
  内含 `_EmptyHint`（图标 + 「导入图片以预览拼接效果」文案）。
* `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` — Riverpod NotifierProvider，
  与 `imageImportControllerProvider(.stitch)` 同步图片列表；暴露 `addFromGallery` / `addFromCamera` /
  `pasteFromClipboard` / `clear` / `removeImage` / `reorder` 方法。

### 参数面板包含的控件

* 模式分段控制（竖向 / 横向）
* 「仅保留字幕」开关（vertical 模式 + 图片数 ≥2 时可用）
* 「字幕高度」滑块（subtitleEffective 时可见）
* 「自动剪裁黑边」开关（subtitleEffective 时可见）
* 「图片间距」滑块（非 subtitleEffective 时可见）
* 「边框宽度」滑块
* 「边框颜色」6 个色板
* 「圆角」滑块

### 已知约束

* **Riverpod state-management spec**：响应式布局必须走 `windowSizeClassOf(context)` / `WindowSizeClass` 枚举，
  不允许在 build 里硬比较 `MediaQuery.sizeOf(context).width < 600`。
* **Image strip 拖拽**：用 `reorderables` 包的 `ReorderableRow`（compact）/ `ReorderableColumn`（expanded），
  需要 long-press 触发；新方案需保持该拖拽语义。
* **导出 CTA**：compact / medium 在 AppBar action 用 `Icons.save_outlined` IconButton，
  expanded / large 用 `FloatingActionButton.extended`。新方案必须保留导出入口。
* **拖拽导入**：编辑器最外层包了 `ImageDropZone`（桌面 / Web 拖入图片直接进 stitch 会话）——新方案的层级
  调整不能打断这条路径。
* **router 拓扑**：`/stitch` 是 `StatefulShellBranch` 的 tab root（不是子页面），`AppBar` 不会显示 leading ←，
  也不需要 push 到任何子路由。新方案在该 tab branch 内部完成所有改造，**不**改 `router.dart`。

---

## Decision (ADR-lite)

**Context**: compact 屏宽下画布只占 ~29% 屏幕高度，挤压严重；需在「画布最大化」「保留全部功能」
「实现成本可控」之间权衡。

**Decision（7 项核心决策）**:

| ID | 决策点 | 选择 |
|---|---|---|
| D-1 | 核心交互形态 | **Approach B**：持久底栏 + 触发式 Sheet |
| D-2 | 底栏与 BottomNav 关系 | **方案 X**：双底栏堆叠（不动 router / AppShell） |
| D-3 | MVP 范围 | **仅 compact (<600 dp) 走新方案**；medium / expanded / large 保持现状 |
| D-4 | 底栏 chip 布局 + 导出入口 | **P3（修订）：3 chip（[+ 添加] / [🖼 N/20] / [⚙ 参数]）+ AppBar 保留导出 IconButton** |
| D-5 | 图片 sheet 形态 | **V**：纵向列表（复用 expanded 模式的 `StitchVerticalImageList`） |
| D-6 | 参数 sheet 锚点 | **S2**：showModalBottomSheet 包 DraggableScrollableSheet，三档 snap [0.3, 0.55, 0.9] |
| D-7 | + 添加 chip 行为 + 空状态 | **E2**：ActionSheet 三选一（相册 / 剪贴板 / 相机）；画布空状态仅保留现有 `_EmptyHint` |

**Consequences**:

* 画布可用高度 ~576 dp / ~72% 屏占（800 dp 设备上）—— 相比现状 ~232 dp / ~29% 提升 2.5×，达成 R-1 目标。
* 零跨模块改动：`router.dart` / `AppShell` / `app_shell.dart` 完全不动；编辑器底栏是 `StitchEditorScreen` 内部新组件。
* 旧 widget（`StitchImageStrip` / `StitchControlsSheet`）**保留**，medium 分支继续使用——本任务不删除任何旧代码。
* 单一文件改动核心：`stitch_editor_screen.dart` 增加 compact 专属分支，新增 4 个 widget 文件。
* D-4 决策于实施 commit 前由用户反转：导出回到 AppBar 经典位置，底栏简化为 3 chip。原因：用户对 AppBar action 位置已建立 muscle memory，移除会增加学习成本；同时 AppBar IconButton 在 disabled 状态下视觉提示更标准（greyed out）。

---

## Requirements (final)

**R-1 画布最大化（仅 compact）**：compact 屏宽（<600 dp）下，预览画布占据屏幕垂直空间 ≥ ~70%
（不含 AppBar / 编辑器底栏 / AppShell BottomNav）。

**R-2 保留全部功能**：
* 图片增：相册 / 剪贴板 / 相机 / 拖入（4 种入口）。
* 图片删：单个 × / 清空。
* 图片重排：long-press drag。
* 参数面板：mode / subtitleOnly / subtitleBandHeight / autoTrim / spacing / border width / border color / corner radius。
* 导出 CTA：一键直达 `/export`。

**R-3 响应式契约不破坏**：
* expanded / large 双列布局保持不变。
* **medium (600-840 dp) 保持现状**——继续走「strip + canvas + sheet 三段 Column」。
* 切换 size class 时状态（参数、图片列表、滚动位置）无丢失。

**R-4 不绕过 spec**：所有响应式分支走 `WindowSizeClass`；compact 专属逻辑走 `WindowSizeClass.compact` 单独分支。

**R-5 双底栏视觉处理（MVP 最低标准）**：编辑器底栏与 AppShell BottomNav 在视觉上至少**通过 elevation
或 colorScheme 任一维度**可区分；精细化 polish 不在 MVP 内。

**R-6 编辑器底栏（compact）**：
* 固定底部，高度 ~64 dp。
* 3 个 segment（从左到右）：`[+ 添加]` `[🖼 N/20]` `[⚙ 参数]`。
* `[+ 添加]`：`FilledButton.tonalIcon`。
* `[🖼 N/20]`：`FilledButton.tonalIcon`；imageCount=0 时禁用。
* `[⚙ 参数]`：`FilledButton.tonalIcon`。
* 区分手段：底栏用 `colorScheme.surface` + elevation 0~3 + 顶部 outlineVariant 分割线，
  与 `AppShell` 的 `NavigationBar` 默认配色区分开。
* 导出 CTA **不**进入底栏 —— 保持在 AppBar action 槽位（见 R-10）。

**R-7 图片管理 Sheet（compact）**：
* 点击 `[🖼 N/20]` 触发 `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`。
* 内容复用 **`StitchVerticalImageList`** widget（不复制代码）。
* Sheet 顶部加 grip handle。
* 高度按内容自适应（不强制 DraggableScrollableSheet——纵向列表已是滚动友好）。
* long-press drag 重排行为保持不变。

**R-8 参数 Sheet（compact）**：
* 点击 `[⚙ 参数]` 触发 `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`。
* 内容用 `DraggableScrollableSheet` 包 **`StitchControlsPanel`**（复用）。
* `initialChildSize: 0.55`，`minChildSize: 0.3`，`maxChildSize: 0.9`，`snapSizes: [0.3, 0.55, 0.9]`，
  `snap: true`。
* 内部 `SingleChildScrollView` 让参数面板在 0.9 高度下也能完整滚动。
* Sheet 顶部加 grip handle。

**R-9 添加 ActionSheet（compact）**：
* 点击 `[+ 添加]` 触发 `showModalBottomSheet`，内容为 3 个 `ListTile`：
  * 「从相册」→ `stitchEditorControllerProvider.notifier.addFromGallery()`
  * 「剪贴板粘贴」→ `stitchEditorControllerProvider.notifier.pasteFromClipboard()`
  * 「拍照」→ `stitchEditorControllerProvider.notifier.addFromCamera()`
* Sheet 顶部加 grip handle。
* 点击任一选项后立即关闭 sheet（`Navigator.of(context).pop()`），然后调用对应 method。

**R-10 AppBar 行为（所有 size class 一致）**：**保留** AppBar 现有的「导出每张子图」`IconButton` 在 compact 屏宽下的渲染——与 medium 行为一致。compact 与 medium 共用同一个 AppBar action 槽位作为导出 CTA；expanded / large 则切换为 FAB。底栏（compact 专属）不承担导出 CTA。

**R-11 画布空状态（compact）**：`StitchPreviewCanvas` 的 `_EmptyHint` **保持原样**
（`Icons.image_outlined` + 「导入图片以预览拼接效果」），不增加 CTA 按钮；用户通过底栏 `[+ 添加]` 完成导入。

---

## Acceptance Criteria (final)

* [ ] **AC-1** 在 360×800 dp 的手机视口下（compact），画布可见高度 ≥ 480 dp（≥60% 屏占比）。
* [ ] **AC-2** 在不打开任何 sheet 的情况下，用户能看到底栏 `[🖼 N/20]` 上的图片数指示。
* [ ] **AC-3** 全流程（添加 1 张图 + 调一个参数 + 导出）的操作步数 ≤ 现状 + 2。
* [ ] **AC-4** 参数 sheet 打开在 `initialChildSize=0.55` 时，画布预览仍 ≥40% 可见；
  用户可拖至 0.3 让画布 ≥70% 可见。
* [ ] **AC-5** 现有 widget 测试（compact / medium / expanded / large 路由分支）全部通过；新增 widget 测试覆盖：
  * compact 屏宽下底栏 3 chip 渲染、可见性、disabled 状态。
  * `[🖼]` chip 点击触发图片 sheet；sheet 内 `StitchVerticalImageList` 渲染。
  * `[⚙]` chip 点击触发参数 sheet；sheet 内 `StitchControlsPanel` 渲染。
  * `[+ 添加]` chip 点击触发 ActionSheet，3 个 ListTile 渲染。
  * compact 屏宽下 AppBar 的「导出」IconButton 渲染并可点击（触发 `_onExportPressed`，验证 `currentExportSourceKindProvider` 被设为 `.stitch`）。
* [ ] **AC-6** `ImageDropZone` 拖入图片行为不变；图片 sheet 内 long-press drag 重排行为不变。
* [ ] **AC-7** medium 屏宽 (600-840 dp) 下行为完全保持现状（不渲染新底栏 / sheet）；
  对应的现有测试不需要修改。
* [ ] **AC-8** compact 屏宽下，AppBar 的「导出」IconButton **仍然渲染**（与 medium 行为一致）；其他 AppBar 元素（leading ← / title）不变。
* [ ] **AC-9** compact 屏宽下 imageCount=0 时，`[🖼 N/20]` 为 disabled 状态；AppBar 导出 IconButton 在 imageCount=0 时为 disabled（greyed out）；画布显示 `_EmptyHint`（图标 + 文案）；底栏 `[+ 添加]` 仍可点击触发 ActionSheet。

## Definition of Done (team quality bar)

* `flutter test` 全绿（含本任务新增的 widget 测试）。
* `flutter analyze` clean，`dart format .` 已跑。
* 不破坏 `.trellis/spec/frontend/responsive-layout.md` 中的现有约定（必要时更新 spec）。
* PR 描述包含 compact 屏宽的截图或 GIF（before / after 对比）。
* 不引入新依赖（所有需要的能力——`showModalBottomSheet` / `DraggableScrollableSheet`——都是 Flutter SDK 自带）。

---

## Technical Approach

### 新增文件

```
lib/features/long_stitch/presentation/widgets/
├─ stitch_editor_bottom_bar.dart   (R-6) — 编辑器底栏 4 chip 容器
├─ stitch_add_action_sheet.dart    (R-9) — + 添加 ActionSheet
├─ stitch_image_sheet.dart         (R-7) — 图片管理 sheet（包裹 StitchVerticalImageList）
└─ stitch_params_sheet.dart        (R-8) — 参数 sheet（DraggableScrollableSheet 包 StitchControlsPanel）
```

### 修改文件

* **`stitch_editor_screen.dart`**：
  * `build()` 中 `useSidePanel` 判断不变。
  * 新增 `isCompact = sizeClass == WindowSizeClass.compact` 分支。
  * compact 分支：`bottomNavigationBar: StitchEditorBottomBar(...)`（用 Scaffold 的 bottomNavigationBar slot 容纳，
    系统自动叠在 `AppShell` 的 BottomNav 上方）。
  * compact 分支 body：`Column { Expanded(canvas) }`（不再有 strip / sheet）。
  * compact 分支 AppBar action：跳过「导出」IconButton（仅 medium 渲染）。
  * 现有 `floatingActionButton`（expanded / large 用）保持不变。
  * medium 分支：完全沿用现有 `_StitchEditorBody` 的 `Column { strip, canvas, sheet }` 路径。
* **`stitch_vertical_image_list.dart`**：可能需要小幅调整以适配 modal sheet 高度（如减少最大高度约束），
  但应优先保持现有 widget 接口不变；如需差异化，新增可选 `compactSheetMode: bool` 参数。
* **`stitch_controls_panel.dart`**：保持不变；它已经被 sheet 复用（仅外层包装变化）。

### 关键风险与缓解

| 风险 | 缓解策略 |
|---|---|
| Scaffold.bottomNavigationBar 与 AppShell.bottomNavigationBar 叠加导致布局错乱 | StitchEditorScreen 已经在自己的 Scaffold 中 —— `AppShell` 是外层 Scaffold，本编辑器是内层 Scaffold。两者的 bottomNavigationBar 互不影响（Flutter 渲染时各自占自己的 SafeArea），但仍需在 dev/test 验证视觉无叠加。 |
| `showModalBottomSheet` 内的 long-press drag 与 sheet drag 手势冲突 | `reorderables` 的 ReorderableColumn 在 long-press 后接管 PanGesture；与 modal sheet 的 drag-down-to-dismiss 在时间上分离（long press > 500ms vs drag immediate）。预期无冲突，但需写一个 widget test 验证。 |
| `DraggableScrollableSheet` 的 `expand: false` + `SingleChildScrollView` 在 maxChildSize 时的 overflow | 测试三档高度下参数面板内容都能完整滚动到底部（含 SizedBox(height: 80) 呼吸感）。 |
| compact 屏宽下 AppBar 移除导出按钮，但 ref.read 仍调用 `_onExportPressed` —— 现有逻辑应保留 | 不动 `_onExportPressed`；只是底栏的 `[导出]` chip 调用它。 |
| medium 屏宽下旧路径不能因新代码而 break | medium 分支完全沿用现有代码路径，仅 compact 分支走新逻辑。size-class enum 切换严格隔离。 |

### 组件设计草图

**`StitchEditorBottomBar`** (Stateless ConsumerWidget)：
```dart
// Material(elevation: 3, color: surface, top-border: outlineVariant)
// Container(height: 64, padding) → Row(spaceBetween) {
//   TonalButton([+ 添加]) → showStitchAddActionSheet
//   TonalButton([🖼 N/20]) → showStitchImageSheet, disabled if !hasImages
//   TonalButton([⚙ 参数]) → showStitchParamsSheet
//   FilledButton([📥 导出]) → _onExportPressed, disabled if !hasImages
// }
```

**`showStitchParamsSheet`**：
```dart
showModalBottomSheet(
  isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
  builder: (_) => DraggableScrollableSheet(
    initialChildSize: 0.55, minChildSize: 0.3, maxChildSize: 0.9,
    snap: true, snapSizes: [0.3, 0.55, 0.9], expand: false,
    builder: (ctx, scrollController) => Material(
      borderRadius: top-rounded 16,
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(children: [_GripHandle(), StitchControlsPanel(), SizedBox(80)]),
      ),
    ),
  ),
);
```

**`showStitchImageSheet`**：
```dart
showModalBottomSheet(
  isScrollControlled: true, useSafeArea: true,
  builder: (_) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: screenH * 0.7),
    child: Column(mainAxisSize: min, children: [_GripHandle(), Expanded(StitchVerticalImageList())]),
  ),
);
```

**`showStitchAddActionSheet`**：
```dart
showModalBottomSheet(
  builder: (_) => SafeArea(child: Column(mainAxisSize: min, children: [
    _GripHandle(),
    ListTile(icon: photo_outlined, '从相册', onTap: addFromGallery),
    ListTile(icon: paste, '剪贴板粘贴', onTap: pasteFromClipboard),
    ListTile(icon: camera_alt_outlined, '拍照', onTap: addFromCamera),
  ])),
);
```

---

## Implementation Plan (small PRs)

* **PR-1**: 新增 `StitchEditorBottomBar` + 3 个 sheet helpers (`stitch_image_sheet.dart` / `stitch_params_sheet.dart` /
  `stitch_add_action_sheet.dart`)，以及共用的 `_GripHandle` 小组件。**不**修改 `stitch_editor_screen.dart`。
  补完整 widget tests。
* **PR-2**: 修改 `stitch_editor_screen.dart` 的 compact 分支：
  * AppBar action 中 compact 时不渲染「导出」IconButton（R-10）。
  * 新增 `bottomNavigationBar: StitchEditorBottomBar(...)`（仅 compact）。
  * body 改为 `Column { Expanded(StitchPreviewCanvas) }`（仅 compact）。
  * medium / expanded / large 路径保持不变。
  * 补 size-class × 渲染契约的 widget test。
* **PR-3**（如有时间余力）：双底栏视觉精细化（R-5 polish）—— elevation / outlineVariant / shadow 调整。

任务整体规模为 **Moderate**，**不**拆分为多个 Trellis sub-tasks（所有改动集中在 long_stitch feature，
无跨 feature 影响）。PR 拆分体现在 git 提交粒度上，而非 Trellis subtask。

---

## Out of Scope (explicit)

* **medium / expanded / large 屏宽的布局改造**——本任务只动 compact。
* 宫格切图（`grid` feature）的画布布局改造。
* 画布内的手势缩放 / pan / 双击 fit。
* 参数面板里**新增**参数（本次只是搬运 / 重组现有控件，不引入新功能）。
* 删除旧 widget（`StitchImageStrip` / `StitchControlsSheet`）—— medium 分支仍依赖它们。
* 国际化 / 主题切换 / 无障碍语义增强（如 Semantics 标签）作为额外改进——除非现有 a11y 因布局变更被破坏。
* 双底栏视觉精细化 polish（R-5 仅要求「至少可区分」，全面精细化是 PR-3 的可选项）。
* 空状态新设计（仅保留现有 `_EmptyHint`，不增加 CTA 按钮）。

---

## Research Notes

### Feasible approaches considered (历史记录)

* **Approach A**（全屏画布 + AppBar action）：未选；AppBar 太挤、画布最大但操作路径远。
* **Approach B**（持久底栏 + Sheet）✅ **采纳**：画布 ~75%，状态可见，高频路径直达。
* **Approach C**（整合 DraggableSheet 三档）：未选；单 sheet 容纳异质功能 + 手势冲突复杂。
* **Approach D**（Grid 风格 height-first 比例）：未选；画布最大也只到 ~60%，未彻底解决问题。

### 关键调研结论

* `DraggableScrollableSheet` 是 Flutter SDK 原生组件（无需新依赖）。
* `showModalBottomSheet` + `isScrollControlled: true` + `useSafeArea: true` 是项目内已使用过的模式。
* 拖入图片的 `ImageDropZone` 包在 `_StitchEditorBody` 外层，新方案保持该包裹层不变。
* router 拓扑确认：`/stitch` 是 tab branch，本任务不动 `router.dart` / `AppShell`。

---

## Open Questions

（无 —— 所有核心决策已敲定，进入实施前的 jsonl 配置阶段。）
