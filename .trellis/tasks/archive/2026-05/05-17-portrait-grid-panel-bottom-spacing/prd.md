# portrait grid panel bottom spacing

## Goal

排查竖屏（compact / medium）下宫格切图编辑屏 (`/grid`) 的控制面板 chrome 与底部导航栏 (`AppBottomNavBar`) 之间出现的"大片空白"，并修复该视觉问题，使整屏视觉延续 chrome 填充的设计意图。

## What I already know

代码现状（`lib/features/grid/presentation/screens/grid_editor_screen.dart` line 324–343）：

```dart
return Padding(
  // Bottom 96 dp clears the floating action button.
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Expanded(
        child: Center(
          child: AspectRatio(aspectRatio: 1, child: GridPreviewCanvas()),
        ),
      ),
      if (sourceTooSmall) ...[
        const SizedBox(height: 12),
        _SourceSizeWarning(...),
      ],
      const SizedBox(height: 16),
      Expanded(child: _buildControlsPanelChrome(context)),
    ],
  ),
);
```

- 外层 `Padding(EdgeInsets.fromLTRB(16, 16, 16, 96))` 中底部 **96 dp** 是为给 `FloatingActionButton.extended` 让位
- `Expanded(child: _buildControlsPanelChrome(context))` 会撑满 column 的剩余空间，但 chrome 的下沿停在 padding 的内边界 → **chrome 下方仍存在 96 dp 的页面背景裸露区**
- AppShell 的 Scaffold 已经在外层提供了 `bottomNavigationBar`，所以 chrome 之下的 96 dp 紧接着就是底部导航栏

视觉上的结果：

```
┌────────────────────────────────────┐
│ AppBar：宫格切图编辑                  │
├────────────────────────────────────┤
│ [Canvas 1:1]                        │
│                                     │
│ ── 16 dp gap ──                     │
│ ┌─ chrome (surfaceContainerLow) ─┐ │
│ │ NineGridSocialRow              │ │
│ │ GridTypeSelector               │ │
│ │ GridParameterCards             │ │
│ └────────────────────────────────┘ │
│                                     │
│      ← 96 dp 大片空白（page bg）  →   │
│                                     │
├────────────────────────────────────┤
│ AppBottomNavBar                     │
└────────────────────────────────────┘
```

### 关键事实

1. **96 dp 在所有情况下恒定**：无论 `state.hasSource` 是否为 true（FAB 显示/隐藏），96 dp 底部 padding 总是存在
   - `state.hasSource == false` → 没 FAB → 96 dp 全部裸露
   - `state.hasSource == true` → 有 FAB → FAB 只占右下角约 (160 × 48) dp，其余区域仍裸露
2. 上一轮任务 `05-17-grid-compact-panel-chrome-fill` 的目标是 chrome 填满 column 剩余高度，避免 chrome 下方的页面 bg 裸露，但**遗漏了**外层 96 dp 这一段
3. 这是设计意图与实现之间的不一致：spec 强调"chrome 背景覆盖什么本该是 page bleed"，但 96 dp 恰恰留出了 page bleed

## Root Cause

`grid_editor_screen.dart:326` 的 `EdgeInsets.fromLTRB(16, 16, 16, 96)` 把 FAB clearance 作为**外层 Padding** 实现，使 chrome 被迫缩短 96 dp。这个 96 dp 区域无任何 chrome 覆盖，露出 Scaffold 的页面背景，与 `bottomNavigationBar` 之间形成视觉上"卡顿"的空白带。

## Requirements

- chrome 视觉下沿与 `AppBottomNavBar` 上沿之间保留 **16 dp** 轻量间距（外层 Padding bottom 由 96 → 16）
- FAB 保持 `FloatingActionButtonLocation.endFloat`（悬浮，不占据 layout 流）
- chrome 内部 `SingleChildScrollView` 底部 padding 动态：`hasSource ? 80 : 16` dp
  - `hasSource == true`：80 dp（FAB extended ~48 dp + 安全缓冲 ~32 dp）→ 最末 bento card 滚动时可避开 FAB
  - `hasSource == false`：16 dp（无 FAB clearance 需求）
- expanded / large 侧边栏分支**完全不变**（FAB 仅浮在画布列上，不与 panel 冲突；chrome 的 scrollview padding 保持 16 dp）
- `GridControlsPanel` 不变（panel-has-no-outer-padding convention 保留）
- `kGridControlsPanelChromeKey` 仍可在两种 size class 下被测试定位到

## Acceptance Criteria

- [ ] compact (< 600 dp) 与 medium (600–840 dp) 设备下，chrome 视觉下沿距 `AppBottomNavBar` 上沿 ≤ 16 dp
- [ ] `state.hasSource == false` 状态下，chrome 之下无大于 16 dp 的页面背景裸露区
- [ ] `state.hasSource == true` 状态下：
  - chrome 视觉延伸到 nav bar 上方 16 dp
  - FAB 悬浮在 chrome 右下角，不遮挡 chrome 装饰边界（FAB 在 z-axis 上方）
  - 滚动到最底部时，最末 `GridParameterCards` 的 bento card 完全可见（不被 FAB 遮挡）
- [ ] expanded / large 分支视觉与现状一致（现有 widget / golden 测试通过）
- [ ] 新增 widget 测试：compact + medium chrome 底部距 body 底 ≤ 32 dp（覆盖 16 dp + 容差）
- [ ] `flutter analyze` / `dart format .` / `flutter test` 三红线全绿

## Definition of Done

- 单文件改动（`grid_editor_screen.dart`），不拆 subtask（改动范围紧凑、强耦合）
- 测试新增覆盖 compact + medium chrome 填充
- spec `.trellis/spec/frontend/responsive-layout.md` 中相关段落同步更新："FAB clearance 不放在外层 Padding，而是改造 scrollview bottom padding 动态值"
- `flutter analyze` / `flutter test` 全绿

## Decision (ADR-lite)

**Context**: 上一轮 `05-17-grid-compact-panel-chrome-fill` 让 chrome 填满 column 剩余高度，但保留了外层 96 dp 的 FAB clearance，导致 chrome 与 bottom nav 之间永久存在 96 dp page bg 裸露区。要么把 FAB clearance 移走，要么完全去除空白。

**Decision**: 采用 **Approach A — FAB clearance 内置到 chrome 的 scrollview bottom padding**：

1. `grid_editor_screen.dart:326` 外层 Padding 由 `EdgeInsets.fromLTRB(16, 16, 16, 96)` 改为 `EdgeInsets.fromLTRB(16, 16, 16, 16)`
2. `_buildControlsPanelChrome` 增加 `bottomPadding` 参数（默认 16 dp）
3. compact / medium 分支调用时传入 `bottomPadding: hasSource ? 80 : 16`
4. expanded / large 分支保持默认（16 dp）

**Consequences**:
- ✅ chrome 视觉延伸到 nav bar 上方 16 dp，无 page bg 裸露
- ✅ FAB 悬浮在 chrome 上方（M3 idiomatic 模式）
- ✅ 最末 bento card 通过 scrollview 内 padding 让位，可滚动避开 FAB
- ⚠️ chrome 右下角圆角 + outline 边界会被 FAB 视觉覆盖一小段（M3 接受的图层语义）
- ⚠️ `_buildControlsPanelChrome` 由无参变成命名参，可能需要更新现有 widget 测试

## Out of Scope (explicit)

- expanded / large 侧边栏分支的样式改动
- 长图拼接 (`stitch_editor_screen.dart`) 类似 FAB clearance 模式的同步重构（如确认存在类似问题，由后续任务跟进）
- FAB 位置 / 形态 / 文案 / 出现条件的变化
- `AppShell` 或 `AppBottomNavBar` 的任何改造
- subtask 拆分（单文件 + 两处紧密耦合的改动，整体作为一个任务执行）

## Implementation Plan

单 PR 单文件改动：

1. **修改 `_buildControlsPanelChrome`** —— 增加 `double bottomPadding = 16` 命名参数，传入到 `SingleChildScrollView.padding`
2. **修改 compact / medium 分支**:
   - watch 出 `state.hasSource`（已可通过 `gridEditorControllerProvider.select` 获得，与 `sourceTooSmall` 共用 watch）
   - 外层 Padding bottom 改为 16 dp
   - chrome 构造传入 `bottomPadding: hasSource ? 80 : 16`
3. **expanded / large 分支** —— 不传 `bottomPadding`，使用默认 16 dp
4. **测试**:
   - 新增 widget 测试断言 chrome 在 compact / medium 下底部距离 body 底 ≤ 32 dp
   - 验证 `hasSource == true` 时 scrollview 内最末元素 + 80 dp padding 可见
   - 现有 `kGridControlsPanelChromeKey` 定位测试不变
5. **spec 更新** —— `responsive-layout.md` 中 chrome 段落补充 "FAB clearance 通过 scrollview internal padding 实现，不放在外层 Padding" 的 convention

## Research References

（无需额外研究：M3 FAB.endFloat + scrollview internal padding 是众所周知 idiomatic 模式；本任务 root cause 与方案在代码内可完整推导）

## Technical Notes

### Layout structure (compact / medium target)

```
Scaffold (AppShell)
├ bottomNavigationBar: AppBottomNavBar
└ body
  └ navigationShell → GridEditorScreen
    └ Scaffold (nested)
      ├ appBar: AppBar
      ├ floatingActionButton: FAB.extended (if hasSource)  ← endFloat 悬浮
      └ body: SafeArea > ImageDropZone > _GridEditorBody
        └ Padding(LTRB 16, 16, 16, 16)            ← 96 → 16
          └ Column(stretch)
            ├ Expanded(Center(AspectRatio(1, canvas)))
            ├ [if sourceTooSmall] SizedBox(12) + warning
            ├ SizedBox(16)
            └ Expanded(_buildControlsPanelChrome(bottomPadding: hasSource ? 80 : 16))
              └ Container(decoration: surfaceContainerLow + outlineVariant + 16dp radius)
                └ SingleChildScrollView(padding: LTRB(16, 16, 16, hasSource ? 80 : 16))
                  └ GridControlsPanel
```

### Affected files

- `lib/features/grid/presentation/screens/grid_editor_screen.dart` — 主修改点（`_buildControlsPanelChrome` 函数签名 + line 296–344 单列分支）
- `test/features/grid/presentation/grid_editor_screen_chrome_test.dart`（若存在）/ 等价位置 — 调整 / 新增 widget 测试
- `.trellis/spec/frontend/responsive-layout.md` — chrome 填满段落补充 "FAB clearance 内置 scrollview padding" convention

### Related historic tasks

- `.trellis/tasks/archive/2026-05/05-17-grid-reactive-canvas-and-panel-chrome/` — 引入侧边栏 chrome
- `.trellis/tasks/archive/2026-05/05-17-grid-compact-panel-chrome-fill/` — compact / medium 引入 chrome 填满，**遗漏 FAB clearance**（本任务修复）
