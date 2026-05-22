# Research: extended_image — GestureConfig + SlidePage（drag-to-dismiss）

- **Query**: `GestureConfig`/`initGestureConfigHandler` 完整参数 + 双击缩放 + 边界 clamp + `inPageView`；`SlidePageRoute` + `enableSlideOutPage` drag-to-dismiss / 阈值 / 背景 opacity / zoomed 时自动 disable / 代码示例
- **Scope**: external（`fluttercandies/extended_image` `master` HEAD）
- **Date**: 2026-05-22
- **Version inspected**: `extended_image: 10.0.1`（env: Flutter ≥ 3.29.0, Dart ≥ 3.7.0）
- **Sources**: `lib/src/gesture/{utils,gesture,slide_page}.dart`、`lib/src/{extended_image,typedef}.dart`、`example/lib/pages/simple/{zoom_image_demo,slide_page_demo}.dart`、`example/lib/common/widget/pic_swiper.dart`、`README.md`

## 重大澄清（先于细节）

1. **`SlidePageRoute<T>` 在 `extended_image` 里不存在**。整个 repo grep 无此 symbol。任务描述里的"SlidePageRoute 构造函数"是误传 —— 真名 `ExtendedImageSlidePage`，是 **`StatefulWidget`**，不是 `PageRoute`。
2. **drag-to-dismiss 正确组合**: `ExtendedImageSlidePage`（外层 wrap）+ `ExtendedImage(enableSlideOutPage: true)`（订阅祖先 slide state）+ **caller 自备透明 PageRoute**（如 `PageRouteBuilder(opaque: false, …)`）。README 提到的 `TransparentMaterialPageRoute` 也**不是 extended_image 提供**，须自写或从其它包引入。
3. `GestureConfig` 没有 `gestureDetailsBuilder` 或 `cacheGestureBoundary` 字段（任务描述里这两个在 v10.0.1 不存在）。
4. 默认 dismiss 阈值源码 (`utils.dart` L599) = `pageSize/6`，README 写 `pageSize/3.5`（**源码为准**，且都会被自定义 `slideEndHandler` 覆盖）。

# Section 1 — `GestureConfig` 与 `initGestureConfigHandler`

## 1.1 `GestureConfig` 完整构造签名

`lib/src/gesture/utils.dart` L416-485：

```dart
class GestureConfig {
  GestureConfig({
    this.minScale = 0.8, this.maxScale = 5.0,
    this.speed = 1.0, this.inertialSpeed = 100.0,
    this.cacheGesture = false, this.initialScale = 1.0,
    this.inPageView = false,
    double? animationMinScale,   // 默认 minScale * 0.8
    double? animationMaxScale,   // 默认 maxScale * 1.2
    this.initialAlignment = InitialAlignment.center,
    this.gestureDetailsIsChanged,
    this.hitTestBehavior = HitTestBehavior.deferToChild,
    this.reverseMousePointerScrollDirection = false,
  }) : assert(minScale <= maxScale),
       animationMinScale = animationMinScale ?? minScale * 0.8,
       animationMaxScale = animationMaxScale ?? maxScale * 1.2,
       assert(animationMinScale <= minScale),
       assert(animationMaxScale >= maxScale),
       assert(minScale <= initialScale && initialScale <= maxScale),
       assert(speed > 0), assert(inertialSpeed > 0);
}
```

| 参数 | 默认 | 一行说明 |
|---|---|---|
| `minScale` / `maxScale` | `0.8` / `5.0` | 最小/最大缩放（pinch 释放后回弹到此） |
| `speed` | `1.0` | zoom/pan 输入速度乘数（手势 delta × speed） |
| `inertialSpeed` | `100.0` | pan 结束 fling 惯性距离系数 |
| `cacheGesture` | `false` | PageView 切回同页保留缩放；启用后须调 `clearGestureDetailsCache()` |
| `initialScale` | `1.0` | 首次显示倍率（落在 `[minScale, maxScale]`） |
| `inPageView` | `false` | 是否嵌套在 `ExtendedImageGesturePageView` 内（详见 §1.4） |
| `animationMinScale` / `animationMaxScale` | `minScale*0.8` / `maxScale*1.2` | pinch "过冲"上下限，松手回弹到 `minScale`/`maxScale` |
| `initialAlignment` | `center` | `initialScale > 1` 时图片对齐方向（9 种 `InitialAlignment` enum） |
| `gestureDetailsIsChanged` | `null` | 状态变化回调（每次 setState 触发） |
| `hitTestBehavior` | `deferToChild` | 内部 `GestureDetector` + `Listener` 的 hitTest |
| `reverseMousePointerScrollDirection` | `false` | 桌面滚轮方向反转（`false`：下滚=放大） |

任务里提到的 `gestureDetailsBuilder` 和 `cacheGestureBoundary` 在 v10.0.1 不存在。

## 1.2 双击缩放 — 如何接线

**双击不会自动放大到固定倍率**。`ExtendedImageMode.gesture` 内置 `_handleDoubleTap`（`gesture.dart` L212-226）只把状态重置为 `initialScale + offset.zero` —— 是"双击复位"，不是"双击放大"。要做"双击 1× ↔ 2×"，必须通过 `ExtendedImage(onDoubleTap: …)` 回调自写动画并调用 `state.handleDoubleTap(scale, doubleTapPosition)`（`gesture.dart` L167-182）：

```dart
void handleDoubleTap({double? scale, Offset? doubleTapPosition}) {
  doubleTapPosition ??= _pointerDownPosition;        // 默认用双击落点
  scale ??= _gestureConfig!.initialScale;
  handleScaleStart(ScaleStartDetails(focalPoint: doubleTapPosition!));
  handleScaleUpdate(ScaleUpdateDetails(focalPoint: doubleTapPosition,
    scale: scale / _startingScale!, focalPointDelta: Offset.zero));
  if (scale < _gestureConfig!.minScale || scale > _gestureConfig!.maxScale)
    handleScaleEnd(ScaleEndDetails());
}
```

它复用 `handleScaleUpdate`，**焦点 clamping 走 §1.3 同一套边界处理** —— 焦点越界时 `calculateFinalDestinationRect` 自动钉回 viewport 边缘，**无需手写 letterbox 降级**。

`pic_swiper.dart` L457-490 标准双击放大模板（精简）：

```dart
onDoubleTap: (ExtendedImageGestureState state) {
  final pointerDownPosition = state.pointerDownPosition;
  final begin = state.gestureDetails!.totalScale;
  final end = (begin == 1.0) ? 2.0 : 1.0;
  _doubleTapAC.stop(); _doubleTapAC.reset();
  _doubleTapAnimation?.removeListener(_listener);
  _doubleTapAnimation = _doubleTapAC.drive(Tween(begin: begin, end: end));
  _listener = () => state.handleDoubleTap(
        scale: _doubleTapAnimation!.value, doubleTapPosition: pointerDownPosition);
  _doubleTapAnimation!.addListener(_listener);
  _doubleTapAC.forward();
},
```

caller 自己持有 `AnimationController _doubleTapAC`（vsync = 父 widget），duration 通常 200ms。

## 1.3 边界 clamp — 对应 `InteractiveViewer.boundaryMargin`

**无 `boundaryMargin` 参数**。boundary 强制启用，钉在 **viewport (`layoutRect`)** 边缘 —— 不是图像像素边，也不是 letterbox 内侧。`GestureDetails._innerCalculateFinalDestinationRect`（`utils.dart` L276-348）：

- 当 `result.left >= layoutRect.left` → 钉回左边并置 `_boundary.left = true`；右/上/下同理（四向独立判定）。
- `_computeHorizontalBoundary` 由"缩放后图像宽 ≥ viewport 宽"决定 —— 图像比 viewport 窄时**不** clamp，允许居中。
- 对比 M-α 布局：M-α 需要外层 `SizedBox.fromSize(renderedSize)` + `boundaryMargin: zero`；`extended_image` 直接以 viewport 为边，**不需要外层 SizedBox**。
- `Boundary` 四个 flag 暴露给 `ExtendedImageGesturePageView`，是"缩放到边再切页"的判定基础（`utils.dart` L350-369 `movePage()`）。

## 1.4 `inPageView: true` 的实际作用

`gesture.dart` L137-145：

```dart
if (_gestureConfig!.inPageView) {
  _pageViewState = context.findAncestorStateOfType<ExtendedImageGesturePageViewState>();
  _pageViewState?.extendedImageGestureState = this;
}
```

- 仅 `inPageView == true` 时向上查 `ExtendedImageGesturePageViewState` 祖先并注册手势 state。
- 注册后，**单指 pan 在缩放 > 1 且触底时**通过 `_pageViewState.onDragUpdate(…)` 委托给 PageView（`gesture.dart` L397-431 `movePage` 分支）—— 这就是"缩放到边 → bleed 切页"的桥梁。
- 不设此 flag 时即使 `ExtendedImage` 套在 `ExtendedImageGesturePageView` 里，**两者也互不沟通**，拖到边会卡住或与 PageView 抢手势。
- 结论：**多图画廊必须设 `inPageView: true`**；单图（非 PageView 内）保持 `false`。

# Section 2 — drag-to-dismiss（`ExtendedImageSlidePage` + `enableSlideOutPage`）

## 2.1 `ExtendedImageSlidePage` 构造签名（不是 `SlidePageRoute`）

`lib/src/gesture/slide_page.dart` L12-24：

```dart
class ExtendedImageSlidePage extends StatefulWidget {
  const ExtendedImageSlidePage({
    this.child, this.slidePageBackgroundHandler, this.slideScaleHandler,
    this.slideOffsetHandler, this.slideEndHandler,
    this.slideAxis = SlideAxis.both,
    this.resetPageDuration = const Duration(milliseconds: 500),
    this.slideType = SlideType.onlyImage,
    this.onSlidingPage, Key? key,
  }) : super(key: key);
}
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `child` | `null` | 被 slide 容器包裹的内容（通常是整个画廊 Stack） |
| `slidePageBackgroundHandler` | `defaultSlidePageBackgroundHandler` | 拖动中页面背景色（含 alpha） |
| `slideScaleHandler` | `defaultSlideScaleHandler` | 拖动中 child 缩放（默认 1.0 → 0.8） |
| `slideOffsetHandler` | 直传 | 改写实际平移量（如只允许向下） |
| `slideEndHandler` | `defaultSlideEndHandler` | 松手回调；返回 `true` → pop，`false`/`null` → spring back |
| `slideAxis` | `both` | `both` / `horizontal` / `vertical` |
| `resetPageDuration` | `500ms` | spring back 时长（**固定线性 controller，无 curve API**） |
| `slideType` | `onlyImage` | `wholePage` 整页 / `onlyImage` 仅图（背景立即透明等 pop） |
| `onSlidingPage` | `null` | 每帧拖动回调 — 文档警告**不要 setState**，用 stream/notifier |

**无 `transitionDuration` / `reverseTransitionDuration`** —— 那些是 `PageRoute` 属性，进出场动画由调用方提供的 `PageRoute` 决定。

## 2.2 `enableSlideOutPage: true` 的运作机制

`lib/src/extended_image.dart` L1102-1105、L1128-1134：

```dart
if (widget.enableSlideOutPage) {
  _slidePageState = context.findAncestorStateOfType<ExtendedImageSlidePageState>();
}
```

- 开关 = 是否让 `ExtendedImage` 在 `didChangeDependencies`/`didUpdateWidget` 时查找祖先 `ExtendedImageSlidePageState`。
- 找到后，内部 `ExtendedImageGesture` 在 `handleScaleUpdate` 判定是否转发 slide 拖动并调 `extendedImageSlidePageState!.slide(focalPointDelta, …)`。
- **InheritedWidget-style ancestor lookup**（实现上不是 `InheritedWidget`，效果相同）；若 `ExtendedImage` 不在 `ExtendedImageSlidePage` 后代里，开关静默无效。

## 2.3 自定义阈值与速度

**无 `slideOutPagePoint` / `slideOutPageSpeed` 字段**。通过 `slideEndHandler` 完全替换。typedef：

```dart
typedef SlideEndHandler = bool? Function(Offset offset, {
  ExtendedImageSlidePageState state, ScaleEndDetails details,
});  // details.velocity.pixelsPerSecond 单位 logical-px/s ≡ dp/s
```

把"drag > 100 dp = dismiss 或 fling > 800 dp/s = dismiss"翻译（参考 `pic_swiper.dart` L684-717）：

```dart
slideEndHandler: (Offset offset, {state, details}) {
  if (state == null || details == null) return null;
  final dragDistance = offset.dy.abs();
  final flingVelocity = details.velocity.pixelsPerSecond.dy.abs();
  if (dragDistance >= 100.0 || flingVelocity >= 800.0) return true; // dismiss
  return false;                                                     // spring back
},
```

- 返回 `true` → `endSlide` 内部 `Navigator.pop(context)`（`slide_page.dart` L193-198）。
- 返回 `false` → `_backAnimationController.forward()` 用 `resetPageDuration` 的线性 Tween 拉回（L201-216）。
- **spring back 曲线无法配置**：源码裸 `AnimationController` 无 `CurvedAnimation`。当前 `easeOutCubic` 会**丢失**（spring back 变线性）。如必须保留 → 自包 `slideOffsetHandler` 应用 curve（hacky）或 fork。

## 2.4 拖动过程背景 opacity

默认 `defaultSlidePageBackgroundHandler`（`utils.dart` L575-592）：

```dart
double opacity = 0.0;
if (pageGestureAxis == SlideAxis.both) {
  opacity = offset.distance / (Offset(pageSize.width, pageSize.height).distance / 2.0);
} else if (pageGestureAxis == SlideAxis.vertical) {
  opacity = offset.dy.abs() / (pageSize.height / 2.0);
}
return color.withValues(alpha: min(1.0, max(1.0 - opacity, 0.0)));
```

默认 **1.0 → 0.0** 线性（到半页/半对角线完全透明）。复刻现有 **1.0 → 0.4**：

```dart
slidePageBackgroundHandler: (Offset offset, Size pageSize) {
  final fraction = (offset.dy.abs() / 100.0).clamp(0.0, 1.0); // 100 dp 阈值
  return Colors.black.withValues(alpha: 1.0 - fraction * 0.6); // 1.0 → 0.4
},
```

配合 `slideScaleHandler: (_, {state}) => 1.0` 禁用 child 缩放，复刻"只改 opacity 不缩 child"。

## 2.5 缩放时是否自动 disable drag-to-dismiss

**自动门控，无需手写**。`gesture.dart` L347-389 `handleScaleUpdate`：

```dart
if (extendedImageSlidePageState != null &&
    details.scale == 1.0 &&                              // 不是 pinch
    (_gestureDetails!.totalScale ?? 1) <= 1 &&           // 当前未放大
    _gestureDetails!.userOffset &&
    _gestureDetails!.actionType == ActionType.pan) {
  // … 计算是否调 extendedImageSlidePageState!.slide(...)
}
```

- `totalScale > 1.0` 时 `slide()` 永不调用 —— **缩放下的单指 pan 完全归属图像，drag-to-dismiss 被静默屏蔽**。
- 覆盖了现有"通过 `ValueNotifier` 上报 zoomed 再决定是否挂垂直拖 callback"的全部职责，**无需自写 zoomed 状态机**。

## 2.6 完整代码示例

提炼自 `example/lib/pages/simple/slide_page_demo.dart` L83-150 + `pic_swiper.dart` L399-734：

```dart
class FullscreenPreviewPage extends StatefulWidget {
  const FullscreenPreviewPage({super.key, required this.images, this.initial = 0});
  final List<Uint8List> images;
  final int initial;
  // 关键：透明 PageRoute（extended_image 不提供，须自备）
  static Route<void> route({required List<Uint8List> images, int initial = 0}) =>
      PageRouteBuilder<void>(opaque: false, barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) =>
            FullscreenPreviewPage(images: images, initial: initial));
  @override State<FullscreenPreviewPage> createState() => _State();
}

class _State extends State<FullscreenPreviewPage> {
  final slidePageKey = GlobalKey<ExtendedImageSlidePageState>();
  @override Widget build(BuildContext context) => Material(
    color: Colors.transparent,                            // 必须透明
    child: ExtendedImageSlidePage(key: slidePageKey,
      slideAxis: SlideAxis.vertical, slideType: SlideType.onlyImage,
      slidePageBackgroundHandler: (offset, _) {
        final frac = (offset.dy.abs() / 100.0).clamp(0.0, 1.0);
        return Colors.black.withValues(alpha: 1.0 - frac * 0.6);
      },
      slideEndHandler: (offset, {state, details}) {
        final d = offset.dy.abs();
        final v = details?.velocity.pixelsPerSecond.dy.abs() ?? 0;
        return d >= 100.0 || v >= 800.0;
      },
      slideScaleHandler: (_, {state}) => 1.0,             // 不缩 child
      child: ExtendedImageGesturePageView.builder(
        controller: ExtendedPageController(initialPage: widget.initial),
        itemCount: widget.images.length,
        itemBuilder: (ctx, i) => ExtendedImage.memory(widget.images[i],
          fit: BoxFit.contain, mode: ExtendedImageMode.gesture,
          enableSlideOutPage: true,                       // 订阅 SlidePage
          initGestureConfigHandler: (_) => GestureConfig(
            inPageView: true, minScale: 1.0, maxScale: 4.0,
            initialScale: 1.0, initialAlignment: InitialAlignment.center),
          onDoubleTap: _handleDoubleTap,                  // 见 §1.2 模板
        ),
      ),
    ),
  );
}
```

## Caveats / Not Found

- **`SlidePageRoute<T>` 不存在** — 真名 `ExtendedImageSlidePage` widget；进出场动画必须由调用方的 `PageRoute`（`opaque: false`）单独提供。
- **`GestureConfig` 无 `gestureDetailsBuilder` / `cacheGestureBoundary`**（v10.0.1 不存在）。
- **spring back curve 不可配置** — 固定线性 `AnimationController`，会丢现有 `easeOutCubic`；只能改 `resetPageDuration` 或在 `slideOffsetHandler` 手动 ease（hacky）。
- **默认 dismiss 阈值源码与 README 不一致** — README `pageSize/3.5`，源码 `pageSize/6`。**源码为准** —— 但我们都会用自定义 `slideEndHandler`，不依赖默认。
- **`heroBuilderForSlidingPage` 未覆盖**（任务未问）：未来给缩略图加 Hero 过渡时需要传，参考 `example/lib/common/widget/hero.dart`。
- **桌面 mouse drag 在 SlidePage 内未实测** — 源码用 `GestureDetector(onScaleStart/Update/End)`，理论上 mouse 一指拖可用，但**未实测**；建议 manual verification 矩阵专门测一次。
- **未确认 `extended_image: 10.0.1` 与项目锁图 SAT 兼容性** — 项目 spec 要求 `flutter pub deps | grep` 验证，需另起 `extended_image-overview.md` 处理。
- **测试侧 finder** — 旧测试用 `find.byType(InteractiveViewer)` 失效；新代码下应 `find.byType(ExtendedImage)` + `tester.state<ExtendedImageGestureState>` 或通过 `extendedImageGestureKey` 直接拿 `state.gestureDetails.totalScale` 做断言。
