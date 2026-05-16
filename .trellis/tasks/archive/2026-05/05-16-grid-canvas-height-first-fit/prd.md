# grid preview canvas height-first fit

## Goal

在宫格切图编辑器的 compact / medium 布局下，让画布以"容器可用高度"为主进行铺满，避免画布按宽度撑成正方形后高度过大、导致整页（画布 + 控件面板）必须滚动才能看到控件的问题。

## What I already know

- 当前画布定义在 `lib/features/grid/presentation/widgets/grid_preview_canvas.dart:33-54`：外层使用 `AspectRatio(aspectRatio: 1)` 包住正方形 `Container`，于是画布永远是 1:1 的正方形——宽度铺满父容器即决定高度。
- compact / medium 模式的 body 在 `lib/features/grid/presentation/screens/grid_editor_screen.dart:196-209` 走 `ListView`：依次是 `GridPreviewCanvas` → `_SourceSizeWarning?` → `GridControlsPanel`，所以画布按 `ListView.maxWidth` 撑成正方形 + `GridControlsPanel` 高度相加超过屏幕高度，必须滚动。
- expanded / large 模式 (`:142-194`) 是两列布局，左侧画布同样 `AspectRatio(1)`，但因为旁边只有 `_SourceSizeWarning`，并且左列被 `SingleChildScrollView` 包裹，问题不那么明显——但仍然是「宽度优先」的逻辑。
- 画布预览的网格 overlay 计算在 `:91-165`，依赖 `constraints.biggest` 拿到画布尺寸后 `scaleX = size.width / effectiveWidth`、`scaleY = size.height / effectiveHeight`，所以画布的实际尺寸如何决定（宽度优先 vs 高度优先）不会破坏 overlay 数学。
- 设计稿描述（`grid_preview_canvas.dart:17-23`）原文照搬 `_3_宫格切图/code.html` 的 `aspect-square`，但产品现在更看重「不滚屏」体验。
- 响应式断点常量在 `lib/core/constants/breakpoints.dart`，`windowSizeClassOf(context)` 提供 compact/medium/expanded/large。
- 受影响测试：`test/features/grid/presentation/grid_editor_responsive_test.dart`（需要补充：compact 模式下"画布高度 ≤ 屏幕高度 - 控件区估值"，以及不出现垂直滚动）。

## Confirmed Decisions (user-approved 2026-05-16)

- ✅ **采用 Approach A: Column + Expanded 高度优先骨架**。
- compact / medium 模式的 body 从 `ListView` 重构为 `Column`。
- 画布外层：`Expanded(child: Center(child: AspectRatio(aspectRatio: 1, child: ...)))`，让画布占据剩余高度后保持 1:1 居中。
- 控件面板：放进 `SingleChildScrollView`，可单独滚动，不与画布抢空间。
- `_SourceSizeWarning` 保留在画布下方（画布 Expanded 之外、控件面板之前），作为非滚动的固定提示条；如果空间紧张可让 ImportZone/控件面板首项接管。
- expanded / large 双栏布局**不在本次改动范围**（旁边面板对滚动需求不同，画布列宽受 Row 约束）。
- 画布保持正方形（1:1），不引入「按源图实际宽高比」方案。

## Requirements

- compact / medium 模式：画布优先以容器可用高度铺满，保持正方形居中显示。
- compact / medium 模式 body 结构改为 `Column`：
  - `Expanded` 区：`Center` + `AspectRatio(1)` 包住的 `GridPreviewCanvas`。
  - 固定高度区（紧贴画布下方）：`_SourceSizeWarning`（条件渲染）。
  - 控件面板区：`SingleChildScrollView` 包 `GridControlsPanel`，max-height 由 `Column` 主轴布局决定（剩余空间），结合 FAB clearance。
- `GridPreviewCanvas` 自身不强制外层 `AspectRatio(1)`——把 `AspectRatio` 责任移到调用方，允许调用方决定先按宽 / 按高 fit（compact: 按高；expanded/large: 沿用现有用法）。
- 网格 overlay 的视觉与现有计算保持一致（`LayoutBuilder` 内部依旧 `scaleX = size.width / effectiveWidth`、`scaleY = size.height / effectiveHeight`）。

## Open Questions

(无 — 方案已确认。)

## Acceptance Criteria

- [ ] 在 360×640 / 411×731（典型手机 compact 尺寸）下，画布保持正方形居中铺满主区域，控件面板可在主轴剩余空间内滚动；整页**首屏即可看到画布 + 第一张参数卡**，无需先滚动才能看到控件。
- [ ] 画布宽 == 高（正方形约束），居中显示。
- [ ] expanded / large 双栏布局的视觉无回归（画布与右侧面板布局照旧）。
- [ ] grid 网格 overlay 在调整间距 / 切换 GridType 时表现与现有一致。
- [ ] `test/features/grid/presentation/grid_editor_responsive_test.dart` 中针对 compact 模式补充「画布尺寸为正方形 + 控件面板内部可滚动 + 整页不存在外层垂直 OverflowError」的断言并通过。
- [ ] `flutter analyze` 与 `flutter test` 干净。

## Technical Approach

- `grid_preview_canvas.dart`：
  - 移除外层 `AspectRatio(aspectRatio: 1)`，让 `Container` 直接接受调用方传入的尺寸约束；正方形语义由调用方负责。
  - 头部 doc-comment 更新：说明「调用方负责强制 1:1 约束 + 居中」。
- `grid_editor_screen.dart` → `_GridEditorBody` compact / medium 分支：
  - `ListView` → `Column(crossAxisAlignment: CrossAxisAlignment.stretch)`。
  - 主结构：
    ```
    Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: GridPreviewCanvas(),
            ),
          ),
        ),
        if (sourceTooSmall) _SourceSizeWarning(...),  // 固定高度提示
        SizedBox(height: 16),
        Expanded(  // 或 Flexible，根据滚动行为决定
          flex: 0,
          child: SingleChildScrollView(child: GridControlsPanel()),
        ),
      ],
    )
    ```
    实现时确认 `Expanded` flex 比例 / `Flexible(fit: loose)` 哪种最稳定（让画布占据「最大可行」，控件面板按需高度，溢出再滚动）。
  - 仍保留底部 FAB clearance（用 `Padding` 包 `_GridEditorBody` 即可；FAB 浮在画布列之上）。

## Decision (ADR-lite)

**Context**: 用户反馈宫格切图编辑页在手机 compact 模式下必须滚动才能看到所有控件，体验差。根因是 `AspectRatio(1)` 让画布按宽度撑满（≈ 屏幕宽度），加上下方控件面板（≥ 360 dp）总高度超过手机屏幕。

**Decision**: 采用 Approach A — compact / medium 模式重构为 `Column + Expanded` 高度优先骨架。画布优先占据剩余高度（保持 1:1 居中），控件面板独立内部滚动。

**Consequences**:
- ✅ 画布在手机上不再被纵向压扁/横向拉宽，达成「以高度铺满容器」语义。
- ✅ 用户首屏即可看到画布与第一张参数卡，符合直觉。
- ⚠️ 控件面板从「页面整体滚动」改为「内部滚动」，是行为变化；但收益更大且符合 spec/frontend/responsive-layout.md 推荐 pattern。
- ⚠️ `GridPreviewCanvas` 的 `AspectRatio(1)` 责任迁移到调用方；expanded / large 调用处需要同步包一层 `AspectRatio(1)` 以保持现状。

## Definition of Done (team quality bar)

- Tests 已更新覆盖 compact 模式下「不滚动」与「画布尺寸正方形」两条核心约束。
- `dart format .` / `flutter analyze` / `flutter test` 全部干净。
- `grid_preview_canvas.dart` 头部 doc-comment 同步更新（说明新布局策略与设计稿差异的原因）。
- 不破坏 stitch 编辑器、export 流程等相邻 feature 的布局表现。

## Research Notes

### Cause analysis

`GridPreviewCanvas` 外层 `AspectRatio(aspectRatio: 1)` 在受到「宽度有约束、高度无约束」的环境（典型 `ListView` child）下，会以 `maxWidth` 为基础计算 height = maxWidth，于是画布高度紧跟设备宽度——手机宽度普遍接近 400 dp，加上下方控件面板（间距 + 提示卡 + 类型 chips + 三张 bento 参数卡，估算 ≥ 360 dp）后整页超过常见手机的屏幕可用高度（约 600~720 dp），因此必然滚动。

### Feasible approaches

**Approach A: compact 改成 `Column` + `Expanded` 包画布（高度优先骨架）** (Recommended)

- How it works: compact / medium 模式的 `ListView` 改成 `Column`；画布外层换成 `Expanded(child: Center(child: AspectRatio(1, child: ...)))`；控件面板放进 `SingleChildScrollView`，可随内容滚动但不与画布抢空间。
- Pros:
  - 画布占据屏幕剩余高度，达成"以高度铺满容器"的直觉。
  - 短控件面板不滚动；长控件面板单独滚动，不影响画布可见性。
  - 与 spec/frontend/responsive-layout.md 中「主内容固定 / 副内容滚动」的常见 pattern 契合。
- Cons:
  - 控件面板从"页面整体滚动"变为"内部滚动"，是行为变化；不过预期收益更大。
  - 需要给 `_SourceSizeWarning` 找新位置（建议放进控件面板顶部或保留在画布下方但用固定高度）。

**Approach B: 用 `LayoutBuilder` 给画布加 `ConstrainedBox(maxHeight: constraints.maxHeight * 0.5)`** 

- How it works: 维持 `ListView`；在画布外层加一个 `ConstrainedBox`，按容器可用高度的 50% 限制画布最大高度；保留 AspectRatio(1) 让画布在宽高都受限时取较小值。
- Pros:
  - 改动最小，整体滚动行为不变。
  - 不需要重构控件面板。
- Cons:
  - "50%" 是经验值，不同手机比例下表现不稳定，仍可能有少量滚动。
  - 不真正达成"以高度铺满"的语义，只是降低问题严重度。

**Approach C: 计算"屏幕高度 − 控件面板预估高度"作为画布 maxHeight**

- How it works: 在 `_GridEditorBody` 里用 `MediaQuery.sizeOf` 拿屏幕高度，减去常量预估（AppBar 56 + 控件面板 ~360 + padding ~64），得到画布 maxHeight；外层仍可保留 `ListView`。
- Pros:
  - 不动滚动模型，但能精确控制画布高度。
- Cons:
  - 估算耦合控件面板内部尺寸；任何控件面板调整都要回来改常量，维护成本高。
  - 跨主题字号 / a11y 文本缩放下估算会失真。

### Recommendation

倾向 Approach A（重构成 `Column + Expanded` 高度优先骨架），它最契合用户的需求语义、可维护性最高；Approach B 是退路（如果用户不愿意改滚动行为），Approach C 不推荐。

## Out of Scope (explicit)

- 不改变画布的视觉风格（边框、阴影、圆角与现状保持一致）。
- 不改 expanded / large 模式的两列布局策略。
- 不引入"按源图实际宽高比"的画布形状（保持 1:1 正方形）。
- 不改 `_3_宫格切图/code.html` 等 design mock。
- 不优化控件面板的内部排版（仅可能从 ListView 一节变为面板内部单独滚动）。

## Technical Notes

- 关键文件：
  - `lib/features/grid/presentation/widgets/grid_preview_canvas.dart`（核心改动：移除/调整 AspectRatio 外层）
  - `lib/features/grid/presentation/screens/grid_editor_screen.dart`（compact / medium 分支骨架）
  - `test/features/grid/presentation/grid_editor_responsive_test.dart`（补充 compact 不滚动断言）
- 相关 spec：
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/responsive-layout.md`
  - `.trellis/spec/frontend/state-management.md`
