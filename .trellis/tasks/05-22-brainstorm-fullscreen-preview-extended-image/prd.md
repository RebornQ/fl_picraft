# brainstorm: 全屏预览改用 extended_image

> **状态**: brainstorm 中（草稿） — 待研究 + 用户确认后转 Phase 2。
> **入参**: 导出页面全屏预览改用第三方包 `extended_image`（<https://pub.dev/packages/extended_image>）

## Goal

把 `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
里的全屏预览实现，从**自实现的 InteractiveViewer + PageView + 自定义 ScrollPhysics**
切换到**第三方包 `extended_image`** 提供的 `ExtendedImage.memory(mode: gesture)`
+ `ExtendedImageGesturePageView.builder` 组合，**保留**全部既有 UX
（chrome 自动隐藏、双击缩放、缩放到边缘切页、drag-to-dismiss）。

**Why（为什么现在换）**: ADR-0001（2026-05-22）当时明确"为了一个页面不引入第三方依赖"
而选择自实现 `_ImmersivePageScrollPhysics`。本次任务**推翻该决策**，动机为
**当前自实现有具体 bug**: 缩放后边缘切页不连贯（`_ImmersivePageScrollPhysics`
的 `{atLeftEdge, atRightEdge}` 触底判定 + tolerance 在某些手势序列下漏判 / 误判），
加上其它体验问题。第三方包 `extended_image` 的 `ExtendedImageGesturePageView`
**原生**实现该行为（图片端 `movePage()` 判定 + PV 端 `canScrollPage` 反向闸门，
源码已通过 research 子 agent 核实），把"缩放↔切页"协调逻辑彻底交给上游维护。

## What I already know

### 现有实现脉络（`preview_full_screen_dialog.dart` 884 行）

* **手势栈分层**:
  * 外层 `GestureDetector(onVerticalDrag*)`: drag-to-dismiss（仅 unzoomed 时挂载 callback）
  * 中层 `PageView.builder` + 自定义 `_ImmersivePageScrollPhysics`: 缩放到边缘 → bleed 切页
  * 内层 `InteractiveViewer`: pinch / pan / double-tap zoom
* **关键状态机**:
  * `_PageGestureState { zoomed, atLeftEdge, atRightEdge }` 由当前页通过
    `ValueNotifier` 上报给 dialog，physics 直接读取
  * `_currentZoomed` 镜像驱动 setState，控制外层垂直拖动 callback **是否挂载**
    （null 时 recognizer 不进竞技场，避免与 IV 的单指 pan 冲突）
* **布局规约（M-α）**:
  * `InteractiveViewer(constrained: true /* default */, boundaryMargin: zero)`
  * 子节点 `Center > SizedBox.fromSize(size: renderedSize) > Image(fit: BoxFit.fill)`
  * `renderedSize = applyBoxFit(BoxFit.contain, _imageSize, viewport).destination`
  * 之所以走 M-α 不走 L-β（`constrained: false`），是因为 Flutter
    `interactive_viewer.dart:1123-1141` 把 `constrained: false` 路径硬编码到
    `OverflowBox(alignment: topLeft)`，无 API 可改 centring
* **多图画廊切页**:
  * 缩放 = 1 → physics 走默认 `PageScrollPhysics`（自由切页）
  * 缩放 > 1 且未触底 → physics 拒绝 user offset（IV 接管 pan）
  * 缩放 > 1 + 触底 + 拖动方向"向外" → physics 接收剩余 delta，平滑过渡切页
  * 触底判定: `tx <= -maxTx + 0.5` / `tx >= maxTx - 0.5`，其中
    `maxTx = (renderedW * scale - renderedW) / 2`
* **桌面端 mouse drag 支持**: 自定义 `_ImmersiveScrollBehavior` 把所有 6 种
  `PointerDeviceKind` 都加进 `dragDevices`
* **chrome 自动隐藏**: 3s 计时器；任何 tap 重置；`AnimatedOpacity` + `AnimatedSlide`
  + `IgnorePointer(!visible)` 避免透明区拦截事件
* **drag-to-dismiss**: 100 dp 阈值 / 800 dp/s fling；下拉过程中背景 opacity 线性
  从 1.0 → 0.4；未达阈值 spring back（250ms easeOutCubic）
* **letterbox 双击降级**: 双击点落在 `BoxFit.contain` 矩形外 → 焦点 fallback
  到图片中心，避免放大后跑出视口

### 现有测试覆盖（`test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart` 783 行）

5 个 group / ~20 个测试用例:
1. `PreviewFullScreenDialog` 基础：tap thumbnail → 打开 dialog、IV 参数、`boundaryMargin: zero`、M-α 子树结构、双击 zoom + 复位后图片仍居中、pan 边界 clamp、关闭按钮
2. chrome（Step 2）：默认可见、3s 自动隐藏、tap 切换 + 重置 timer、隐藏后关闭按钮仍可点、AppBar.leading == null
3. 手势（Step 3）：minScale=1.0 panEnabled=false、双击 → 2× + panEnabled=true、二次双击复位、letterbox 双击降级到中心
4. 多图 / drag-to-dismiss（Step 4）：单图标题"预览"、多图 "X / Y"、PageView 存在、自定义 physics 是 `PageScrollPhysics` 子类、横向 fling 切页、垂直拖 200dp pop、垂直拖 60dp snap back
5. 回归（桌面 mouse + zoomed pan）：mouse / trackpad 在 dragDevices、touch fling 仍切页、zoomed 单指 pan 改变 IV 矩阵且不触发 dismiss

### 项目约束

* `pubspec.yaml`: Riverpod 锁定 2.x；`flutter_lints` 6.x；Flutter SDK ^3.10.8
* `.trellis/spec/frontend/dependencies-and-platforms.md`: 新增依赖前必须
  `flutter pub deps | grep <package>` 验证锁图兼容（避免 SAT 冲突）
* `.trellis/spec/frontend/component-guidelines.md`: 注释提到的"桌面端 PageView 鼠标
  拖动 gotcha" — extended_image 替代实现也必须确认该问题
* ADR-0001 状态 = Accepted；推翻它需在新 PRD / ADR-lite 写清"上次决策的前提
  发生了什么变化"（reverse decision pattern）

### `extended_image` 已知概览（待 research 子 agent 详细确认）

* `ExtendedImage.memory(bytes, mode: ExtendedImageMode.gesture)` — 单图 + 内置手势栈
* `initGestureConfigHandler: (state) => GestureConfig(minScale, maxScale, ...)` —
  双击缩放、惯性、边界 clamp 全部内置
* `ExtendedImageGesturePageView.builder` — 专用画廊容器，**内置**缩放到边缘 →
  切页的语义（替代我们的 `_ImmersivePageScrollPhysics`）
* `SlidePageRoute<T>` + `enableSlideOutPage: true` — 内置 drag-to-dismiss
  （含背景 opacity 联动）
* `loadStateChanged` 回调可自定义 LoadingState / FailedState

## Assumptions (temporary)

* **A1**: ~~用户希望保留当前所有 UX~~ — **已用户确认**（Q1）: 推翻动机是当前
  实现的"缩放后边缘切页不连贯"bug + 其它体验问题。换 extended_image 的目的是
  把"缩放↔切页"协调与 drag-to-dismiss 等手势复杂度交给上游维护。
* **A2**: `extended_image` 版本 = **`^10.0.1`**（research 已确认锁图兼容，无 SAT 冲突）。
* **A3**: ~~替换范围仅 fullscreen~~ — **已用户确认**（Q2）: 范围 = **全屏预览
  + 缩略图 (`PreviewThumbnail`)**。grid / stitch 预览画布 / editor 等其它场景
  **不**纳入本次。
* **A4**: ~~测试需要重写~~ — **已用户确认**（Q3）: 重写既有 783 行测试，**保持
  覆盖度**（黑盒 + 关键 widget tree 节点断言均保留，按 ExtendedImage /
  ExtendedImageGesturePageView 的 API 重新表达）。
* **A5**: 不连带 ADR-0001 直接废弃；以新 ADR-lite 形式记录"推翻动机 + 新选择
  的代价收益"，老 ADR 仍保留作历史 + 加 "Superseded by ..." 注脚。

## Open Questions (Blocking / Preference only)

* ~~Q1 (Blocking): 切换动机~~ → **已答**: 当前实现"缩放后边缘切页不连贯" + 其它体验问题
* ~~Q2 (Preference): 替换范围~~ → **已答**: 全屏预览 + 缩略图
* ~~Q3 (Preference): 测试策略~~ → **已答**: 重写后保持覆盖度

待问（最终收敛）：
* **Q6 (Preference) - 关键**: drag-to-dismiss spring-back 曲线降级是否接受？
  现有 `easeOutCubic 250ms` → ext 固定线性。
* **Q7 (Preference)**: PoC 风险验收策略 — 是否在实现前先做最小 PoC（仅 dialog 单元验证
  #736 drag-to-dismiss + 画廊脆弱问题、#761 iOS .memory 兼容、桌面 mouse drag
  翻页 3 个红旗），通过后再正式重写？

## Approaches (proposed)

基于 3 个 research 子 agent 的发现，给出 3 个候选实现路径：

### Approach A: 全面拥抱 extended_image (Recommended)

**How**:
- `PreviewFullScreenDialog` 的 body 完全用 `ExtendedImageSlidePage` (root)
  + `ExtendedImageGesturePageView.builder` (中层) + `ExtendedImage.memory(...,
  mode: gesture)` (叶子)
- drag-to-dismiss 用 `slideEndHandler` (100dp / 800dp/s 阈值) +
  `slidePageBackgroundHandler` (1.0→0.4 opacity)
- 双击 zoom 用 caller-owned `AnimationController` + `state.handleDoubleTap()`
- 调用方从 `showDialog` 迁移到 `PageRouteBuilder(opaque: false, ...)`
- 保留外层 `_ImmersiveScrollBehavior` 注入 dragDevices（桌面保险）
- 删除 `_PageGestureState` / `_ImmersivePageScrollPhysics` / `_currentZoomed` /
  M-α `SizedBox(renderedSize)` / `_imageDisplayRect` / `_resolveImageSize` /
  外层垂直 GestureDetector 全部自实现

**Pros**:
- 实现最简化，自维护代码减少 ~500 行（884 → ~350 行预估）
- 缩放↔切页协调彻底交给上游（解决用户 #1 痛点）
- letterbox 双击降级问题彻底消失（焦点 clamping 内建）
- 未来扩展 Hero / cropping / 滤镜路径最短

**Cons**:
- spring-back 曲线从 `easeOutCubic` 退化为 linear（细微视觉差异）
- 命中 #736 风险面最大（drag-to-dismiss + PageView 组合）→ PoC 必须先验证
- ADR-0001 完全推翻，需新 ADR-lite

### Approach B: 仅画廊用 extended_image，drag-to-dismiss 保留自实现

**How**:
- 画廊层用 `ExtendedImageGesturePageView.builder` + `ExtendedImage(mode: gesture,
  inPageView: true)`
- **保留**外层 `Dialog.fullscreen` + 外层 `GestureDetector(onVerticalDrag*)` +
  自实现 100dp 阈值 + `easeOutCubic` 回弹（**不**用 `ExtendedImageSlidePage`）
- 双击 zoom 同样需要 `AnimationController + handleDoubleTap`
- `_currentZoomed` 机制**保留**（控制外层垂直手势 callback 是否挂载，避免与
  ext 内部的单指 pan 冲突 — 因为这次外层是我们的 GestureDetector，不是 ext 的
  SlidePage，ext 内部那套自动屏蔽不会生效）

**Pros**:
- 解决用户 #1 痛点（缩放↔切页）
- 完全规避 #736 风险（drag-to-dismiss + PageView 组合 fragile 问题）
- spring-back 曲线 `easeOutCubic` 保留
- 调用方仍可用 `showDialog`，迁移面更小

**Cons**:
- 删除代码量减少（~150 行预估）
- 仍需自维护 `_currentZoomed` + 外层 GestureDetector 的手势竞技场协调
- 拼接式架构（上半 ext / 下半自实现）认知负担略高

### Approach C: PoC 先行（不立即决定 A / B）

**How**: 第一周做 PoC 验证 3 个红旗：
1. #736 在我们用例下是否真实复现
2. #761 同版本 iOS .memory + BoxFit.contain 是否受影响
3. 桌面 mouse drag 翻页是否需要额外配置

PoC 通过 → 走 Approach A；任一红旗复现 → 走 Approach B。

**Pros**: 风险驱动 / 不押注
**Cons**: 周期略长（多 2-3 天）；PRD 与 jsonl 需准备两套

## Requirements (evolving)

* **R1**: `PreviewFullScreenDialog` 的对外 API（构造函数签名、`bytes` /
  `initialIndex` 参数语义）**保持不变**。
* **R2**: 引入 `extended_image: ^10.0.1` 至 `pubspec.yaml` `dependencies:`，
  研究子 agent 已确认锁图无冲突（与 `web ^1.1.0` / `image ^4.3.0` /
  `super_drag_and_drop ^0.9.0` / `flutter_riverpod ^2.6.x` 等均兼容）。
* **R3**: 全部 UX 行为保留（除 R3-exception 列出的几项不可配项）：
  * 缩放：minScale=1.0 / maxScale=4.0 / 双击 2× 切换 / pinch zoom（双击 zoom
    需 caller 持 `AnimationController`，反复调 `state.handleDoubleTap(scale,
    doubleTapPosition)` 推进动画；ext 内置只能 reset 到 `initialScale`）
  * 多图画廊：横向 fling 切页 / 缩放到边缘 bleed 切页（由
    `ExtendedImageGesturePageView` + `GestureConfig(inPageView: true)` 原生提供）
  * 桌面 mouse drag 切页：**保留** `_ImmersiveScrollBehavior` 外包一层（research
    显示 ext 桌面拖动未官方测试，保留我们的 dragDevices 注入是零成本保险）
  * chrome 自动隐藏：3s 计时；tap 切换 + 重置；隐藏后关闭按钮仍可点（与 ext 无关，
    保留 `_chromeVisible / _autoHideTimer / AnimatedOpacity + AnimatedSlide` 原逻辑）
  * drag-to-dismiss：100 dp 阈值 / 800 dp/s fling / 下拉过程背景 opacity 1.0→0.4 /
    未达阈值 snap back **（实现路径见 R3-exception-1）**
  * letterbox 双击降级：**不再需要** —— `ExtendedImageGesture.handleDoubleTap`
    内部对 `doubleTapPosition` 已经做焦点 clamping（焦点落在缩放后图片可视区之外
    时自动 fallback 到内部 center；源码 `gesture.dart`）
* **R3-exception** (用户须接受的细微 UX 降级 / 实现差异):
  * **(1) drag-to-dismiss 实现路径**: 用 `ExtendedImageSlidePage` (StatefulWidget)
    包裹画廊；调用方把 `PreviewFullScreenDialog` 从 `showDialog<void>(Dialog.fullscreen(...))`
    迁移到 **`Navigator.of(context).push(PageRouteBuilder<void>(opaque: false,
    barrierColor: ..., pageBuilder: ...))`**（透明 PageRoute）。`ExtendedImage(...,
    enableSlideOutPage: true)` 内建感知外层 SlidePage 状态。**阈值定制**通过
    `slideEndHandler(ScaleEndDetails)` 回调，命中 100dp 或 800dp/s fling 时返回
    `true` 触发 pop。**背景 opacity**通过 `slidePageBackgroundHandler(color, pageSize,
    offset)` 返回 `Colors.black.withValues(alpha: 1.0 - clamp(|offset.dy|/100, 0,
    1) * 0.6)` 硬编码 1.0→0.4 曲线。
  * **(2) Spring-back 曲线降级**: 现有 `easeOutCubic (250ms)` → ext **固定线性曲线**
    （`slide_page.dart` L201-216，不可配，除非 fork）。下拉未达阈值 release 时，
    回弹动画从"easeOutCubic"变为"linear"。视觉差异较细微，但本小姐认为该差异在
    用户可感知阈值之上（待用户 Q6 确认是否接受）。
  * **(3) M-α SizedBox(renderedSize) workaround 整体删除**: ext 默认 clamp 到
    viewport 边缘，行为与现有 M-α 一致（letterbox 黑边 = 背景黑色 → 视觉等价）。
    `_imageDisplayRect` / `applyBoxFit` 等几何计算全部删除。
  * **(4) `_currentZoomed` ValueNotifier 整体删除**: ext 内置 "zoomed 时
    drag-to-dismiss 屏蔽"逻辑（`gesture.dart` L347-389：只在 `scale == 1.0 &&
    totalScale <= 1` 时路由 pan 到 SlidePage.slide()）。我们的"null callback
    避免 recognizer 进竞技场"机制成为多余。
  * **(5) 自定义 `_PageGestureState` / `_ImmersivePageScrollPhysics` 整体删除**:
    ext 内部的 `movePage()` 判定 + `canScrollPage` 反向闸门替代之。
* **R4**: `PreviewThumbnail` 改用 `ExtendedImage.memory(bytes, fit: BoxFit.contain,
  mode: ExtendedImageMode.none)`（缩略图本身不需要手势，只是为了统一显示栈和
  为将来 Hero 动画铺路）。对外 API（`bytes` / `semanticLabel` / `allBytes` /
  `initialIndex`）保持不变，调用方（grid / stitch）零修改。
* **R5**: 维持当前文件命名空间（`preview_full_screen_dialog.dart`,
  `preview_thumbnail.dart`），不拆新文件除非 widget tree 强烈建议。
* **R6**: 调用方 `preview_thumbnail.dart::_openFullScreen` 从 `showDialog<void>`
  迁移到 `Navigator.of(context).push(PageRouteBuilder<void>(opaque: false, ...))`。
  对 `PreviewThumbnail` 调用方（grid / stitch）零修改 —— 这是
  `PreviewThumbnail` 内部实现细节，对外只是"tap → 打开预览"。

## Acceptance Criteria (evolving)

* [ ] `extended_image` 已加入 `pubspec.yaml`，`flutter pub get` 干净解算
* [ ] `flutter analyze` 0 issue
* [ ] `dart format --set-exit-if-changed .` 0 file
* [ ] 既有 5 个 group 的核心 AC（见"现有测试覆盖"）重写后全部通过
* [ ] 手动验证矩阵（至少 1 移动 1 桌面 1 web）：
  * [ ] 单图：缩放 / 双击 / drag-to-dismiss
  * [ ] 多图：fling 切页 / 缩放到边切页 / mouse drag 切页（桌面）
  * [ ] chrome 自动隐藏 + tap 切换
* [ ] 新 ADR-lite 记录推翻 ADR-0001 的动机 + 选择 extended_image 的代价收益

## Definition of Done

* Tests added/updated（重写后通过）
* Lint / typecheck / CI green
* 新增 ADR 或在既有 ADR-0001 加 "Superseded by … " 注脚
* `preview_full_screen_dialog.dart` 注释中所有指向 `_ImmersivePageScrollPhysics`
  / M-α 布局的内部解释**全部清理或重写**（避免残留误导性历史注释）
* Rollout 风险评估：extended_image 与 super_drag_and_drop / super_clipboard
  无版本冲突；与 Riverpod 2.x 无强依赖（extended_image 不依赖 Riverpod）

## Out of Scope (explicit)

* 不一并迁移 `PreviewThumbnail` 或 grid / stitch 模式下的图片显示（除非 Q2 改变）
* 不引入 extended_image 的额外能力（裁剪 / 滤镜 / 网络图加载 / EditorMode）
* 不改 chrome 视觉风格（AppBar 透明度 / 关闭按钮样式 / 标题格式）
* 不调整缩放参数（min/max scale / 双击 2× 比例 / 边界 tolerance）

## Research References

* [`research/extended_image-overview.md`](research/extended_image-overview.md) —
  `extended_image 10.0.1` (2025-04-21) / MIT / Dart `>=3.7.0 <4.0.0` /
  Flutter `>=3.29.0`，与项目 Dart 3.10.x **兼容**。直接依赖 `extended_image_library
  ^5.0.0` + `meta ^1.7.0` + `vector_math ^2.1.4`；传递性 `crypto / http_client_helper /
  js (legacy stub) / path / path_provider / web`，与现有依赖**零冲突**。维护
  信号：2k+ stars，pub 150/160，但维护者最近 13 个月不主推该 repo（slow triage
  保留 fork preparedness）。
* [`research/extended_image-gallery-api.md`](research/extended_image-gallery-api.md) —
  `ExtendedImageGesturePageView.builder` 原生支持缩放↔切页协调（源码 `gesture.dart:396-431`
  + `utils.dart:350-369`），核心开关 `GestureConfig(inPageView: true)`。Controller
  = `ExtendedPageController(initialPage, pageSpacing, ...)`；`onPageChanged: ValueChanged<int>`
  与原生 PageView 一致。**注意点**：(1) `physics` 参数会被强制 `NeverScrollableScrollPhysics()
  .applyTo(...)` 包装，传 `BouncingScrollPhysics()` 只让 fling 生效；(2) 桌面
  mouse drag 翻页**未官方测试**，建议外包一层 `ScrollConfiguration(behavior with
  dragDevices: {touch, mouse, trackpad, ...})`；(3) `preloadPagesCount` 上层
  不暴露，需 `precacheImage`；(4) `cacheGesture: false` (默认) → 跨页 transformation
  状态不保留（与现有行为一致）。
* [`research/extended_image-gesture-and-slide.md`](research/extended_image-gesture-and-slide.md) —
  **API 真实命名纠正**: `SlidePageRoute<T>` 在 v10.0.1 中**不存在**。drag-to-dismiss
  的真实 API 是 `ExtendedImageSlidePage`（StatefulWidget）+ 调用方提供透明 `PageRoute`
  (例如 `PageRouteBuilder(opaque: false, barrierColor: ..., pageBuilder: ...)`)；
  `ExtendedImage(enableSlideOutPage: true)` 是 ExtendedImage 与外层 SlidePage 协作
  的开关。**重要简化**: drag-to-dismiss 在 zoomed (`totalScale > 1` 或
  `scale != 1.0`) 时由 `gesture.dart` L347-389 **自动屏蔽**——现有 `_currentZoomed`
  ValueNotifier + 条件 callback 挂载机制**可以完全删除**。**新限制**: spring-back
  动画曲线**不可配**（`slide_page.dart` L201-216 固定 linear `AnimationController`），
  现有 `easeOutCubic (250ms)` 会丢失；双击 zoom 到 2× 仍需 caller 持
  `AnimationController` + 反复调 `state.handleDoubleTap(scale, doubleTapPosition)`
  (示例 `pic_swiper.dart` L457-490)，焦点 clamping 内建（**letterbox fallback
  不再需要**）。**boundary clamp** 固定在 viewport 边缘（无 `boundaryMargin` 等价物）
  → **M-α `SizedBox.fromSize(renderedSize)` workaround 整体可以删除**。所有阈值
  通过 `slideEndHandler(ScaleEndDetails)` / `slidePageBackgroundHandler(pageSize, offset, ...)`
  这两个 handler callback 实现，分别覆盖"100 dp / 800 dp/s 阈值"和"1.0 → 0.4
  opacity 联动"。

## Risks (from research)

* **R-risk-1 (open issue #736, Android, 16 comments)** — "swipe-to-dismiss
  combined with the page view is fragile"，单指垂直 swipe 在手势竞技场被
  `ExtendedVerticalDragGestureRecognizer` 拒绝。**这是高风险**: 我们的 drag-to-dismiss
  + 多图画廊场景命中该 bug 的可能性高。**Mitigation**: PoC 阶段优先验证此点；
  如失效则保留外层 `GestureDetector(onVerticalDrag*)` + 自实现 100dp 阈值（与
  现有方案相同），仅画廊与缩放交给 extended_image。
* **R-risk-2 (open issue #761, iOS, v10.0.1)** — fresh bug on
  `ExtendedImageGesturePageView.builder + ExtendedImage.file + BoxFit.contain`,
  0 comments since Feb 2026。**Mitigation**: 我们用 `.memory` 不是 `.file`，
  但需要在 PoC 阶段在 iOS 真机/模拟器上验证 `.memory + BoxFit.contain` 不受影响。
* **R-risk-3 (open issue #752)** — `allowImplicitScrolling` 不可配，预加载有
  瞬时空白。**Mitigation**: 用官方建议的 `precacheImage` + `onPageChanged
  pre/next` 预热。
* **R-risk-4 (open issue #686 / #648)** — 缩放到最小后回弹卡住 / 快速横滑切页
  不流畅。**Mitigation**: PoC 验收时加入"反复横扫 10 次切页 / minScale 回弹"
  的手动 smoke。
* **R-risk-5 (维护信号)** — 维护者最近 13 个月不主推 repo，PR/issue triage
  慢。**Mitigation**: 在 ADR-lite 中标记"将来若 Flutter SDK 重大升级时可能需要
  fork/patch"，并在仓库 README 加一行 fork-preparedness 注脚。

## Decision (ADR-lite)

**Context**: 现有 `_ImmersivePageScrollPhysics` 自实现的"缩放后边缘 bleed 切页"
在实际使用中**不连贯**（用户反馈：触底判定 + tolerance 在某些手势序列下漏判/误判，
且其它体验问题持续）。ADR-0001 当时拒绝 `photo_view_gallery` 的核心理由是"for
one screen"成本不值得，但完成自实现后实际维护成本（884 行实现 + 783 行测试）已
明显超过当时预估，bug 仍未根治。

**Decision**: 采用 **Approach A: 全面拥抱 `extended_image: ^10.0.1`**:
- `PreviewFullScreenDialog` 完全用 `ExtendedImageSlidePage` (drag-to-dismiss
  root) + `ExtendedImageGesturePageView.builder` (画廊层) + `ExtendedImage.memory(
  ..., mode: ExtendedImageMode.gesture, inPageView: true)` (单页叶子)
- `PreviewThumbnail` 改用 `ExtendedImage.memory(..., mode: ExtendedImageMode.none)`
- 调用方迁移 `showDialog<void>` → `Navigator.of(context).push(PageRouteBuilder<void>(
  opaque: false, barrierColor: Colors.transparent, pageBuilder: ...))`（透明
  PageRoute，让 SlidePage 的背景 opacity handler 直接生效）
- 删除自实现 ~500 行：`_ImmersivePageScrollPhysics` / `_PageGestureState` /
  `_currentZoomed` / `_imageDisplayRect` / `_resolveImageSize` / M-α
  `SizedBox(renderedSize)` workaround / 外层垂直拖动 GestureDetector / drag-snap-back
  `AnimationController`（保留：chrome auto-hide / `_ImmersiveScrollBehavior` /
  双击 zoom 的 caller-owned `AnimationController` 配 `handleDoubleTap`）
- ADR-0001 状态从 Accepted 改为 Superseded，添加 "Superseded by ADR-0002 (2026-05-22)"
  注脚；新写 ADR-0002 记录推翻动机 + 代价收益（接受 spring-back 曲线降级、
  接受 #736 风险 + PoC 验证 mitigation）

**Consequences**:
- **正向**: 自维护代码减少 ~500 行；缩放↔切页协调彻底交给上游（解决用户痛点）；
  letterbox 双击降级问题彻底消失（焦点 clamping 内建）；未来扩展 Hero / cropping /
  滤镜路径最短
- **负向**: spring-back 曲线从 `easeOutCubic` 退化为 linear（用户已接受）；
  绑定 extended_image 维护节奏（维护者最近 13 个月不主推，PR/issue triage 慢；
  Mitigation: 仓库 README 加 fork-preparedness 注脚）；命中 #736 / #761 风险
  （Mitigation: 实现前先做最小 PoC 验证，验证失败回退到 Approach B）
- **中性**: ADR-0001 中考虑过的 `photo_view_gallery` 替代仍未被采用，转而选择
  `extended_image` 因为其 API 更现代、维护更频（虽近期略慢）、支持
  Wasm-ready、覆盖 6 平台

## Implementation Plan (subtasks)

将 brainstorm 任务自身仅做 PRD/jsonl 准备；具体实施拆为 4 个 child subtask：

* **ST1**: `extended-image-dep-and-poc` — 引入 `extended_image: ^10.0.1` 到
  `pubspec.yaml`；`flutter pub get` + `flutter pub deps` 验证锁图；做最小 PoC
  代码（独立的 `_poc_dialog.dart` 一次性脚本，不进入正式调用链）验证 3 个红旗：
  (a) #736 drag-to-dismiss + GesturePageView 在我们用例下是否真实复现；
  (b) #761 iOS .memory + BoxFit.contain 不受影响；(c) 桌面 mouse drag 翻页是否
  需要额外配置。PoC 通过 → 后续 ST2/ST3 安全推进；任一红旗复现 → 重新进
  brainstorm 切到 Approach B（这是 risk gate）。
* **ST2**: `migrate-preview-full-screen-dialog` — 重写
  `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`:
  `ExtendedImageSlidePage` + `ExtendedImageGesturePageView.builder` +
  `ExtendedImage.memory(mode: gesture, inPageView: true)` 三层；caller-owned
  `AnimationController` 配 `handleDoubleTap` 实现 2× 双击 zoom；`slideEndHandler`
  + `slidePageBackgroundHandler` 实现 100dp / 800dp/s / 1.0→0.4 opacity；保留
  chrome auto-hide + `_ImmersiveScrollBehavior`；删除 ~500 行老实现。同步更新
  `PreviewThumbnail._openFullScreen` 从 `showDialog` 到 `Navigator.push(
  PageRouteBuilder(opaque: false, ...))`。
* **ST3**: `migrate-preview-thumbnail` — 重写
  `lib/features/export/presentation/widgets/preview_thumbnail.dart`:
  `ExtendedImage.memory(bytes, fit: BoxFit.contain, mode: ExtendedImageMode.none)`，
  对外 API 不变。验证 grid / stitch 调用方无回归。
* **ST4**: `rewrite-tests-and-update-adrs` — 重写
  `test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart`
  （783 行 → 适配 ExtendedImage / ExtendedImageGesturePageView widget tree，
  断言换成 `find.byType(ExtendedImage)` + `tester.state<ExtendedImageGestureState>`
  / `extendedImageGestureKey.currentState!.gestureDetails.totalScale`）；
  保持现有 5 个 group ~20 个用例的 AC 等价覆盖；在 `docs/adr/0001-...md` 加
  "Superseded by ADR-0002 (2026-05-22)" 注脚，新写 `docs/adr/0002-extended-image-fullscreen-preview.md`
  记录 Decision (ADR-lite) 的完整内容。`flutter analyze` + `dart format` + `flutter test`
  全绿；至少 1 移动 + 1 桌面 + 1 web 手动 smoke 矩阵签字。

## Technical Notes

* 当前实现路径: `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart` (884 行)
* 当前测试路径: `test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart` (783 行)
* 调用方: `lib/features/export/presentation/widgets/preview_thumbnail.dart`
* 既往任务（按时序）：
  * `05-20-export-page-preview` — 初始预览功能（单图）
  * `05-22-export-preview-fullscreen-immersive` — 多图画廊 + 沉浸式 chrome
  * `05-22-limit-fullscreen-preview-pan-bounds` — M-α 布局 + 边界 clamp
* 决策记录: `docs/adr/0001-immersive-page-scroll-physics.md`（Accepted →
  完成本任务后改为 Superseded by ADR-0002）
* 依赖政策: `.trellis/spec/frontend/dependencies-and-platforms.md`
* 关键源码定位（extended_image v10.0.1）:
  * `lib/src/gesture/page_view/gesture_page_view.dart:70-110` — `ExtendedImageGesturePageView.builder` 签名
  * `lib/src/gesture/page_view/page_controller/page_controller.dart:4-10` — `ExtendedPageController`
  * `lib/src/gesture/gesture.dart:347-389` — drag-to-dismiss 在 zoomed 时自动屏蔽（核心简化点）
  * `lib/src/gesture/gesture.dart:396-431` — 边缘溢出切页路由
  * `lib/src/gesture/utils.dart:350-369` — `movePage()` 边界判定
  * `lib/src/gesture/page_view/gesture_page_view.dart:550-556` — `canHorizontalOrVerticalDrag` 反向闸门
  * `lib/src/extended_image_slide_page.dart` — SlidePage state machine (drag-to-dismiss)
  * `example/lib/pages/simple/photo_view_demo.dart` — 简版多图画廊参考
  * `example/lib/common/widget/pic_swiper.dart:457-490` — 双击 zoom + AnimationController 参考实现
