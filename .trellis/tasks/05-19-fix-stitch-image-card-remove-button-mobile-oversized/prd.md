# Fix: 长图拼接图片卡片移除按钮在移动端尺寸过大

## Goal

修复 `StitchImageStrip._ImageCard`（长图拼接编辑器，compact / medium 屏幕）卡片右上角"移除"按钮在移动端视觉上过大、与桌面端 `_VerticalImageRow` 同功能按钮不一致的问题，同时确保符合项目 spec 中的 **48×48 dp 触摸目标** a11y 要求。

## What I already know

### 问题代码定位

- **问题端（移动端）**：`lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart:227-244` —— `_ImageCard` 中 `Stack > Positioned > Material > IconButton`，IconButton 配置：
  - `iconSize: 16`、`visualDensity: VisualDensity.compact`、`padding: EdgeInsets.zero`
  - `constraints: BoxConstraints(minWidth: 24, minHeight: 24)`
  - **未设置 `tapTargetSize`** → 走默认 `MaterialTapTargetSize.padded`（48×48 dp）
- **对照端（桌面端）**：`lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart:282-290` —— `_VerticalImageRow` 行内 IconButton 配置：
  - `iconSize: 18`、`visualDensity: VisualDensity.compact`、`padding: EdgeInsets.zero`
  - `constraints: BoxConstraints(minWidth: 32, minHeight: 32)`
  - 同样**未设置 `tapTargetSize`**，但视觉上"正常"
- **对照端（顶部按钮）**：`stitch_image_strip.dart:89, 102` 顶部「添加」「清空」`TextButton.icon`，显式 `tapTargetSize: MaterialTapTargetSize.shrinkWrap` → 紧凑形态

### 根因分析

1. `IconButton` 的默认 `MaterialTapTargetSize` = `padded`，会把 widget 外层包到 ≥ 48×48 dp（即使 `constraints` 设置了 24×24，padded 仍会向外扩展点击区域）
2. **移动端**：`Positioned(top: 4, right: 4)` 把 IconButton 浮在卡片右上角，**没有外部尺寸约束**，padded 完全展开成 48×48，视觉上「巨大」
3. **桌面端**：`_VerticalImageRow` 把 IconButton 放在 `Row` 中，外侧有 56×56 的缩略图作视觉对照，48×48 不那么显眼

### Spec 约束（关键发现）

`.trellis/spec/frontend/component-guidelines.md:385-435` 明确：

- **Minimum tap target**：48×48 dp（Android），44×44 dp（iOS）
- 顶层屏幕应使用 `meetsGuideline(androidTapTargetGuideline)` / `iOSTapTargetGuideline` widget test 守护
- Editor screens (stitch / grid) 当前未覆盖 surface-level a11y guideline test —— 是 known gap

→ **当前移动端 48×48 实际上符合 a11y spec**；桌面端 32×32 反而违反 spec（虽然视觉好看）
→ 任务的真正难点是**视觉协调 vs a11y 合规**的权衡

### Theme 设定

- `lib/app/theme/app_theme.dart` 没有全局设置 `materialTapTargetSize`、`iconButtonTheme` —— 走 Flutter 默认值
- 没有项目级 a11y / tap target 政策文档

### 影响范围

- **唯一直接受影响的文件**：`lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart`
- **可能需要同步审查的文件**：`lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart`（桌面端 32×32 违反 spec）
- 其他 feature 检查：`grid/` 模块没有"图片列表 + 单卡删除按钮"的等价模式（grid 是单源图片 + 单元格替换交互），无类似 bug

## Assumptions (temporary)

- 用户感知到的"按钮太大"是移动端真机/模拟器横屏 + 卡片 110×140 dp 内 48×48 的角标显得突兀。
- 用户期望"和桌面端看起来一致"——但桌面端当前 32×32 是「违反 spec 的视觉妥协」，需明确以哪边为准。
- 不希望大幅改动交互（如改成长按弹菜单删除），仍保留"卡片角标删除按钮"这一交互形态。

## Open Questions (Blocking / Preference)

- ~~**Q1 [MVP scope]**~~ ✅ **决定：B 方案**——仅改 `stitch_image_strip.dart` 一个 IconButton。桌面端 `_VerticalImageRow` 当前 32×32 列为 known issue,本任务不联动。
- ~~**Q2 [测试策略]**~~ ✅ **决定：T2'（修订）**——新增针对性 widget test `test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart`，覆盖（1）点击 × 按钮触发 `onRemove`、（2）shrinkWrap 决策守护（生产 IconButton 渲染尺寸 ≤ 28×28，反向防止误改回 padded）。**不**跑 `meetsGuideline(androidTapTargetGuideline)` / `meetsGuideline(iOSTapTargetGuideline)`——本 widget 处明确放弃 ≥48dp 守护（详见 Q3 v2 修订）。
- ~~**Q3 [视觉尺寸]**~~ ✅ **决定：V2' 修订（ADR-lite v2 revision）**——iconSize=14、视觉 `BoxConstraints(minWidth: 24, minHeight: 24)`、**hit area = 24×24 (shrinkWrap)**。原 V2 padded 方案在真机测试中视觉仍过大：`MaterialTapTargetSize.padded` 即使把 visual chrome 限制到 24×24，tap/hover 时的 48×48 splash 反馈圈仍占据完整 48×48，与 chrome 24×24 错位，视觉上仍显得"按钮过大"。用户决定退到 `MaterialTapTargetSize.shrinkWrap`，主动放弃 ≥48dp tap target 守护，作为显式视觉/a11y trade-off。适用边界仅卡片角标场景。

## Requirements (locked)

- 移动端 `_ImageCard` 右上角"移除"按钮：
  - 视觉尺寸 24×24（与原代码 `constraints` 设计意图一致）
  - **hit area = visual = 24×24 dp (shrinkWrap)** —— 显式违反 `androidTapTargetGuideline` (≥48dp) / `iOSTapTargetGuideline` (≥44dp) 作为视觉/a11y trade-off（详见 Decision (ADR-lite) v2 revision）
  - tooltip 保留 `'移除'`
  - 不破坏外圈 `Material(circle, surface@0.9)` 的视觉风格（圆形浅色底 + close icon）
- 桌面端 `_VerticalImageRow` 不联动修改（known issue 列入 follow-up）
- 长按图片卡片触发拖拽重排手势不被影响（`ReorderableRow` + `needsLongPressDraggable: true`）

## Acceptance Criteria (locked)

- [ ] AC1：移动端 (compact / medium 屏幕 WindowSizeClass) 卡片右上角 × 按钮视觉宽高 ≈ 24×24 dp，不再撑满到 48×48
- [ ] AC2：点击 × 按钮 24×24 视觉区域触发 `onRemove`
- [ ] AC3：`flutter test test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart` 全部通过，包含：
  - 点击 × 按钮调用 `onRemove`
  - **shrinkWrap render size guard**：生产 IconButton 渲染尺寸 ≤ 28×28 dp（反向守护，防止误改回 padded）
- [ ] AC4：`flutter analyze` clean
- [ ] AC5：`flutter test` 整体绿（不引入回归）
- [ ] AC6：长按图片卡片仍能触发 `ReorderableRow` 的拖拽手势（不被 hit area 区域抢走）

## Technical Approach

### 修改点 1：`stitch_image_strip.dart` `_ImageCard` 右上角 IconButton

将 `Positioned > Material > IconButton` 改造为「hit area = visual = 24×24 (shrinkWrap)」紧凑方案：

```dart
Positioned(
  top: 4,
  right: 4,
  child: Material(
    color: colorScheme.surface.withValues(alpha: 0.9),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: IconButton(
      tooltip: '移除',
      iconSize: 14,                                          // 视觉 icon 大小
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        // shrinkWrap：hit area 紧贴 visual chrome 24×24，不再外扩到 48×48。
        // splash 反馈圈也收敛到 chrome 内，视觉真正紧凑。
        // 代价：违反 androidTapTargetGuideline / iOSTapTargetGuideline（≥48 / ≥44 dp）。
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // 不设 visualDensity（保留 standard，避免与 shrinkWrap 叠加产生意外尺寸）
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
      onPressed: onRemove,
    ),
  ),
),
```

关键差异（vs 原始（前一轮 implement 完成的）padded 代码）：

| 字段 | 原始 (V2 padded) | 修订 (V2' shrinkWrap) | 理由 |
|------|------|------|------|
| `iconSize` | 14 | 14 (不变) | 视觉 icon 仍 14×14 |
| `visualDensity` | **未设**（standard） | **未设**（standard） | 不变 |
| `tapTargetSize` | `padded`（hit area 48×48） | `shrinkWrap`（hit area = visual 24×24） | 真机测试反馈 padded 的 splash 反馈圈仍让按钮看起来过大 |
| `constraints` | minWidth: 24, minHeight: 24 | 同上 (不变) | 视觉 chrome 24×24 不变 |

#### 为什么有效（V2' shrinkWrap）

`MaterialTapTargetSize.shrinkWrap` 行为：

- IconButton 的渲染尺寸**紧贴** `constraints` + `iconSize` 决定的视觉 chrome
- splash / hover / focus 反馈圈也只在视觉 chrome 范围内（24×24）扩散
- 用户点击区域 = 视觉区域 = 24×24 dp
- **代价**：低于 Material 3 默认推荐的 48dp 最小 tap target，违反 a11y guideline

这是用户在真机测试后做出的**显式 trade-off**：在卡片角标这种视觉空间极度受限的场景（110×140 卡片右上角），视觉一致性优先于 ≥48dp tap target 守护。

> ℹ️ 历史记录：原始 V2 方案 (padded) 是想保留 ≥48dp 守护、同时通过 `constraints` 限制 visual chrome 到 24×24。但 padded 在视觉小 chrome 上的 splash 反馈圈仍占据完整 48×48，与 chrome 错位、视觉上看起来比 chrome 大。完整原始方案的代码保留在本节的 git history 中，可对比参照。

### 修改点 2：新增 `stitch_image_strip_test.dart`

新增文件 `test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart`：

测试结构（V2' 修订后只剩两个 testWidgets）：

```dart
testWidgets('tapping × removes the image from the stitch session via the controller', (tester) async {
  // pump StitchImageStrip + 注入 _FakeRepo 的 imageImportRepository
  // 点击 find.byTooltip('移除')
  // 断言 importedImagesProvider(.stitch) 从 1 → 0
});

testWidgets('production _ImageCard × button render size is shrinkWrap-tight (≤ 28×28, NOT 48×48)', (tester) async {
  // 反向 sanity 守护——防止未来误改回 padded 让按钮膨胀到 48×48
  // 用 find.ancestor(of: tooltip '移除', matching: IconButton) 定位真实生产 IconButton
  // 断言 tester.getSize(removeButton) ≤ 28×28
  // 测试 doc comment 明确：本测试故意守护"违反 a11y guideline"的状态
});
```

**移除**的测试（V2 → V2' 修订时删除）：

- `meets Android tap target guideline (≥ 48×48 dp)` —— shrinkWrap 后必 fail，与决策冲突
- `meets iOS tap target guideline (≥ 44×44 pt)` —— 同上
- `_RemoveButtonHarness` mirror harness —— 仅服务于 meetsGuideline，跟着删

### 不变项

- `_VerticalImageRow`（桌面端）保持原样（known issue,follow-up 处理）
- 顶部 `添加 / 清空` 按钮（已有 `shrinkWrap`）不动
- `ReorderableRow` 长按拖拽手势机制不动

## Decision (ADR-lite)

### v1 (superseded by v2 — kept for history)

**Context**: 长图拼接图片卡片右上角"移除"按钮在移动端视觉过大（48×48），与桌面端 (32×32 视觉) 不一致。根因是 `IconButton` 默认 `tapTargetSize: padded` 行为在 `Positioned` 无约束容器中完全展开。直接缩小到 24×24 会让 hit area 也跌破 spec 要求的 48dp。

**Decision**: 采用「视觉 24×24 + hit area 48×48」**解耦方案**——保留 Material 推荐的 padded tap target、同时通过 `constraints` 限制 visual chrome 到 24×24。仅改一个文件、新增一个 widget test。桌面端 `_VerticalImageRow` 的 32×32 hit area 违规列为 known follow-up（独立任务跟进）。

**Consequences**:
- ✅ 视觉一致性提升（视觉 chrome 不再"巨大"）
- ✅ a11y 合规（meetsGuideline 通过）
- ✅ 范围最小，回归风险低
- ⚠️ 桌面端 32×32 hit area 违反 spec 仍未解决（known issue，后续独立任务）
- ⚠️ 视觉 hover/click feedback 在 48dp hit area 范围内可能与 chrome 24×24 错位（Material default 行为，**实测后证实这就是 v1 失败的根因**）

### v2 (revision — **current decision**)

**Context (revision)**: v1 方案在真机测试中**视觉仍过大**。根因：`MaterialTapTargetSize.padded` 即使把视觉 chrome 限制到 24×24，tap/hover 时的 splash 反馈圈仍占据完整 48×48 范围。用户感知的"按钮过大"不是 chrome 大，而是**splash 反馈圈大**——chrome 24 dp 居中浮在 48 dp 反馈圈中，每次点击/悬停都看到一个比 chrome 大一倍的浅色高光，视觉上"按钮还是太大"。v1 把视觉解耦理解为「只看 chrome 不算 feedback」，但用户真机评估把 feedback 圈也算进"按钮视觉"——这是 v1 决策时的盲点。

**Decision**: 退到 `MaterialTapTargetSize.shrinkWrap`，hit area = visual = 24×24。**主动放弃** ≥48dp 最小 tap target 守护（违反 `androidTapTargetGuideline` / `iOSTapTargetGuideline`），作为显式视觉/a11y trade-off。

**Consequences**:
- ✅ 视觉感受真正紧凑（splash 反馈圈也收敛到 24×24）
- ⚠️ a11y guideline 违规：本 widget 在 `meetsGuideline(androidTapTargetGuideline)` 与 `iOSTapTargetGuideline` 都会 fail。本任务的 widget test 不跑这两个 guideline（详见 Q2 修订），全局 a11y test（home / export 等）继续守护其他屏幕的最小 tap target，不受本任务影响
- ⚠️ 桌面端 `_VerticalImageRow` 32×32 hit area 与此一致（known issue 状态保持）
- 📌 **适用边界**：仅卡片角标场景（视觉空间 ≤ 110×140 dp，× 按钮浮在右上角）。其他按钮——AppBar IconButton、顶部 Add/Clear、Editor 主 CTA——仍应满足 48dp 最小 tap target
- 📌 测试侧增加「反向 sanity 守护」：生产 IconButton 渲染尺寸断言 ≤ 28×28。若未来有人误改回 padded，按钮会膨胀到 48×48 触发断言，提醒「这是显式 trade-off,不是疏忽」

## Implementation Plan (single PR)

1. **修改 `stitch_image_strip.dart:227-244`**：按 Technical Approach 改造 `_ImageCard` 的 IconButton
2. **新增 `test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart`**：2 个 testWidgets case（V2' 修订后：onRemove 集成路径 + shrinkWrap 反向 sanity 守护）
3. **跑 `flutter analyze` + `flutter test`**：全绿
4. **真机/模拟器视觉检查**（compact + medium + expanded + large）：移动端 × 按钮视觉缩小到 24×24；桌面端不变
5. **更新 PRD**：标记 AC 完成状态、记录 follow-up known issue

## Definition of Done (team quality bar)

- Tests added/updated（widget test 或 a11y guideline test）
- Lint / typecheck / CI 全绿
- 若需要沉淀 spec 知识点（如 Pitfall / Pattern / Caveat），同步更新 `.trellis/spec/frontend/component-guidelines.md`
- 真机/模拟器视觉验证（如果可行）

## Out of Scope (explicit)

- 大规模改动图片列表交互形态（如改成长按菜单 / 侧滑删除）
- AppBar 上的标准 IconButton（home / grid / export 等）—— 这些走 Material 默认 48dp 是正确做法
- Grid 编辑器（grid 没有同类列表删除按钮，无需联动）
- 项目级 IconButton 主题统一（如设置全局 `iconButtonTheme`）—— 若需要，独立任务

## Technical Notes

### Flutter 触摸目标机制

- `IconButton.tapTargetSize` 默认 = `MaterialTapTargetSize.padded`（48×48 dp 外扩点击区域），即使 child 视觉很小。**注意**：padded 不仅外扩 hit area，**splash / hover / focus 反馈圈也在 48dp 范围内扩散**——这是 v1 → v2 修订的根因（见 Decision v2）。
- `MaterialTapTargetSize.shrinkWrap` 取消外扩，widget（含 feedback 圈）紧贴 `constraints`。本任务最终采用方案。
- ⚠️ `visualDensity: VisualDensity.compact` **会**进一步影响 tap target（不是只压缩视觉密度）：在 `IconButton.styleFrom` 上同时设 `padded + compact` 会把 hit area 从 48 砍到 40 dp（`compact.baseSizeAdjustment * interval(4) = (-8, -8)`），违反 `androidTapTargetGuideline`。详见 spec → `component-guidelines.md` → 「Pitfall: `IconButton` `tapTargetSize: padded` cancelled by `visualDensity: compact`」
- **本任务最终方案（V2' / Decision v2）的标准做法**：`tapTargetSize: shrinkWrap` + `constraints` + `iconSize` 控制视觉大小 + **不**叠加 `visualDensity: compact`（保留 standard 即可，shrinkWrap 已经收敛尺寸，叠加 compact 没有正向收益且会让 hit area 进一步小于 visual chrome 的下限）。
- 一般场景（非卡片角标）仍推荐 `tapTargetSize: padded`（默认）+ `constraints` + `iconSize` 解耦，参考 spec 同名 Pitfall 章节的「✅ Correct」示例。

### Spec 沉淀（本任务产出）

本次任务前两轮（v1 implement + check）误把 `padded + compact` 一起写，被 check 阶段反向 sanity test 抓到。两个知识点已沉淀到 spec：

- `.trellis/spec/frontend/component-guidelines.md` → 「Pitfall: `IconButton` `tapTargetSize: padded` cancelled by `visualDensity: compact`」（Accessibility 章节）
- `.trellis/spec/frontend/component-guidelines.md` → 「Pattern: Direct render-size guard for private widget a11y-critical children」（紧邻 `meetsGuideline` Pattern）

v2 修订后产出的第三个知识点（padded 视觉感受 / shrinkWrap 适用边界）评估后**不**沉淀到 spec —— 详见本任务的 implement summary（理由：现有 Pitfall 章节已涵盖"padded 视觉问题"的可能性；shrinkWrap 例外是单一场景决策，沉淀到 PRD ADR-lite + 生产代码注释已经足够，全局 spec 强调"接受 a11y 违规"可能误导后续开发）。

### 参考文件

- `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart:227-244`（问题代码）
- `lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart:282-290`（对照代码）
- `.trellis/spec/frontend/component-guidelines.md:385-435`（a11y 约束）
- `.trellis/spec/frontend/responsive-layout.md`（WindowSizeClass 分支）

### 现有 a11y test 覆盖

- 已有：`home_screen_a11y_test.dart`、`export_screen_a11y_test.dart`
- 缺失（known gap）：`stitch_editor_a11y_test.dart`、`grid_editor_a11y_test.dart`

## Research References

（暂无外部研究依赖；Flutter Material IconButton 行为可直接参考 Flutter SDK 文档）
