# Journal - Reborn (Part 2)

> Continuation from `journal-1.md` (archived at ~2000 lines)
> Started: 2026-05-23

---



## Session 60: ST4 final + parent close: extended_image migration arc complete

**Date**: 2026-05-23
**Task**: ST4 final + parent close: extended_image migration arc complete
**Branch**: `main`

### Summary

Final subtask of 05-22-brainstorm-fullscreen-preview-extended-image. Three intertwined deliverables in one cohesive cleanup commit (43dd483): (1) Rewrote preview_full_screen_dialog_test.dart from 776→843 lines, 27→25 tests all PASS — implemented failing-tests.md hand-off spec verbatim (16 rewrites + 4 deletions); 9 surviving tests preserved byte-identical; 3 new helpers (_gestureState pins ExtendedImageGesture not ExtendedImage; _primeImageDecode runs precacheImage to swap in real ExtendedImageGesture before ImageStream resolves; _dragFromBy 16-step controlled drag mirrors real user 60fps for ScaleGestureRecognizer arena resolution) inline documented. (2) ADR double update — ADR-0001 frontmatter Superseded by [ADR-0002] (2026-05-23) + new section at file end (original preserved); ADR-0002 new (258 lines) with Context / Decision / Consequences containing Post-ST2 Revision sub-bullet recording 'keep showDialog<void> not migrate to PageRouteBuilder(opaque:false) — main decision held, sub-decision reversed via layered decision-making' / Alternatives (B/C/photo_view_gallery) / Validation / References. (3) PoC cleanup — deleted lib/_poc/extended_image_poc.dart (364 lines, dir gone); removed kDebugMode-gated debug entry from home_screen.dart (foundation.dart import only used for kDebugMode, also removed); preserved archived poc-report.md + failing-tests.md as institutional records. flutter analyze 0 / dart format 0 changed / flutter test 546 PASS / 3 skip benchmark / 0 FAIL. Net stats: 7 files / +1059 / -800 — healthy cleanup. Archived ST4 + parent brainstorm together (parent [4/4 done] after ST4 archive). Closes the entire 4-subtask extended_image migration arc started 2026-05-22. ADR-0001 (Accepted → Superseded by ADR-0002) preserved as historical record.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `43dd483` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 61: Export page polish — skeleton copy & disclaimer position

**Date**: 2026-05-23
**Task**: Export page polish — skeleton copy & disclaimer position
**Branch**: `main`

### Summary

Two导出页 UX 微调：(1) PreviewSkeleton loading 文案 '加载中.../刷新中...' → '生成中.../重新生成中...'，与后端'合成新图'的实际语义对齐；(2) SaveDisclaimer 从 _ExportBody 末尾移到首位 (PreviewCard 之上)，让本地隐私承诺先于预览图被读到。保留底部 88dp FAB clearance、未动 PreviewLoading.staleBytes 字段 / SaveDisclaimer / PreviewCard 自身视觉。trellis-implement → trellis-check 全绿 (546 tests pass, analyze clean)。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `b846c3f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 62: 长图拼接 compact 画布主导重设计

**Date**: 2026-05-24
**Task**: 长图拼接 compact 画布主导重设计
**Branch**: `main`

### Summary

重设计 compact 屏宽（<600 dp）下的长图拼接编辑器：用「持久编辑器底栏（3 chip：+ 添加 / 🖼 N/20 / ⚙ 参数）+ 触发式 modal sheets」替代原「strip + canvas + sheet 三段 Column」，画布占屏从 ~29% 提升到 ~72%。导出 CTA 保留在 AppBar action（D-4 反转，对齐 medium 行为）。medium / expanded / large 完全保持现状。新增 5 个 widget（StitchEditorBottomBar / StitchAddActionSheet / StitchImageSheet / StitchParamsSheet / StitchSheetGripHandle）+ 4 个 test 文件，复用 StitchVerticalImageList / StitchControlsPanel 零代码重复。Spec 更新 responsive-layout.md 新增「Mobile-first canvas-dominant editor」pattern + 修订 stitch_editor 行 + 补充 DraggableScrollableSheet 边界（persistent sheet 不要用 / trigger-fired modal 推荐用）。Tooltip 文案 retune「导出每张子图」→「导出拼图」。最终 565 测试全过、analyze clean、format clean。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8d4543b` | (see git log) |
| `c956cd8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 63: JPG 质量滑块：拖动中不再触发预览重生成，改为 onChangeEnd 提交

**Date**: 2026-05-24
**Task**: JPG 质量滑块：拖动中不再触发预览重生成，改为 onChangeEnd 提交
**Branch**: `main`

### Summary

导出页面 _QualitySlider 从 StatelessWidget 改造为 StatefulWidget：本地 _draftValue 缓冲拖动中值，Slider.onChanged 只 setState 草稿（数字 + 拇指实时跟随），Slider.onChangeEnd 才向上提交 setQuality。didUpdateWidget 在外部 value 变化时同步草稿，覆盖 PNG→JPG 切换与父 rebuild 场景。PreviewController / ExportController / ExportState 全部不动。新增 3 个 widget 测试覆盖 R1/R2/拖回原值短路。在 .trellis/spec/frontend/component-guidelines.md 沉淀新 convention 'Expensive-preview sliders submit on onChangeEnd, not onChanged' 含 What/Why/Example/When to apply/Required tests 五段，约束未来同类滑块。质量门：flutter analyze 0 issues、dart format 0 changes、目标测试 9/9、全套 567/567 通过。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `bff9dd5` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 64: 修复 stitch/grid editor AppBar 返回按钮的 go_router pop 崩溃

**Date**: 2026-05-24
**Task**: 修复 stitch/grid editor AppBar 返回按钮的 go_router pop 崩溃
**Branch**: `main`

### Summary

删除 StitchEditorScreen / GridEditorScreen AppBar 的 leading: Navigator.canPop(context) ? IconButton : null 整段（former line 99-106 / 174-181）。原代码企图在 StatefulShellRoute branch root 上条件渲染返回按钮，但 canPop 在某些瞬态（从 /export 返回 / 热重载）短暂返回 true，按钮渲染并被点击时 GoRouter currentConfiguration 已空，触发 _handlePopPageWithRouteMatch 的 isNotEmpty 断言崩溃。修复彻底对齐 spec/frontend/component-guidelines.md 的 'a tab root is not back-able; use the bottom nav instead' 契约——branch root 不应该有返回按钮，由 AppShell.PopScope 统一处理 Android back / iOS edge-swipe 回 home tab。新增 4 个 widget 测试（每 editor 2 个），用 triple-finder 覆盖（AppBar.leading == null + Icons.arrow_back not found + Tooltip 返回 not found）锁定契约。质量门：flutter analyze 0 issues、dart format 0 changes、571/571 全套测试通过（含 4 新增）、AppShell 5/5 PopScope 测试不退化。0 findings during trellis-check audit.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1017715` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
