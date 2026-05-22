# ST2: 迁移 PreviewFullScreenDialog 到 extended_image 三件套

> **Parent**: `05-22-brainstorm-fullscreen-preview-extended-image`
> **Predecessor**: `05-22-extimage-dep-and-poc` (archived; 3/3 红旗 PASS, Approach A 推进)
> **Successor**: `05-22-migrate-thumbnail` (ST3), `05-22-rewrite-tests-and-adrs` (ST4)
> **入口契约**: 父 PRD `Implementation Plan` ST2 段 + `R3` / `R3-exception` / `Decision (ADR-lite)`

## Goal

把 `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart` (884 行)
**从自实现 `InteractiveViewer + PageView + _ImmersivePageScrollPhysics + 自实现
drag-to-dismiss` 切换到 `extended_image` 三件套**:

- 外层 `ExtendedImageSlidePage` 负责 drag-to-dismiss (100dp / 800dp/s / 1.0→0.4 opacity)
- 中层 `ExtendedImageGesturePageView.builder` 负责多图画廊 + 缩放↔切页协调
- 叶子 `ExtendedImage.memory(mode: ExtendedImageMode.gesture, inPageView: true,
  enableSlideOutPage: true)` 负责单页 pinch / pan / double-tap zoom

**对外 API 完全不变**: `PreviewFullScreenDialog({required List<Uint8List> bytes,
int initialIndex = 0})` 保留。调用方 (`PreviewThumbnail._openFullScreen`) **本任务
不修改** —— `showDialog` 改 `Navigator.push(PageRouteBuilder(opaque: false))` 是
ST3 的工作（thumbnail 任务同步迁移调用方）。

**预期产出**: 文件从 884 行 → ~350 行（删除 ~500 行自实现），`flutter analyze` 0 issue,
`dart format` 0 changed, `flutter test` 0 regression（**测试本任务不重写**，可能因
widget tree 改变而失败，ST4 会重写测试，本任务允许 `preview_full_screen_dialog_test.dart`
失败但不允许其它测试失败）。

## Requirements

* **R1**: `PreviewFullScreenDialog` 对外 API（`bytes` / `initialIndex` 参数语义）
  **保持不变**；调用方零修改是 ST3 的契约，**本任务不动 `preview_thumbnail.dart`**
  （即使现有调用方仍用 `showDialog` 调用，ST2 的新 dialog 也必须能在 `showDialog`
  里跑 —— 这是临时双轨期，会在 ST3 切到 `Navigator.push(PageRouteBuilder(opaque: false))`）。
* **R2**: 使用 PoC `lib/_poc/extended_image_poc.dart` 作为参考实现 —— 三件套的
  widget 树结构、`GestureConfig` 参数、`slideEndHandler` / `slidePageBackgroundHandler`
  闭包数学、`_PocScrollBehavior(dragDevices: 6 PointerDeviceKind)` 全部沿用。
* **R3** (**删除清单** — 必须全部删除，不允许残留)：
  - `_ImmersivePageScrollPhysics extends PageScrollPhysics` 类
  - `_PageGestureState { zoomed, atLeftEdge, atRightEdge }` 类
  - `_currentZoomed` ValueNotifier + 镜像 setState 字段 + 外层 GestureDetector
    callback null/non-null 切换逻辑
  - M-α 布局：`SizedBox.fromSize(size: renderedSize)` workaround + 关联的
    `applyBoxFit(BoxFit.contain, _imageSize, viewport).destination` 几何计算
  - `_imageDisplayRect(viewport)` / `_resolveImageSize()` / `_detachImageListener()`
    / `_imageSize` / `_lastViewport` / `_imageStream` / `_imageListener` 字段及方法
  - 外层 `GestureDetector(onVerticalDragStart/Update/End)` + `_dragSnapBack`
    `AnimationController` + `_dragOffsetY` / `_dragging` / `_snapBackStart` 字段
  - `_onMatrixChanged` / `_reportGestureState` / `_onZoomTick` / `_onSnapBackTick`
    / `_handleDoubleTapDown` / `_handleDoubleTap` / `_resolveFocalPoint` / `_zoomMatrix`
    （以及关联的 `TransformationController _tc`）

* **R4** (**保留清单** — 必须保留且行为不变)：
  - **Chrome auto-hide** 机制 (`_chromeVisible` / `_autoHideTimer` /
    `_scheduleAutoHide` / `_toggleChrome` / `kChromeAutoHideDelay = 3s` /
    `kChromeAnimationDuration = 200ms`)
  - **Chrome widget tree**: `AnimatedSlide` + `AnimatedOpacity` + `IgnorePointer` +
    transparent `AppBar` (single-image 标题 "预览" / 多图 "X / Y" 格式)
  - **Floating close button** (`_FloatingCloseButton`) 永远可点 + 视觉样式不变
    （`Material(color: Colors.black.withValues(alpha: 0.4)) > IconButton(Icons.close)`）
  - **`_ImmersiveScrollBehavior`** (6 PointerDeviceKind in dragDevices) — 包在
    `ExtendedImageGesturePageView` 外层（research 警告桌面 mouse drag 未官方测试，
    ST1 PoC 已确认此 ScrollBehavior 注入有效，保留）
  - **常量**: `kZoomAnimationDuration = 250ms` / `kDoubleTapZoomScale = 2.0` /
    `kMaxScale = 4.0` (作为 `GestureConfig.maxScale`) / `kDragToDismissDistance = 100`
    (作为 `slideEndHandler` 阈值) / `kDragToDismissFlingVelocity = 800`
  - **PageView page change 回调** 更新当前 index + 标题 "X / Y"
  - **`initialIndex` clamp** 到 `[0, bytes.length - 1]`
  - **`assert(bytes.length > 0)`** 入参校验

* **R5** (**新实现要求** — 三件套配置):
  - **`ExtendedImageSlidePage`** 配 `slideAxis: SlideAxis.vertical` +
    `slideType: SlideType.onlyImage` (drag 时图片向下移动，不带 AppBar)
  - `slideEndHandler: (Offset offset, {Size? pageSize, ScaleEndDetails? details}) =>`
    sliding 距离 `offset.dy.abs() >= kDragToDismissDistance` 或 fling velocity
    `details.velocity.pixelsPerSecond.dy.abs() >= kDragToDismissFlingVelocity`
    → return true (dismiss)，否则 false (spring back)
  - `slidePageBackgroundHandler: (Offset offset, Size pageSize) =>
    Colors.black.withValues(alpha: (1.0 - (offset.dy.abs() / kDragToDismissDistance)
    * 0.6).clamp(0.4, 1.0))` (与 ST1 PoC 行 156-163 完全一致)
  - **`ExtendedImageGesturePageView.builder`** 配 `ExtendedPageController(initialPage:
    _currentIndex)` + `onPageChanged: _onPageChanged` (更新 `_currentIndex` +
    setState 触发标题刷新)
  - **`ExtendedImage.memory(bytes[i], fit: BoxFit.contain, mode: ExtendedImageMode.gesture,
    enableSlideOutPage: true, initGestureConfigHandler: ...)`** 配
    `GestureConfig(inPageView: true, minScale: 1.0, maxScale: kMaxScale,
    animationMinScale: 0.8, animationMaxScale: kMaxScale * 1.1, initialAlignment:
    InitialAlignment.center)`
  - **双击 zoom**: 每页 `ExtendedImage` 持 caller-owned `AnimationController` +
    `onDoubleTap` 回调 → 反复调 `state.handleDoubleTap(scale, doubleTapPosition)`
    推进到 `kDoubleTapZoomScale = 2.0`（参考 PoC + research
    `pic_swiper.dart:457-490`）；letterbox 焦点降级**不再需要**（ext 内建）
  - **`_PocScrollBehavior` 改名为 `_ImmersiveScrollBehavior` 复用**（实际上是
    把现有的 `_ImmersiveScrollBehavior` 类**保留不动**，把 PoC 的 `_PocScrollBehavior`
    定义在 ST2 实现里删除）

* **R6** (**测试边界**):
  - 本任务**不重写** `preview_full_screen_dialog_test.dart` (ST4 的工作)
  - 现有测试可能因 widget tree 大改而**部分失败**，这是预期的
  - **其它测试** (`stitch_*` / `grid_*` / `preview_renderer_*` / `export_*`) **不允许
    出现 regression** —— 它们与本任务无关
  - 实施完成后跑一次 `flutter test test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart`，
    把失败列表记录到本任务 `failing-tests.md`，作为 ST4 重写测试的输入

* **R7** (**清理**):
  - 文件顶部 dartdoc 注释**全部重写** —— 现有注释指向 `_ImmersivePageScrollPhysics`
    / M-α 布局 / L-β / OverflowBox(topLeft) 等历史细节，必须**全部删除**，换成
    新三件套的简洁注释（不要保留误导性历史）
  - 删除 `import 'dart:async'` (如不再用 Timer 之外的 async 类型) — 实际上
    `_autoHideTimer` 还要保留所以仍需 import；判断每个 import 是否还需要
  - 删除 `import 'package:flutter/gestures.dart'` (PointerDeviceKind 仍需，保留)
  - 删除 ADR-0001 注脚等长篇 widget tree 解释注释

* **R8**: `lib/_poc/extended_image_poc.dart` + home_screen.dart 的 debug 入口 +
  TODO(ST4) 标记本任务**不动**（ST4 cleanup 的工作）；保留为 sub-agent 的参考样板。

## Acceptance Criteria

* [ ] `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
      重写完成 (~350 行，删除 ~500 行)
* [ ] 文件中 grep 不到 `_ImmersivePageScrollPhysics` / `_PageGestureState` /
      `_imageDisplayRect` / `_currentZoomed` / `_ImmersivePageScrollPhysics` /
      `applyBoxFit` / `SizedBox.fromSize` / `_dragSnapBack` 等被删除的符号
* [ ] 文件中 grep 得到 `ExtendedImageSlidePage` / `ExtendedImageGesturePageView` /
      `ExtendedImage.memory` / `GestureConfig` / `inPageView: true` /
      `enableSlideOutPage: true` / `slideEndHandler` / `slidePageBackgroundHandler`
* [ ] `_ImmersiveScrollBehavior` 类仍存在 + 仍包含 6 PointerDeviceKind
* [ ] `_FloatingCloseButton` 类仍存在 + 视觉样式未改
* [ ] `flutter analyze` 0 issue
* [ ] `dart format --set-exit-if-changed .` 0 file
* [ ] `flutter test test/features/export/` 中**非** `preview_full_screen_dialog_test.dart`
      的测试全部 PASS
* [ ] `failing-tests.md` 文件存在，记录 `preview_full_screen_dialog_test.dart`
      失败用例清单（供 ST4 重写时定位）
* [ ] PoC 文件 `lib/_poc/extended_image_poc.dart` 与 home_screen.dart 的 debug 入口
      均未被修改（ST4 cleanup 的范围）

## Definition of Done

* Lint / format / non-preview-dialog tests 全绿
* `failing-tests.md` 记录预期失败的测试用例
* 文件顶部新注释简洁、不留误导性历史
* `_ImmersiveScrollBehavior` + `_FloatingCloseButton` 保留
* `PreviewFullScreenDialog` 对外签名不变

## Out of Scope

* `preview_thumbnail.dart` 改动 (ST3)
* `preview_full_screen_dialog_test.dart` 重写 (ST4)
* `lib/_poc/` + home_screen.dart debug 入口的清理 (ST4)
* ADR-0001 / ADR-0002 编辑 (ST4)

## Technical Notes

### 参考实现（必读）

* PoC 三件套范例: `lib/_poc/extended_image_poc.dart` (364 行，由 ST1 实施 agent 编写，
  通过 ST1 check + 人工 PoC 验证)
* 现有自实现: `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
  (884 行，本任务要替换的目标)

### 关键源码定位

* `ExtendedImageGesturePageView.builder` API: 见
  `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/research/extended_image-gallery-api.md`
  第 1 节
* `GestureConfig(inPageView: true)` 必要性: 同上 "关键注意事项" 段
* `ExtendedImageSlidePage` + `slideEndHandler` + `slidePageBackgroundHandler`: 见
  `research/extended_image-gesture-and-slide.md`
* 双击 zoom 用 `state.handleDoubleTap`: 同上 + extended_image example
  `pic_swiper.dart:457-490` (本地拷贝在 `/tmp/extended_image_research/`)
* 桌面 mouse drag `ScrollBehavior` 注入: research `gallery-api.md` 第 3 节
  ("桌面鼠标拖动")

### 父 PRD 全文

`.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/prd.md` ——
Decision (ADR-lite) + R3-exception (5 条不可避免实现差异) + Risks (5 个 R-risk
条目) 是本任务的完整背景上下文。
