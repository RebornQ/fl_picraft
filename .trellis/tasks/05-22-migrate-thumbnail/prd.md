# ST3: 迁移 PreviewThumbnail 到 ExtendedImage.memory

> **Parent**: `05-22-brainstorm-fullscreen-preview-extended-image`
> **Predecessor**: ST1 (archived, 3/3 红旗 PASS) + ST2 (archived, 884→429 行三件套迁移)
> **Successor**: ST4 (`rewrite-tests-and-adrs`)
> **Scope (Post-ST2 Revision 2026-05-23)**: **已收窄** —— 仅图片显示 widget 替换，
> **不动** `_openFullScreen` 方法体（继续用 `showDialog<void>(...)`）。

## Goal

把 `lib/features/export/presentation/widgets/preview_thumbnail.dart` 里的
`Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)` 替换为
`ExtendedImage.memory(bytes, fit: BoxFit.contain, mode: ExtendedImageMode.none,
gaplessPlayback: true)`，作为整体迁移到 `extended_image` 栈的最后一块拼图。

**为什么是 `ExtendedImageMode.none`**: 缩略图是被动展示，**不需要**手势（pinch /
pan / double-tap），点击进入全屏才用三件套。`mode: none` 让 ExtendedImage 只承担
"更现代的 ImageProvider 处理 + 与未来 Hero 动画 / loadStateChanged 自定义占位的
扩展点"，零运行时手势开销。

**显式不做**（Post-ST2 Revision 2026-05-23 反向决策）:
- **不**动 `_openFullScreen` 方法体；继续用 `showDialog<void>(barrierDismissible:
  false, builder: (_) => PreviewFullScreenDialog(...))` 不变
- **不**迁移到 `Navigator.of(context).push(PageRouteBuilder<void>(opaque: false,
  ...))`（ST2 实测 showDialog 体验更丝滑）

## Requirements

* **R1**: 把 `Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)`
  （`preview_thumbnail.dart` build 方法内层）换成 `ExtendedImage.memory(bytes,
  fit: BoxFit.contain, mode: ExtendedImageMode.none, gaplessPlayback: true)`。
  保留 `BoxFit.contain` + `gaplessPlayback: true` 行为不变。
* **R2**: **不**修改 `_openFullScreen` 方法（继续 `showDialog<void>(...)`）。
* **R3**: 对外 API（`PreviewThumbnail({required bytes, semanticLabel, allBytes,
  initialIndex})`）**不变**。调用方（grid / stitch 等）零修改。
* **R4**: 包裹结构保持：`Semantics > InkWell > ClipRRect > ColoredBox >
  <ExtendedImage>` —— 仅最内层 widget 类型变化，外层包裹与样式（`BorderRadius.circular(8)`
  / `colorScheme.surfaceContainerHighest` 背景色）byte-for-byte 一致。
* **R5**: `import` 语句：删除 `Image.memory` 不再需要的额外 imports（如有）；
  新增 `import 'package:extended_image/extended_image.dart';`。
* **R6**: 文件 dartdoc 顶部注释更新 — "Image rendered with `BoxFit.contain`" →
  "Image rendered via `ExtendedImage.memory(mode: none)` with `BoxFit.contain`"
  （或类似简洁修订），不夸张展开。
* **R7**: `flutter analyze` 0 issue, `dart format --set-exit-if-changed .` 0 file,
  `flutter test test/features/` 全绿（含 `preview_full_screen_dialog_test.dart`
  的 9 surviving PASS — ST3 改动不应破坏它们；18 FAIL 仍然 expected, ST4 工作）。

## Acceptance Criteria

* [ ] `grep "Image.memory" lib/features/export/presentation/widgets/preview_thumbnail.dart`
      → 0 hits（替换完成）
* [ ] `grep "ExtendedImage.memory" lib/features/export/presentation/widgets/preview_thumbnail.dart`
      → 1 hit
* [ ] `grep "ExtendedImageMode.none" lib/features/export/presentation/widgets/preview_thumbnail.dart`
      → 1 hit
* [ ] `grep "showDialog" lib/features/export/presentation/widgets/preview_thumbnail.dart`
      → 仍有 1 hit（`_openFullScreen` 内部，**保留不动**）
* [ ] `grep "PageRouteBuilder" lib/features/export/presentation/widgets/preview_thumbnail.dart`
      → 0 hits（**没有**引入新路由 API）
* [ ] `import 'package:extended_image/extended_image.dart';` 已加入
* [ ] `gaplessPlayback: true` 保留
* [ ] `BoxFit.contain` 保留
* [ ] `flutter analyze` 0 issue
* [ ] `dart format --set-exit-if-changed .` 0 file
* [ ] `flutter test test/features/` 整体绿，特别是 9 个 surviving
      `preview_full_screen_dialog_test.dart` 测试不被破坏

## Definition of Done

* Lint / format / 全部非 dialog 测试绿
* `preview_full_screen_dialog_test.dart` 9 surviving 仍 PASS（18 FAIL 仍 expected）
* `PreviewThumbnail` 对外 API 不变（grid / stitch 零修改）
* PoC `lib/_poc/extended_image_poc.dart` 与 home_screen.dart debug 入口仍**保留**
  （ST4 cleanup 范围）

## Out of Scope

* `_openFullScreen` 方法体 / `showDialog` 调用方式（Post-ST2 Revision 明确保留）
* `preview_full_screen_dialog.dart` 二次改动（ST2 已完成）
* `preview_full_screen_dialog_test.dart` 重写（ST4）
* `lib/_poc/` cleanup（ST4）
* home_screen.dart debug 入口 cleanup（ST4）
* ADR-0001 / ADR-0002 编辑（ST4）

## Technical Notes

* 当前实现路径: `lib/features/export/presentation/widgets/preview_thumbnail.dart`
  （87 行，结构很轻）
* 父 PRD: `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/prd.md`
  （特别是 R4 + Post-ST2 Revision 节）
* 调用方位置（仅用作零修改回归确认，**不修改**）:
  - `lib/features/grid/...` / `lib/features/long_stitch/...` 各种网格/拼图预览卡片
  - 全文 grep `PreviewThumbnail(` 找所有调用方
* `ExtendedImage.memory` API 接受 `gaplessPlayback` 参数（与 `Image.memory` 兼容）
* 参考: ST2 重写后的 `preview_full_screen_dialog.dart` 内部使用 ExtendedImage 的写法
* 预估 diff: ~5-10 行（最内层 widget 替换 + import + 注释微调）
