# 导出页面微调：PreviewSkeleton 文案 & SaveDisclaimer 位置

## Goal

把导出页面的两个 UX 细节调整到更贴近用户语义的状态：

1. **PreviewSkeleton 文案语义化**：`"加载中..." / "刷新中..."` 改成 `"生成中..." / "重新生成中..."`，让用户更清晰地理解后台在「合成图片」而不是「加载已存在的资源」。
2. **SaveDisclaimer 上移**：把隐私说明（"所有处理均在本地完成…"）从导出页面底部移到 PreviewCard 上方，让用户在看到预览图之前就先读到隐私承诺，提高心安感。

## What I already know

### 文案改动涉及
- `lib/features/export/presentation/widgets/preview_skeleton.dart:53` — 实际渲染的文案
- 该文件第 13、14、30、31、46 行 — doc-comment 描述了"加载中..." / "刷新中..."
- `test/features/export/presentation/widgets/preview_card_test.dart` 第 110、129、137、154 行 — 测试断言与描述

### 布局改动涉及
- `lib/features/export/presentation/screens/export_screen.dart:104-155` — `_ExportBody` 组装顺序
- 当前顺序（compact + medium 公用）：`PreviewCard → FormatQuality/Watermark → SaveDisclaimer → 88dp spacer`
- 第 25–26 行 doc-comment 表格描述了该顺序
- 第 116–118 行注释说"Preview card spans the full row… the user sees the current export's rendered preview before any settings"
- 第 143–148 行注释解释了 88dp spacer 是给 endFloat FAB 留 clearance、避免 FAB 视觉覆盖 disclaimer

### 既有测试期望
- `test/features/export/presentation/export_screen_responsive_test.dart:54` 检查 SaveDisclaimer 存在（只 findsOneWidget，未断言位置）
- `test/features/export/presentation/export_screen_dark_mode_test.dart:42` 同上
- 两个测试都不依赖 disclaimer 的纵向位置，移动后无需改它们

## Requirements

### R1: PreviewSkeleton 文案
- `preview_skeleton.dart:53` 文案：`hasStale ? '刷新中...' : '加载中...'` → `hasStale ? '重新生成中...' : '生成中...'`
- 同步更新 `preview_skeleton.dart` 中 doc-comment 出现的旧文案（13、14、30、31、46 行）
- 同步更新 `preview_card_test.dart` 中的断言文本与测试描述（110、129、137、154 行）

### R2: SaveDisclaimer 上移到 PreviewCard 之上
- 调整后顺序（compact + medium 公用）：`SaveDisclaimer → PreviewCard → FormatQuality/Watermark → 88dp spacer`
- 在 SaveDisclaimer 与 PreviewCard 之间保留 16dp gap，保持节奏一致
- 底部 88dp spacer **保留**：FAB 仍然 endFloat，仍然会覆盖最后一个元素（现在是 WatermarkCard），clearance 仍然必要
- 同步更新 `export_screen.dart` 第 25–26 行 doc-comment 表格的顺序描述
- 同步更新第 116–118 行 PreviewCard 上方的"sees the preview before any settings"注释（现在 disclaimer 在更前面）
- 同步更新第 143–148 行底部 spacer 的注释（去掉"避免 FAB 覆盖 disclaimer"的措辞，改为通用的"FAB clearance"）

## Acceptance Criteria

- [ ] 真机/widget test 中 loading 首帧（无 staleBytes）显示「生成中...」
- [ ] 真机/widget test 中 loading 刷新帧（有 staleBytes）显示「重新生成中...」
- [ ] export 页面打开后，SaveDisclaimer 在 PreviewCard 之上（同列、纵向更靠顶）
- [ ] `flutter test` 全绿（preview_card_test 文案断言已同步更新）
- [ ] `flutter analyze` 无新增告警
- [ ] `dart format .` 无 diff

## Definition of Done

- Tests 更新并通过（widget test for skeleton 文案；现有 responsive/dark mode test 不需要改）
- `flutter analyze` clean
- `dart format .` clean
- 涉及的 doc-comment 与代码语义保持一致（不留下"加载中.../刷新中..."的死引用、不留下"disclaimer 在底部"的过时注释）
- 不需要新建 ADR：这是文案 + 位置的小调整，不影响架构决策

## Technical Approach

### 方案 A（推荐）：原地修改 + 同步更新注释和测试
- 直接在两个 widget 源文件与一个 test 文件中修改字符串与布局顺序
- 同步更新 doc-comment 中所有出现的旧措辞
- 不抽提取常量、不引入新组件、不改 PreviewLoading state 字段

理由：scope 极小，引入抽象反而违背 YAGNI。

### 不选的方案
- **方案 B**：把"生成中.../重新生成中..."提取为常量或 i18n key —— 项目目前没有 i18n 框架，单一处使用，不值得抽象（YAGNI）
- **方案 C**：把 SaveDisclaimer 设计成「可在 props 控制位置的容器」—— 同样违背 YAGNI，导出页只有这一处使用

### 实施顺序（一个小 PR）
1. 改 `preview_skeleton.dart`（代码 + 注释）
2. 改 `preview_card_test.dart`（断言 + 测试描述）
3. 改 `export_screen.dart`（_ExportBody 的 children 顺序 + 三处注释）
4. 跑 `dart format .` / `flutter analyze` / `flutter test`

## Decision (ADR-lite)

**Context**: 用户反馈两个 UX 细节希望调整 —— 预览加载文案的语义更贴近"在生成新图片"而非"在加载资源"；隐私说明在用户看预览图前更先看到能增强信任感。

**Decision**:
1. 文案改为「生成中... / 重新生成中...」（保留 `hasStale` 二分逻辑，只换字符串）
2. SaveDisclaimer 移到 _ExportBody children 首位，PreviewCard 之前；保留 16dp gap 与 88dp 底部 FAB clearance

**Consequences**:
- 用户读到的文案与"在合成图片"的实际后端行为对齐
- 隐私说明的视觉位置抬升，更容易被首次用户注意到
- 不影响响应式布局规则（FormatQuality/Watermark 在 medium+ 仍然 side-by-side）
- 不引入新的抽象，方案 B/C 不需要

## Out of Scope

- 不改 PreviewLoading state 字段（`staleBytes` 命名 / 字段结构保持不变）
- 不引入 i18n 框架
- 不改 PreviewCard 自身的尺寸/aspect ratio/视觉
- 不改 SaveDisclaimer 内部的图标、边框、底色样式
- 不动 SaveActionButton（FAB）与底部 88dp 留白的数值
- 不改 Mockup 的 source-of-truth（`_4_导出页面/code.html`）

## Technical Notes

- 编辑器源 mockup 的导出顺序（`SaveDisclaimer` 原来位于底部）来自 `_4_导出页面/code.html` lines 210–215；本任务的"上移"是有意偏离 mockup 的产品决策，注释里点一句即可
- `preview_skeleton.dart` 的类级 doc-comment 记录了 Iteration 0/1/2 的设计演进 —— 只需替换文案字符串，不动决策叙事
- 底部 88dp spacer 的算式（`56dp FAB + 16dp endFloat margin + 16dp breathing room`）原本写在 disclaimer 上方注释里，移动后该注释应贴到底部 spacer 处
- 文案改动并非 breaking change：`PreviewLoading.staleBytes` 字段未动，外部 API 一致
