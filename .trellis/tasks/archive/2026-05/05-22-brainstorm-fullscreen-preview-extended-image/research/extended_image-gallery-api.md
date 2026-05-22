# extended_image — Gallery / Multi-image API Research

> 源码基础: `extended_image` v10.0.1，克隆至 `/tmp/extended_image_research`
> 所有论据均标注源码文件:行号。

## TL;DR

`ExtendedImageGesturePageView` **原生支持边缘溢出到翻页** —— 这是它存在的核心理由。开箱即用、无需自定义 `ScrollPhysics`。但 `preloadPagesCount` 在上层未透传，需用 `precacheImage` 手动预热；桌面鼠标拖动需自行验证。

---

## 1. `ExtendedImageGesturePageView[.builder]` API

来源: `/tmp/extended_image_research/lib/src/gesture/page_view/gesture_page_view.dart:70-110`

```dart
ExtendedImageGesturePageView.builder({
  Key? key,
  Axis scrollDirection = Axis.horizontal,
  bool reverse = false,
  ExtendedPageController? controller,               // 见 Q6
  ScrollPhysics? physics,                           // 会被强制 applyTo(NeverScrollableScrollPhysics)
  bool pageSnapping = true,
  ValueChanged<int>? onPageChanged,                 // 见 Q5
  required IndexedWidgetBuilder itemBuilder,
  int? itemCount,
  CanScrollPage? canScrollPage,                     // (GestureDetails?) -> bool, 自定义闸门
  ShouldAccpetHorizontalOrVerticalDrag? shouldAccpetHorizontalOrVerticalDrag,  // 多指/鼠标场景调参
})
```

集成方式: 在 `itemBuilder` 里返回 `ExtendedImage(... mode: ExtendedImageMode.gesture, initGestureConfigHandler: (s) => GestureConfig(inPageView: true, ...))`。**`inPageView: true` 必须设置**，否则图片与 PageView 间不会自动协调（`gesture.dart:140` `_pageViewState` 仅在 `inPageView == true` 时通过 `findAncestorStateOfType` 注册）。

底层架构（位于 `gesture_page_view.dart:337-356`）：包一层 `GesturePageView.custom` + 外层 `RawGestureDetector`（持有 `ExtendedHorizontalDragGestureRecognizer`）。内层 scrollable 被强制 `NeverScrollableScrollPhysics` 接管，所有拖动由外层识别器路由到 `position.drag()`。

---

## 2. 边缘溢出翻页（核心特性，开箱即用）

证据链（两段联合实现 iOS Photos 行为）：

**(a) 图片端检测边界 → 转交 PageView** — `lib/src/gesture/gesture.dart:396-431`:

```dart
if (_pageViewState != null) {
  final bool movePage = _pageViewState!.isDraging ||
      (details.pointerCount == 1 &&
       details.scale == 1 &&
       _gestureDetails!.movePage(details.focalPointDelta, axis));
  if (movePage) {
    if (!pageViewState.isDraging) {
      pageViewState.onDragDown(...);
      pageViewState.onDragStart(...);
    }
    pageViewState.onDragUpdate(DragUpdateDetails(... primaryDelta: delta.dx));
    return;
  }
}
```

**(b) `movePage()` 边界判定** — `lib/src/gesture/utils.dart:350-369`:

```dart
bool movePage(Offset delta, Axis axis) {
  if (totalScale! <= 1.0) return false;       // 未放大 -> PV 自己接管
  return delta.dx != 0 &&
      delta.dx.abs() > delta.dy.abs() &&
      ((delta.dx < 0 && boundary.right) ||    // 向左拖 + 已到右边界 -> 翻下一页
       (delta.dx > 0 && boundary.left)  ||    // 向右拖 + 已到左边界 -> 翻上一页
       !_computeHorizontalBoundary);
}
```

**(c) PV 端反向闸门** — `gesture_page_view.dart:550-556`，未缩放（totalScale ≤ 1）时 `canHorizontalOrVerticalDrag` 返回 true（PV 直接接管）；放大时返回 false（让图片的 `ScaleGestureRecognizer` 先吃掉手势，再按 (a)/(b) 决定是否回灌给 PV）。

**结论**: 行为完全等价于现有自定义 `PageScrollPhysics` 的 `{zoomed, atLeftEdge, atRightEdge}` 跟踪。**阈值**: `minGesturePageDelta = 5.0`px (`utils.dart:505`)；**速度**沿用 `physics.minFlingVelocity`（`gesture_page_view.dart:254-256`，外部 `physics` 注入）。

附加 hook: `canScrollPage: (GestureDetails?) -> bool` 可作为额外业务闸门（示例: 详情面板已下拉时禁用翻页，见下方代码 `_imageDetailY >= 0`）。

---

## 3. 桌面鼠标拖动

混合结论:

- **图片缩放/拖动（图片端）**: `gesture.dart:117-124` 用 Flutter 内置 `GestureDetector` 的 `onScaleStart/Update/End`，`ScaleGestureRecognizer` 默认 `supportedDevices = null` → 接受所有 `PointerDeviceKind`（含 mouse, trackpad）。鼠标按住拖动放大后的图片应当工作。
- **滚轮缩放**: `gesture.dart:235-255` 显式监听 `PointerScrollEvent` + `event.kind == PointerDeviceKind.mouse`，开箱支持。`GestureConfig.reverseMousePointerScrollDirection` 可反向 (`utils.dart:484`)。
- **PageView 翻页拖动（未缩放 1x 时）**: 由 `ExtendedHorizontalDragGestureRecognizer`（`drag_gesture_recognizer.dart:65-82`）处理。该类继承自 Flutter 的 `_HorizontalDragGestureRecognizer`，构造参数透传 `supportedDevices`，默认为 `null` → 理论上接受 mouse。但 `widget.controller.shouldIgnorePointerWhenScrolling` 决定是否再叠加一个 `ScaleGestureRecognizer`（`gesture_page_view.dart:293-306`），在动画期间会忽略指针。

**警告**: 仓库源码、README、CHANGELOG 均未显式声明"桌面 mouse 拖动翻页"为受支持场景。`grep mouse|desktop|trackpad` 仅命中滚轮缩放相关代码（`reverseMousePointerScrollDirection`）。CHANGELOG 9.0.1 仅提及 "Make the list can be scrolled on web platform"（指 ListView 不是 PageView）。**建议**: 上层若要保险，外面再包一层 `ScrollConfiguration(behavior: AppScrollBehavior with dragDevices: {touch, mouse, trackpad, ...})`，无副作用。

---

## 4. 预加载与跨页状态保留

**预加载**: `ExtendedImageGesturePageView.builder` **不暴露** `preloadPagesCount`。底层 `GesturePageView`（`widgets/page_view.dart:299`）支持，但 `gesture_page_view.dart:337-346` 在转调 `GesturePageView.custom(...)` 时**未透传**该参数 → 实际 `cacheExtent = 0.0`（仅当前 viewport）。

**官方示例做法**: 在 `onPageChanged` 与 `didChangeDependencies` 里手动调 `precacheImage(ExtendedNetworkImageProvider(url, cache: true, imageCacheName: 'CropImage'), context)`（见 `pic_swiper.dart:379-397` 与 `simple/photo_view_demo.dart:45-56`）。对内存图片可直接 `precacheImage(MemoryImage(bytes), context)`。

**跨页 transformation 状态**: `GestureConfig(cacheGesture: true)` 可保留缩放/偏移状态——缓存以 `extendedImageState.imageStreamKey` 为 key（`gesture.dart:71-74`），同一 `ImageProvider` 回滑时复用上次状态。退出页面记得调 `clearGestureDetailsCache()`（顶层函数 `gesture.dart:17`）。示例中默认 `cacheGesture: false`（每次回到该页都从 identity 开始）。

---

## 5. 页码变更回调

`onPageChanged: ValueChanged<int>?`，语义与官方 `PageView.onPageChanged` 一致。源码 `widgets/page_view.dart:343-356` 通过 `NotificationListener<ScrollNotification>` 监听 `ScrollUpdateNotification`，取 `(notification.metrics as PageMetrics).page!.round()`，仅在 `currentPage != _lastReportedPage` 时触发。即"页面中心切换"语义，**不是**手指抬起时才触发。

---

## 6. Controller / 编程式跳转

`ExtendedPageController extends _PageController extends ScrollController`（`page_controller/page_controller.dart:3` + `page_controller/official.dart:9`）。

构造（`page_controller.dart:4-10`）:

```dart
ExtendedPageController({
  int initialPage = 0,
  bool keepPage = true,
  double viewportFraction = 1.0,
  bool shouldIgnorePointerWhenScrolling = false,  // 滚动动画期是否屏蔽指针
  double pageSpacing = 0.0,                       // 页间留白（逻辑像素）
});
```

继承自父类的方法（`page_controller/official.dart:82,104,119,130`）:
- `Future<void> animateToPage(int page, {required Duration duration, required Curve curve})`
- `void jumpToPage(int page)`
- `Future<void> nextPage({required Duration duration, required Curve curve})`
- `Future<void> previousPage({required Duration duration, required Curve curve})`

可视化属性: `controller.page` (double) / `controller.position` 一并可用。

---

## 7. 官方完整示例（≤50 行版本）

来源 `/tmp/extended_image_research/example/lib/pages/simple/photo_view_demo.dart`（已剔除路由注解与样板）：

```dart
class _SimplePhotoViewDemoState extends State<SimplePhotoViewDemo> {
  final List<String> images = [/* 7 张网络 URL */];
  final List<int> _cachedIndexes = <int>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloadImage(1);  // 预热第二张
  }

  void _preloadImage(int index) {
    if (_cachedIndexes.contains(index)) return;
    if (0 <= index && index < images.length) {
      precacheImage(
        ExtendedNetworkImageProvider(images[index], cache: true),
        context,
      );
      _cachedIndexes.add(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ExtendedImageGesturePageView')),
      body: ExtendedImageGesturePageView.builder(
        controller: ExtendedPageController(
          initialPage: 0,
          pageSpacing: 50,
        ),
        onPageChanged: (int page) {
          _preloadImage(page - 1);
          _preloadImage(page + 1);
        },
        itemCount: images.length,
        itemBuilder: (BuildContext context, int index) {
          return ExtendedImage.network(
            images[index],
            fit: BoxFit.contain,
            mode: ExtendedImageMode.gesture,
            initGestureConfigHandler: (ExtendedImageState state) {
              return GestureConfig(
                inPageView: true,            // 必须 true
                initialScale: 1.0,
                maxScale: 5.0,
                animationMaxScale: 6.0,
                initialAlignment: InitialAlignment.center,
              );
            },
          );
        },
      ),
    );
  }
}
```

对应 `ExtendedImage.memory` 场景（用户用例）只需把 `ExtendedImage.network(url, ...)` 替换为 `ExtendedImage.memory(Uint8List bytes, ...)`，其余参数完全相同。完整复杂版（含 `ExtendedImageSlidePage` 下拉关闭 + 详情面板）位于 `/tmp/extended_image_research/example/lib/common/widget/pic_swiper.dart`。

---

## 关键注意事项

- **`inPageView: true` 是 PV 协调的开关** —— 漏写会失去 Q2 的边缘溢出行为。
- **`preloadPagesCount` 在 `ExtendedImageGesturePageView` 上层不可用**，必须走 `precacheImage`。
- **桌面鼠标翻页**未被官方明确测试，迁移时建议在 macOS/Linux/Windows 三端手测；如有问题可外包一层自定义 `ScrollBehavior` 扩展 `dragDevices`。
- **`physics` 参数**会被强制 `NeverScrollableScrollPhysics().applyTo(yourPhysics)` 包装（`gesture_page_view.dart:51-54`），传 `BouncingScrollPhysics()` 只是为了让 fling 行为生效而非接管拖动。
- **`canScrollPage` ≠ canScale** —— 前者控翻页（看 `GestureDetails`），后者控缩放（`ExtendedImageGesture` 构造参数 `canScaleImage`，见 `pic_swiper.dart:518`）。

## 参考源码定位（全部为绝对路径）

- `/tmp/extended_image_research/lib/src/gesture/page_view/gesture_page_view.dart`
- `/tmp/extended_image_research/lib/src/gesture/page_view/widgets/page_view.dart`
- `/tmp/extended_image_research/lib/src/gesture/page_view/page_controller/page_controller.dart`
- `/tmp/extended_image_research/lib/src/gesture/gesture.dart`
- `/tmp/extended_image_research/lib/src/gesture/utils.dart`
- `/tmp/extended_image_research/lib/src/gesture_detector/drag_gesture_recognizer.dart`
- `/tmp/extended_image_research/example/lib/pages/simple/photo_view_demo.dart`
- `/tmp/extended_image_research/example/lib/common/widget/pic_swiper.dart`

GitHub: <https://github.com/fluttercandies/extended_image> (v10.0.1, sdk: ">=3.7.0 <4.0.0", flutter: ">=3.29.0")
