# ST4: 重写测试 + 双 ADR 更新 + cleanup (final subtask)

> **Parent**: `05-22-brainstorm-fullscreen-preview-extended-image`
> **Predecessors**: ST1 (PoC, archived) + ST2 (dialog migration, archived) +
> ST3 (thumbnail migration, archived)
> **Role**: 整个 extended_image 迁移的**收尾棒** —— 把临时性 / 历史性产物
> 全部归位，让仓库回到"干净 + 可维护"的状态。

## Goal

完成 extended_image 迁移的最后三件事，每件独立但同属"收尾"：

1. **测试重写**: `preview_full_screen_dialog_test.dart` 18 个 expected-failing
   测试 → 重写成针对 `ExtendedImage` / `ExtendedImageGesturePageView` /
   `ExtendedImageSlidePage` widget tree 的断言；保留 9 个 surviving；用例总数
   维持原 27 个左右（保持 5 个 group / ~20 个测试用例的等价覆盖）。
2. **ADR 双更新**: `docs/adr/0001-immersive-page-scroll-physics.md` 加
   "Status: Superseded by ADR-0002 (<today's date>)" 注脚；新写
   `docs/adr/0002-extended-image-fullscreen-preview.md` 完整覆盖父 PRD
   Decision (ADR-lite) 三段（Context / Decision / Consequences），且
   Consequences 段含 Post-ST2 Revision 作为一条 sub-bullet。
3. **PoC + Debug 入口 Cleanup**: 删除 `lib/_poc/extended_image_poc.dart` 文件 +
   `lib/features/home/presentation/screens/home_screen.dart` 中的 `kDebugMode`
   守卫 `Icons.science_outlined` IconButton（包括相关 import / TODO(ST4) 注释）。
   **保留** `.trellis/tasks/archive/2026-05/05-22-extimage-dep-and-poc/poc-report.md`
   不动（已 archived，作为 institutional 记录）。

## Requirements

### Section 1: 测试重写 (`preview_full_screen_dialog_test.dart`)

* **R1**: 完整重写 `test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart`，
  以 ST2 hand-off doc `.trellis/tasks/archive/2026-05/05-22-migrate-fullscreen-dialog/failing-tests.md`
  作为权威输入。每个原失败测试都按 hand-off 的 "Suggested rewrite" 路径处理。
* **R2** (**保留 9 个 surviving tests**):
  1. `tap on PreviewThumbnail opens the dialog`
  2. `close button title and tooltip render`
  3. `tapping the close button pops the dialog`
  4. `chrome (AppBar) is visible by default on open`
  5. `chrome auto-hides after 3 seconds`
  6. `floating close button stays interactive after chrome auto-hides`
  7. `AppBar leading slot is empty (no auto-injected back arrow)`
  8. `single-image title shows "预览"`
  9. `multi-image title shows "X / Y"`
  这 9 个测试在 ST2 后仍 PASS，ST4 **不应破坏**它们 —— 它们是 chrome /
  close button / 标题等"实现无关 / 行为契约"的断言。
* **R3** (**重写 A 类: 5 个 InteractiveViewer 属性断言**):
  - `dialog contains an InteractiveViewer` → 改为 `find.byType(ExtendedImage)`，
    通过 `tester.state<ExtendedImageGestureState>(...)` 读 `gestureDetails.gestureConfig`
    断言 `minScale == 1.0` / `maxScale == kMaxScale`
  - `InteractiveViewer.boundaryMargin is EdgeInsets.zero ...` → **删除**（M-α 不
    再适用，行为契约转移到 ext 内部 viewport-edge clamp）
  - `InteractiveViewer uses constrained:true + Center + SizedBox(renderedSize)
    ...` → **删除**（M-α / L-β / OverflowBox saga 全部废弃）
  - `after a double-tap zoom + reset, the image remains centred ...` → 重写为
    驱动两次双击，断言渲染图片 rect 居中（用 `tester.getRect(find.byType(ExtendedImage))`），
    保留 `runAsync(precacheImage)` 预热
  - `pan beyond image-pixel edge is clamped: dragging twice ...` → 重写为预 zoom +
    两次 drag 后断言 `gestureDetails.offset` 未越 ext 的 boundary；注释说明 ext
    的 clamp 是 viewport-edge 不是 image-pixel edge
* **R4** (**重写 B 类: 1 个 chrome-toggle 测试**):
  - `single tap toggles chrome and resets the timer` → 把
    `tester.tap(find.byType(InteractiveViewer))` 改为
    `tester.tap(find.byType(ExtendedImage))`（或合适的 widget tree 节点）。
    chrome 状态机本身未改动。
* **R5** (**重写 C 类: 4 个 gesture 测试**):
  - `minScale == 1.0 and panEnabled == false at identity` → minScale 部分通过
    `gestureConfig` 验证；`panEnabled == false at identity` 没有等价物，**替换**为
    "drag vertically while un-zoomed dismisses the dialog (drag-to-dismiss to
    SlidePage); pre-zoom, drag vertically, dialog stays"（即测试 ext 的
    auto-gating 行为）
  - `double-tap animates the controller up to ~2.0× scale` → 驱动双击 + 推进
    AnimationController，从 `tester.state<ExtendedImageGestureState>` 读
    `gestureDetails.totalScale`，断言 closes to `kDoubleTapZoomScale = 2.0`
  - `double-tap while zoomed resets the matrix to identity` → 预 zoom → 双击 →
    断言 `totalScale == 1.0`
  - `double-tap focal falls back to image centre when tap lands in letterbox`
    → **弱化或删除**（ext 内建 focal clamping；保留一个 smoke 版"double-tap
    in letterbox does not push image out of view"也可）
* **R6** (**重写 D 类: 5 个 PageView 测试**):
  - `multi-image dialog renders a PageView` → 替换 `find.byType(PageView)`
    为 `find.byType(ExtendedImageGesturePageView)`
  - `PageView uses immersive physics that is a PageScrollPhysics` → **删除**
    （physics ownership 迁到 ext 上游）
  - `swiping horizontally while un-zoomed advances to the next page` → fling
    target 改为 `find.byType(ExtendedImageGesturePageView)`
  - `vertical drag exceeding threshold pops the dialog` → drag target 改为
    `find.byType(ExtendedImage)`（threshold 由 `_slideEndHandler` 保证）
  - `vertical drag below threshold snaps back and keeps the dialog open` →
    同上；wait 时长按 `ExtendedImageSlidePage.resetPageDuration: 500ms` 调整
* **R7** (**重写 E 类: 3 个 ScrollConfiguration / mouse-drag 回归测试**):
  - `PageView is wrapped in a ScrollConfiguration whose dragDevices include
    mouse / trackpad` → 把 `find.ancestor(of: find.byType(PageView), matching:
    find.byType(ScrollConfiguration))` 中 `PageView` 改为
    `ExtendedImageGesturePageView`；断言 `dragDevices` 含 mouse + trackpad +
    touch + stylus 不变
  - `touch fling on PageView still advances pages (regression check that the
    custom ScrollConfiguration did not break the default touch path)` → fling
    target 改为 `find.byType(ExtendedImageGesturePageView)`
  - `single-finger pan after double-tap zoom moves the matrix (outer vertical
    -drag recognizer is not in the arena while zoomed)` → 改为：预 zoom + 单指
    pan → 断言 `gestureDetails.offset` 变化 + dialog 仍存在（ext 的 auto-gating
    取代了我们的 `_currentZoomed` 机制）
* **R8** (**ST2 hand-off doc 中"ST4 implementation notes"必读**):
  - `MemoryImage` decode 需用 `runAsync(precacheImage)` 预热 image stream
  - `ExtendedImageSlidePage.resetPageDuration: 500ms` (不是之前的 250ms)
  - `tester.state<ExtendedImageGestureState>` 访问路径（需通过
    `find.byType(ExtendedImage)` 找）
* **R9**: 测试最终结果 `flutter test test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart`
  必须 **全部 PASS**，无 FAIL 无 skip（除非有非常具体的 `skip:` reason）。

### Section 2: ADR 双更新

* **R10** (**ADR-0001**): 编辑
  `docs/adr/0001-immersive-page-scroll-physics.md` 在 frontmatter（line 1-5）
  把 `**Status**: Accepted` 改为 `**Status**: Superseded by ADR-0002 (2026-05-23)`，
  **不要**删除其它内容（保留作历史记录）。可以在文件末尾加一个简短的
  `## Superseded by ADR-0002` section 指向新 ADR。
* **R11** (**新写 ADR-0002**): 在 `docs/adr/` 下新建
  `0002-extended-image-fullscreen-preview.md`，结构遵循 ADR-0001 的格式
  （Date / Status / Context / Decision / Consequences / Alternatives / Validation）：
  - **Date**: 2026-05-23
  - **Status**: Accepted
  - **Context**: 摘抄父 PRD `Decision (ADR-lite)` 的 Context 段（"现有
    `_ImmersivePageScrollPhysics` 自实现的'缩放后边缘 bleed 切页'实际使用中
    不连贯..."）；引用 ADR-0001 被推翻的事实
  - **Decision**: 摘抄 + 整理父 PRD `Decision (ADR-lite)` 的 Decision 段
    （Approach A: 全面拥抱 extended_image: ^10.0.1 + 三件套 widget 组合 + 删除清单 +
    保留清单）
  - **Consequences**:
    - **Positive**: 自维护 ~500 行 → ~100 行（迁移净减少）；缩放↔切页协调彻底
      交给上游；letterbox 双击 fallback 问题消失；将来 Hero / cropping / 滤镜
      路径最短
    - **Negative**: spring-back 曲线 `easeOutCubic` → ext 内置 linear（接受降级）；
      绑定 extended_image 维护节奏（维护者最近 13 个月不主推，README 加
      fork-preparedness 注脚）；命中 #736 / #761 风险（已 ST1 PoC 验证 PASS，
      mitigation 留在 issue tracker）
    - **Post-ST2 Revision sub-bullet** (CRITICAL — 须明确写入): 调用方
      `_openFullScreen` 保留 `showDialog<void>(Dialog.fullscreen(transparent))`
      不迁移到 `Navigator.push(PageRouteBuilder(opaque: false))`。ST2 完成后
      实际手测发现 showDialog 体验更丝滑，反向了 brainstorm 阶段的 sub-decision。
      参见父 PRD 的 `Post-ST2 Revision (2026-05-23)` 节。教训：**主决策与
      sub-decision 分层管理**让反向决策成本可控。
  - **Alternatives considered**:
    - **Approach B (rejected)**: 仅画廊 ext + 保留自实现 drag-to-dismiss
    - **Approach C (rejected)**: PoC 先行决策路径（实际是 ST1 路径，最终采纳 A）
    - **photo_view_gallery (rejected)**: 仍未被采用（ADR-0001 已考虑过，本任务
      不重新评估）
  - **Validation criteria**: 9 surviving + 18 重写后的测试全 PASS；flutter
    analyze 0 issues；3/3 PoC 红旗 PASS；维护信号长期跟踪
  - **References**: 父 PRD path / ST1-4 子任务 archive 路径 / GitHub issue
    #736 / #761 / #686 / #648 / #752 链接 / extended_image pub.dev / repo URL

### Section 3: PoC + Debug 入口 Cleanup

* **R12**: **删除** `lib/_poc/extended_image_poc.dart` 整个文件
* **R13**: **从** `lib/features/home/presentation/screens/home_screen.dart` 移除:
  - `import '../../../../_poc/extended_image_poc.dart';` (如有)
  - `import 'package:flutter/foundation.dart';` (仅当原 home_screen 没用
    `kDebugMode` 之外的 foundation 类型，且本任务后不再使用)
  - `if (kDebugMode)` 守卫的 `Icons.science_outlined` IconButton 整个块
  - 所有 `TODO(ST4): remove after migration` 注释
* **R14**: **保留**（不删除）：
  - `.trellis/tasks/archive/2026-05/05-22-extimage-dep-and-poc/poc-report.md`
    （ST1 archive 中的 institutional 记录）
  - `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
    内部任何引用（应该不存在 PoC 引用，但 grep 确认）

### Section 4: 全项目验证

* **R15** (**全套绿灯门控**):
  - `flutter analyze` → 0 issues
  - `dart format --set-exit-if-changed .` → 0 files changed
  - `flutter test` → 整套全 PASS（含本任务重写后的 preview_full_screen_dialog_test.dart）
  - `flutter pub deps --no-dev | grep extended_image` 仍返回 10.0.1 链
* **R16** (**Cleanup grep 验证**):
  - `grep -r "lib/_poc" lib/ test/ 2>/dev/null` → 0 hits（PoC 引用全部清除）
  - `grep -r "TODO(ST4)" lib/ test/ 2>/dev/null` → 0 hits（清理标记全部消除）
  - `find lib/_poc -type f 2>/dev/null` → 0 results（目录已删）
* **R17** (**ADR 验证**):
  - `head -5 docs/adr/0001-immersive-page-scroll-physics.md` 含
    `Superseded by ADR-0002`
  - `test -f docs/adr/0002-extended-image-fullscreen-preview.md` 返回 true
  - `grep -c "Post-ST2 Revision\|showDialog.*仍.*使用\|保留.*showDialog" docs/adr/0002-extended-image-fullscreen-preview.md`
    ≥ 1（验证 reverse decision sub-bullet 已写入）

## Acceptance Criteria

* [ ] `preview_full_screen_dialog_test.dart` 重写后全 PASS（无 expected-FAIL）
* [ ] 9 个 surviving tests 仍 PASS（不被破坏）
* [ ] 测试用例总数约 20-27 个（保持等价覆盖；R3/R5 删除的 4 个测试可减总数）
* [ ] `docs/adr/0001-immersive-page-scroll-physics.md` frontmatter
      `Status: Superseded by ADR-0002 (2026-05-23)`
* [ ] `docs/adr/0002-extended-image-fullscreen-preview.md` 新建，含 Context /
      Decision / Consequences（含 Post-ST2 Revision sub-bullet）/ Alternatives /
      Validation / References 段
* [ ] `lib/_poc/extended_image_poc.dart` 已删除
* [ ] `lib/features/home/presentation/screens/home_screen.dart` 中
      `Icons.science_outlined` IconButton + `if (kDebugMode)` 守卫 + `TODO(ST4)` 注释
      + 相关 imports 全部清除
* [ ] `flutter analyze` 0 issue
* [ ] `dart format --set-exit-if-changed .` 0 file
* [ ] `flutter test` 整套全 PASS
* [ ] `grep -r "TODO(ST4)" lib/ test/` 0 hits

## Definition of Done

* Lint / format / 全套测试绿
* ADR-0001 加 Superseded 注脚 + 保留原文
* ADR-0002 新建覆盖完整三段 + Post-ST2 Revision sub-bullet
* PoC + debug 入口 cleanup 完成
* 父 brainstorm 任务进度变 [4/4 done]，可以 archive

## Out of Scope

* `extended_image` 包版本升级 / fork（如未来 SDK bump 需要 fork 是独立任务）
* 引入 Hero 动画 / cropping / 滤镜等扩展能力（独立任务）
* `preview_thumbnail.dart` 二次改动（ST3 已完成）
* `preview_full_screen_dialog.dart` 二次改动（ST2 已完成）
* 其它 grid / stitch / editor 场景的图片显示迁移（父 PRD 已明确不在范围）
* `pubspec.yaml` 改动（ST1 已完成 + ST4 不动 deps）

## Technical Notes

### 关键路径

* **ST2 hand-off doc**:
  `.trellis/tasks/archive/2026-05/05-22-migrate-fullscreen-dialog/failing-tests.md`
  —— 18 个失败测试 A-E 5 类 + 9 个 surviving + ST4 implementation notes
* **父 PRD**:
  `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/prd.md`
  —— Decision (ADR-lite) + Risks + Post-ST2 Revision 是 ADR-0002 的素材
* **新规约 spec**:
  `.trellis/spec/frontend/component-guidelines.md`
  → "Pattern + Gotcha: extended_image 三件套多图沉浸式画廊" 段（ST2 沉淀）
  → "PoC gate for risky third-party packages" Convention（ST1 沉淀）
* **ADR-0001 原文**: `docs/adr/0001-immersive-page-scroll-physics.md`
* **PoC 文件 + 报告**:
  - 删除目标: `lib/_poc/extended_image_poc.dart` (364 行)
  - 保留: `.trellis/tasks/archive/2026-05/05-22-extimage-dep-and-poc/poc-report.md`
* **Debug 入口**: `lib/features/home/presentation/screens/home_screen.dart`
  - 寻找 `kDebugMode` + `Icons.science_outlined` + `TODO(ST4)` 的相关块

### ExtendedImageGestureState 测试访问模式

```dart
// 找 ExtendedImage widget
final imageFinder = find.byType(ExtendedImage);

// 拿 State —— 需要等 ImageStream 解析完
await tester.runAsync(() async {
  await precacheImage(MemoryImage(bytes), tester.element(imageFinder));
});
await tester.pumpAndSettle();

// 读 gestureDetails
final gestureState = tester.state(imageFinder) as ExtendedImageGestureState;
expect(gestureState.gestureDetails?.totalScale, closeTo(2.0, 0.01));
expect(gestureState.gestureDetails?.offset, ...);
```

### 三件套 widget tree 测试 finder

```
ExtendedImageSlidePage              // outer (drag-to-dismiss)
  └ ScrollConfiguration             // dragDevices: 6 PointerDeviceKind
      └ ExtendedImageGesturePageView  // (替代 PageView)
          └ ExtendedImage           // leaf (mode: gesture)
```

各 finder:
- `find.byType(ExtendedImageSlidePage)` — outer
- `find.ancestor(of: find.byType(ExtendedImageGesturePageView), matching:
  find.byType(ScrollConfiguration))` — 测试 dragDevices
- `find.byType(ExtendedImageGesturePageView)` — fling / drag target
- `find.byType(ExtendedImage)` — leaf access for gestureState

### ADR-0002 写作素材

来自父 PRD 现成的段落（直接复用即可）:
- Context: 父 PRD `## Decision (ADR-lite)` 的 **Context** 段
- Decision: 父 PRD `## Decision (ADR-lite)` 的 **Decision** 段（删除清单 +
  保留清单 + ADR-0001 Superseded 表述）
- Consequences Positive / Negative / Neutral: 父 PRD `## Decision (ADR-lite)`
  的 **Consequences** 段
- Consequences sub-bullet (Post-ST2 Revision): 父 PRD `## Post-ST2 Revision
  (2026-05-23)` 整节（提炼成 1 个 sub-bullet + 链回原节）
- Alternatives: 父 PRD `## Approaches (proposed)` 三段（A/B/C）
- References: 父 PRD `## Technical Notes` 中的"关键源码定位" + GitHub issue 链接
