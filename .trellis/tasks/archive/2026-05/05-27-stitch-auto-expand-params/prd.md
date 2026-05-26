# 移动端长图拼接：添加图片后自动展开参数面板

## Goal

在 compact 视口（< 600 dp）下，长图拼接编辑器的 inline 参数面板
（`StitchInlineControlsContainer`）当前默认收起，用户必须主动点击
底部 `[⚙ 参数]` chip 才能看到所有参数（基础 / 边框 / 圆角间距等）。
对**首次进入编辑器并添加图片**的用户来说，这是一个隐藏的发现成本。

**目标**：当用户在 compact 编辑器里**导入图片**（empty → non-empty）
时，自动把 `stitchControlsInlineVisibleProvider` 翻为 `true`，让参数
面板**首次展开**，使用户在画布出现的同时立刻看到可调节项；后续
是否重新展开/收起需要在 brainstorm 中决策。

为什么：减少首次使用的"功能盲区"，让 compact 用户的核心操作链
（添加图片 → 调参 → 导出）更顺畅；与 medium / expanded / large
档已经常驻显示控制面板的体验对齐。

## What I already know

### 现状代码位置

- `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart:272`
  ```dart
  final stitchControlsInlineVisibleProvider = StateProvider<bool>((_) => false);
  ```
  默认隐藏，由 `_ParamsChip` toggle。
- `lib/features/long_stitch/presentation/widgets/stitch_inline_controls_container.dart`
  watches the provider，AnimatedSize + AnimatedSwitcher 做展开动画。
- `lib/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar.dart`
  内 `_ParamsChip`（行 ~175）通过 `update((v) => !v)` toggle。
- `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart:36`
  `StitchEditorController.build()` 内已有
  `ref.listen<List<ImportedImage>>(importedImagesProvider(kind), …)`
  监听导入列表变化（同处也已处理 subtitle 重置的 empty→non-empty 触发）。
  这是我们要扩展自动展开逻辑的天然挂载点。

### 导入入口（4 类，全部汇入 imageImportControllerProvider）

- 相册：`StitchEditorController.addFromGallery`
- 相机：`addFromCamera`
- 剪贴板：`pasteFromClipboard`
- 拖拽：`ImageDropZone(sessionKind: stitch)`（包裹在 `_StitchEditorBody` 外）

所有入口最终都触发 `importedImagesProvider(stitch)` 列表变更，因此
扩展 `ref.listen` 即可统一覆盖所有路径。

### 当前测试覆盖

- `test/features/long_stitch/presentation/widgets/stitch_inline_controls_container_test.dart`
- `test/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar_test.dart`
- `test/features/long_stitch/presentation/providers/` （subtitle 重置相关测试已在此处覆盖 empty→non-empty 触发模式）

### 仅 compact 受影响

- compact (< 600 dp)：用 `StitchEditorBottomBar` + `StitchInlineControlsContainer`，参数面板**默认隐藏**。← 本任务唯一改动目标
- medium：用 `StitchControlsSheet`（始终可见）—— 不受影响
- expanded / large：用 `StitchControlsPanel` 常驻右侧 —— 不受影响

## Assumptions (temporary)

- 触发源是 `importedImagesProvider(stitch).length` 从 0 变为 ≥ 1
  （而不是单次 add 事件计数，因为列表可一次性导入多张）。
- "自动展开"只关心首次添加，**不**意味着 controller 在用户手动
  收起后还要硬翻回来（待 Open Questions 决策）。
- 不影响 medium / expanded / large 任何一档（其参数面板本就常驻
  显示，`stitchControlsInlineVisibleProvider` 在那几档下根本不被
  消费）。

## Open Questions

> 全部已通过 brainstorm 决策完毕。决策摘要见 `Decision (ADR-lite)`，
> 实现挂载点见 R2，触发语义见 R3/R4/R5，spec 同步见 R8。
> 测试粒度（controller-level 单元测试 + 可选 widget 集成测试）已并入 R7。

## Requirements

### R1 仅 compact 生效
- 改动只影响 compact 视口（< 600 dp）下消费
  `stitchControlsInlineVisibleProvider` 的渲染路径。
- medium / expanded / large 三档不变：它们渲染的是
  `StitchControlsSheet` 或 `StitchControlsPanel`，不消费该 provider。

### R2 触发挂载点：扩展现有 ref.listen
- 改动点统一收敛在
  `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
  的 `StitchEditorController.build()` 内现有
  `ref.listen<List<ImportedImage>>(importedImagesProvider(kind), …)`
  块（与 subtitle 重置同处）。
- 在同一 listener 内**追加** `stitchControlsInlineVisibleProvider`
  的边沿翻转副作用，**不**新增独立的 listener/provider。
- 副作用 emit 方式：
  `ref.read(stitchControlsInlineVisibleProvider.notifier).state = …`。

### R3 empty → non-empty 边沿：自动展开
- 当导入列表 length 从 `0` 变为 `≥ 1`（任意 empty→non-empty 边沿）
  时，将 `stitchControlsInlineVisibleProvider` 设为 `true`。
- 同一会话内多次 empty→non-empty（清空再导）**都**触发展开。
- 触发**不依赖**导入来源：相册 / 相机 / 剪贴板 / 拖拽全覆盖
  （因为四类入口都汇入 `importedImagesProvider(stitch)`）。

### R4 non-empty → empty 边沿：自动收起
- 当导入列表 length 从 `≥ 1` 变为 `0`（手动清空 / 移除全部）
  时，将 `stitchControlsInlineVisibleProvider` 设为 `false`。
- 触发源包含但不限于：`StitchEditorController.clear()`、
  `StitchImageSheet` 中逐张移除最后一张、`05-26-mobile-stitch-secondary-page`
  里的"退出二次确认 → 清空"路径。

### R5 不强制覆盖用户手动操作
- **用户在"有图状态"下手动点 `[⚙ 参数]` chip 收起面板后**，
  仅当列表先经历完整的 `non-empty → empty → non-empty` 旋回
  才会再次自动展开。
- 本任务**不**在 R3 内做"已经为 true 就 no-op"的优化（StateProvider
  对同值赋值不会重建消费者），但语义保证：在 `[1..N] → [1..M]` 这种
  "有图变化但跨过 empty"的过渡里**不**主动翻转可见性。

### R6 既有测试不破
- `stitch_editor_bottom_bar_test.dart` 中 `[⚙ 参数]` toggle 测试
  保持绿（toggle 本身行为不变）。
- `stitch_inline_controls_container_test.dart` 中可见性渲染测试
  保持绿（消费 provider 的方式不变）。

### R7 新增测试
- 至少新增两条 controller-level 单元测试覆盖：
  - empty→non-empty 边沿后 `stitchControlsInlineVisibleProvider` 为 `true`
  - non-empty→empty 边沿后 `stitchControlsInlineVisibleProvider` 为 `false`
- 第三条单元测试：在 `[1] → user toggle 收起 → [1,2]` 序列里
  provider 保持为 `false`（验证 R5 不被覆盖）
- 可选：widget 层的 compact 集成测试，验证导入即面板出现的渲染链路。

### R8 spec 同步
- 在 `.trellis/spec/frontend/component-guidelines.md` 的 compact
  编辑器章节（由 `05-26-mobile-stitch-secondary-page` 引入）末尾
  追加一条 UX 约定，措辞示意：
  > **compact 编辑器导图即展开参数面板**：当导入图片列表从空
  > 变为非空时，自动展开 inline 参数面板；当列表从非空变为空
  > 时，自动对称收起。在"有图状态"下的任何变化（add 单张 /
  > remove / reorder）都不翻转面板可见性，以尊重用户对
  > `[⚙ 参数]` chip 的显式操作。
- 约定 anchor 在 `stitchControlsInlineVisibleProvider`，引用
  `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`。

## Acceptance Criteria (evolving)

### compact 自动展开
- [ ] compact 视口下，编辑器初次打开（图片列表为空）时面板**保持收起**
- [ ] compact 视口下，**首次**导入任一图片后面板**自动展开**（动画与现有 toggle 一致）
- [ ] compact 视口下，导入图片后用户手动点 `[⚙ 参数]` 收起，
      然后**继续添加**第 2 张图（列表保持 non-empty），面板**保持收起**（尊重用户意图）
- [ ] compact 视口下，用户清空所有图片后面板**自动收起**；
      再次导入图片，面板**再次自动展开**

### 跨档不变
- [ ] medium / expanded / large 视口下，行为**不变**（无 regression）
- [ ] 既有 `stitch_editor_bottom_bar_test.dart` toggle 测试全绿
- [ ] 既有 `stitch_inline_controls_container_test.dart` 可见性测试全绿

### 新增测试
- [ ] controller-level 单元测试覆盖 empty→non-empty 边沿后 visible == true
- [ ] controller-level 单元测试覆盖 non-empty→empty 边沿后 visible == false
- [ ] controller-level 单元测试覆盖 "有图态内手动收起后继续 add" 不被覆盖

### Spec
- [ ] `.trellis/spec/frontend/component-guidelines.md` compact 编辑器
      章节追加 "导图即展开参数面板" 约定（R8）

## Definition of Done

- `flutter analyze` 0 error 0 warning
- `dart format .` 已应用
- 既有 + 新增 `flutter test` 全绿
- 在 spec 内增加（或扩展）相关章节（如决定要加）
- PRD `Out of Scope` 之外的需求全部实现

## Out of Scope (explicit)

- medium / expanded / large 视口的任何改动
- 修改 `StitchControlsSheet` / `StitchControlsPanel` 本身
- 修改 inline 面板的高度 / 动画曲线 / chip 文案
- 长图拼接以外的功能（宫格切图等）
- **"用户意图记忆"**：本任务不引入"用户已经主动操作过 chip"的
  持久标记；R5 的语义仅靠 empty/non-empty 边沿天然实现，不写
  额外 flag 进 `StitchEditorState`

## Decision (ADR-lite)

**Context**: compact 视口的 inline 参数面板默认收起，新用户难以
发现 `[⚙ 参数]` chip 入口。需要平衡"可发现性"与"不打扰用户的
显式收起操作"。

**Decision**: 采用 **B = empty/non-empty 边沿触发 + 清空对称收起**：
- empty→non-empty 自动 visible=true
- non-empty→empty 自动 visible=false
- 有图态内的任意变化（add / remove 单张 / reorder）**不**翻转可见性
- 实现挂载在现有 `ref.listen<List<ImportedImage>>` 块内，与 subtitle 重置
  的边沿触发模式一致

**Consequences**:
- ✅ 新用户首次添加即看到参数 —— 解决发现性问题
- ✅ 用户手动收起后继续操作不会被覆盖 —— 尊重显式意图
- ✅ 清空再导是天然 "重置入口" 心智 —— 对称感强
- ⚠️ 没有"已自动展开过一次就不再触发"的记忆 —— 如果用户清空再导，
  会再次触发展开（这是设计的一部分，不是 bug）
- ⚠️ 不能覆盖"用户主动收起 + 立刻清空再导"的极端连击场景 —— 
  会再次自动展开，但本小姐认为这是合理的，因为 empty 边沿
  本身就是一种"语义重置"

## Technical Notes

- 主改动点：`lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
  的现有 `ref.listen<List<ImportedImage>>` 块（与 subtitle 重置同处）。
- 相关 spec：
  - `.trellis/spec/frontend/state-management.md`（ref.listen 模式）
  - `.trellis/spec/frontend/responsive-layout.md`（compact 三段式
    sheet/inline/panel 范式）
  - `.trellis/spec/frontend/component-guidelines.md`（最近 05-26 任务
    已新增 compact 编辑器约定，可能需要追加这条 UX 约定）
- 参考相邻任务：
  - `.trellis/tasks/archive/2026-05/05-26-compact/` — 引入 inline 控件
  - `.trellis/tasks/archive/2026-05/05-26-mobile-stitch-secondary-page/` — compact 二级页面 + PopScope
  - `.trellis/tasks/archive/2026-05/05-18-subtitle-reset-on-reselect/` — 同处 ref.listen 的 empty→non-empty 模式参考
