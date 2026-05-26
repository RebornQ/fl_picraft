# Compact 参数面板内联化改造

## Goal

把长图拼接编辑器**手机端 (compact, <600dp)** 的参数 sheet 从「点击 `[⚙ 参数]` → `showModalBottomSheet` 弹出 modal」改造为「点击 `[⚙ 参数]` → 在画布与底部栏之间内联展开/收起一个 `StitchControlsPanel` 容器」。

**Why**：
- 当前 `showStitchParamsSheet` 是模态弹窗，每次调参都要打开关闭，与底部栏的 `[+ 添加]` / `[🖼 N/20]` 行为相比交互"突兀"
- 内联面板可以与画布共存（挤压画布而非遮挡），使用户在调整参数时实时看到预览变化，符合"所见即所得"的编辑器交互范式
- 与 medium / expanded 形成清晰的渐进层级：medium 一直常驻 sheet，compact 可 toggle，expanded 右侧 dock —— 而非"compact 走 modal、medium 走 sheet"的割裂

## Prerequisites (前置完成项)

* **wireframe 草图已更新**（`docs/UI Design/Sketch/long-stitch-screen-wireframe.excalidraw`）：
  * compact 列内 sheet 虚框标注 `showStitchParamsSheet (弹出 modal)` → `InlineControlsContainer (内联展开/收起)`
  * compact 列底部说明 `⚙ 参数 → 弹出 sheet (Tab 栏 + 横向滚动卡片列表)` → `⚙ 参数 → 内联展开/收起面板 (画布挤压, toggle)`
  * 注释行 `StitchEditorBottomBar · Compact 三个按钮; ⚙ 参数 → 弹出 sheet` → `... ⚙ 参数 → 内联 toggle 面板`
  * JSON 结构完整性已校验通过（`python3 -c "json.load(...)"` 成功）
  * 实现阶段**必须以此草图为单一事实来源**（single source of truth），代码与草图描述需保持一致

## Requirements

### 行为规范

* `StitchEditorBottomBar` 的 `[⚙ 参数]` chip 改为 **toggle 控件**：
  * 默认状态：未选中（面板隐藏）
  * 点击：面板显隐切换，按钮进入 selected 高亮态
  * 高亮态使用 `FilledButton`（primary 填充）替代当前的 `FilledButton.tonal`，以视觉强化"激活"状态
* 仅参数 chip 受影响，`[+ 添加]` / `[🖼 N/20]` 保持原有 modal sheet 行为不变
* 点击画布或其它区域**不**收起面板（避免误触；用户必须显式再次点击参数按钮）

### 布局规范（compact only）

* `_StitchEditorBody` compact 分支由：
  ```
  Column(children: [Expanded(StitchPreviewCanvas())])
  ```
  改为：
  ```
  Column(children: [
    Expanded(StitchPreviewCanvas()),  // 画布自动挤压
    AnimatedSize(StitchControlsPanel | SizedBox.shrink)  // 内联可展开
  ])
  ```
* 面板可见时，**画布通过 `Expanded` 自动收缩**（不另设固定 splits）
* 面板高度：**固定 ~280dp**（估算：TabBar 48 + content max 224 + padding 8）；通过测试核对，必要时微调（参考 `StitchControlsPanel._buildBody` 内部的 `SizedBox(height: 224)` + TabBar 标准高度）
* medium / expanded / large 三个 size class **完全不受影响**（保留原 `StitchControlsSheet` 与 side-dock 布局）

### 动画规范

* 展开/收起：`AnimatedSize` + `FadeTransition` 组合，~250ms，`Curves.easeInOutCubicEmphasized`（MD3 emphasized easing）
* 隐藏时面板从布局中真正移除（`AnimatedSize` 高度 → 0 后 child 释放），避免无谓重建消耗
* 配合 `ClipRect` 防止内容在动画过程中越界绘制

### 状态管理

* 新增 Riverpod provider：`stitchControlsInlineVisibleProvider` 类型 `StateProvider<bool>`，默认 `false`
* `StitchEditorBottomBar._ParamsChip` 与新内联容器同读同写该 provider
* 该状态**不持久化**（与 PRD 历史决策一致：进入编辑器始终默认收起，避免上次会话状态污染新会话）
* 状态作用域：仅 compact 关心；medium / expanded 在 build 时**不读取**该 provider（避免无意义的重建订阅）

### 废弃路径

* `showStitchParamsSheet()` 在 compact 入口（`StitchEditorBottomBar._ParamsChip.onPressed`）的调用被替换，函数本身**保留**（向后兼容、单元测试可用；其它 entry 暂未发现）
* 关联测试 `stitch_params_sheet_test.dart` 保留（仍然覆盖函数行为），但 `stitch_editor_bottom_bar_test.dart` 需要更新：参数 chip 点击不再触发 modal，而是 flip provider

## Acceptance Criteria

* [x] wireframe 草图已更新为内联面板语义（前置已完成）
* [ ] 手机端点击 `[⚙ 参数]`：面板从底部 slide+fade 出现，画布高度同步收缩；按钮进入高亮态
* [ ] 再次点击 `[⚙ 参数]`：面板 slide+fade 收起，画布回填空间，按钮回未选中态
* [ ] 面板展开时所有原有 4 个 Tab（基础/电影台词/边框/圆角间距）功能与现有 `StitchControlsPanel` 完全一致（PRD §D1~D6 行为保留）
* [ ] 面板收起时 widget 树中不存在 `StitchControlsPanel`（用 `findsNothing` 断言）
* [ ] medium (600–840dp) 屏幕：底部 `StitchControlsSheet` 常驻不变，参数 chip 不出现（bottomNavigationBar 仅 compact 渲染）
* [ ] expanded / large (≥840dp) 屏幕：右侧 dock 布局不变
* [ ] 切换 size class（如旋转屏幕）从 compact 到 medium 时，`stitchControlsInlineVisibleProvider` 是否为 true 都不影响 medium 渲染
* [ ] 新增 widget 测试：
  * 点击参数 chip → 面板出现 + chip 进入 selected 态
  * 再点 → 面板消失
  * 面板内仍可正常切换 Tab、修改参数
  * provider 默认值 false
* [ ] `flutter analyze` clean、`dart format .` 已应用、`flutter test` 全绿
* [ ] 截图/录屏验证动画顺滑无掉帧（≥ 55fps）

## Definition of Done

* `flutter analyze` 无 warning / error
* `dart format .` 已应用
* `flutter test` 全部通过（含新增的 widget test）
* 手机端在真机或模拟器上人工验证（slide+fade 动画、画布挤压、toggle 行为）
* PR 描述包含改造前后对比 GIF / 录屏

## Technical Approach

### 新增

1. **`stitchControlsInlineVisibleProvider`**（位置：`lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` 末尾）
   ```dart
   /// Compact-only: whether the inline parameter panel is expanded.
   /// Not persisted across sessions — every fresh editor mount starts
   /// collapsed (consistent with the no-persist tab choice in PRD §D3).
   final stitchControlsInlineVisibleProvider = StateProvider<bool>((_) => false);
   ```

2. **`StitchInlineControlsContainer`**（新文件：`stitch_inline_controls_container.dart`）
   * `ConsumerWidget`，watch `stitchControlsInlineVisibleProvider`
   * 用 `AnimatedSize` + `AnimatedSwitcher` 实现 slide+fade
   * 内部装载 `StitchControlsPanel`
   * Material elevation: 3，topRadius 16，模拟从底部"抽出"的感觉
   * `ClipRect` 包裹防止动画越界

### 修改

1. **`stitch_editor_screen.dart`**：`_StitchEditorBody.build()` compact 分支由：
   ```dart
   return const Column(children: [Expanded(child: StitchPreviewCanvas())]);
   ```
   改为：
   ```dart
   return const Column(children: [
     Expanded(child: StitchPreviewCanvas()),
     StitchInlineControlsContainer(),
   ]);
   ```

2. **`stitch_editor_bottom_bar.dart`**：`_ParamsChip`
   * 改为 `ConsumerWidget`
   * `onPressed` 由 `showStitchParamsSheet(context)` 改为 `ref.read(stitchControlsInlineVisibleProvider.notifier).update((v) => !v)`
   * 根据 provider 值切换 `FilledButton` (selected) vs `FilledButton.tonal` (default)
   * tooltip 文案：selected 时 "收起参数"，否则 "展开参数"

### 不修改

* `StitchControlsPanel` 本体（已经 Tab 化、可复用）
* `StitchControlsSheet`（medium 仍使用）
* `showStitchParamsSheet` 函数本体（保留入口，删除调用即可）
* expanded / large 的 `_StitchEditorBody` Row 布局

## Decision (ADR-lite)

**D1 — Compact 参数面板从 modal 改内联**
* Context: 当前 compact 使用 `showModalBottomSheet`，每次调参打开关闭交互突兀
* Decision: 改为内联 `AnimatedSize` 折叠容器，按钮 toggle
* Consequences: 画布会被挤压（用户接受），状态管理多一个 provider，但 UX 一致性提升

**D2 — 固定高度而非自适应**
* Context: 不同 Tab 内容高度不一（基础 Tab 横向卡片 ~100dp + caption；圆角/间距 Tab 双 slider ~140dp）
* Decision: 固定 ~280dp，覆盖最大 Tab 内容
* Consequences: 部分 Tab 下方有少量空白，但避免切 Tab 时画布高度跳变（破坏视觉稳定性）

**D3 — provider 不持久化**
* Context: 与 PRD §D3 Tab 不持久化决策保持一致
* Decision: `StateProvider<bool>` 默认 false，session 内有效
* Consequences: 用户每次进入编辑器面板默认收起；简化心智，避免脏状态

**D4 — 点击外部不收起**
* Context: 类比 medium 的 `StitchControlsSheet` 常驻、不响应外部点击
* Decision: 仅参数按钮 toggle，画布点击不影响
* Consequences: 防止误触；用户明确控制；与底部栏其它 chip 的 modal 行为有差异（modal 点外部会关），但参数 chip 的 selected 视觉状态可补偿此心智差

## Out of Scope

* medium / expanded / large 的布局调整（本次只动 compact）
* `StitchControlsPanel` 内部 Tab 结构与样式（已经在 05-26-long-stitch-toolbar-tab-redesign 完成）
* `showStitchParamsSheet` 函数的删除（保留以备未来其它 entry）
* 横屏 (compact landscape) 的特殊处理（按 size class 判定，横屏宽度 ≥600dp 走 medium）
* 面板拖拽调整高度（固定 280dp，未来如有需要再加）

## Technical Notes

### 关键文件

* `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart` (lines 255–264 compact 分支)
* `lib/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar.dart` (lines 91–94 _ParamsChip onPressed)
* `lib/features/long_stitch/presentation/widgets/stitch_params_sheet.dart` (showStitchParamsSheet 当前实现)
* `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` (复用，不动)
* `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` (新增 provider)
* `lib/core/constants/breakpoints.dart` (windowSizeClassOf 工具)

### 测试文件

* `test/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar_test.dart` (需更新参数 chip 行为断言)
* 新增：`test/features/long_stitch/presentation/widgets/stitch_inline_controls_container_test.dart`

### 设计参考

* `docs/UI Design/Sketch/long-stitch-screen-wireframe.excalidraw` (compact 列已在本任务 prerequisites 阶段更新为"内联 toggle 面板"语义) —— **作为本任务实现阶段的单一事实来源**
* Material 3 motion: emphasized easing for layout transitions
  https://m3.material.io/styles/motion/easing-and-duration/applying-easing-and-duration

### 风险

* `AnimatedSize` 在子 child 为 `SizedBox.shrink()` 时如果不正确配合 `ClipRect`，可能短暂出现内容溢出 → 用 `ClipRect` 包裹
* 测试环境下动画时间需要 `tester.pumpAndSettle()` 等待完成，避免 flaky test
* `StatefulShellRoute` 在 tab 切换时保留 state，意味着 provider 值会留在内存中 —— 由于 provider 是默认 false 重启，**首次进入编辑器**始终是 false；但用户离开 → 回到拼图 tab 时 provider 保持上次值。是否需要在 `StitchEditorScreen.initState` 强制重置？→ 待笨蛋实现时决定，倾向**不重置**（用户 tab 切换是连续会话，强制重置反而意外）

## Implementation Plan (单 PR)

任务复杂度 = Simple-to-Moderate。预计 4~6 个文件改动，无外部依赖，**不拆 subtask**，单 PR 完成。

1. **Commit 1 — Provider + 容器**：新增 `stitchControlsInlineVisibleProvider` + `StitchInlineControlsContainer` widget
2. **Commit 2 — Screen 集成**：`_StitchEditorBody` compact 分支接入容器
3. **Commit 3 — BottomBar 重构**：`_ParamsChip` 改 ConsumerWidget + toggle 行为 + selected 视觉
4. **Commit 4 — 测试**：新增容器 widget test + 更新 bottom bar test
5. **Commit 5 — 文档 / 清理**：必要的 doc comment 更新

## Open Questions

(全部已通过 AskUserQuestion 解决)

* ~~显示方式~~ → 挤压画布（内联）
* ~~切换行为~~ → 点击参数按钮 toggle
* ~~高度~~ → 固定 ~280dp（计算最小所需，避免目前 sheet 偏高）
* ~~动画~~ → 从底部 slide + fade

剩余唯一开放点：
* **Provider 重置策略**：tab 切换回编辑器时是否强制 reset 为 false？倾向不重置，实现时如有强烈用户体验信号再调整。
