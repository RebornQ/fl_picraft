# export-preview-fullscreen-immersive

## Goal

把导出界面 `PreviewFullScreenDialog` 升级为 **沉浸式照片查看器**：

1. **背景全屏 + 纯黑**：内容延伸到状态栏 / 底部系统导航 / iOS home indicator 区，背景固定 `Colors.black`，不跟随主题
2. **AppBar 透明叠加 + 单击切显隐**：保留关闭按钮 / 标题，但作为悬浮层，单击图片区切显隐
3. **统一手势契约（单图 / 多图共用）**：
   * `minScale = 1.0`（缩小不能小于原始大小）
   * 未放大（`scale == 1.0`）→ 禁用 pan
   * 已放大（`scale > 1.0`）→ 启用自由 pan
   * 双击未放大 → 平滑放大到目标倍数（以双击点为锚）
   * 双击已放大 → 平滑复位到 1.0
   * 双指 pinch zoom 与双击不冲突（手势 arena 自动仲裁）
4. **多图左右滑动切换**：当 `bytes.length > 1` 时全屏预览支持 PageView 左右切页
   * 未放大 → 横向滑动切换上一 / 下一张
   * 已放大 → PageView 禁用（横向手势归还给 InteractiveViewer 做 pan）
   * AppBar / 关闭按钮 / 页面指示器 (`2 / 5`) 仍可点击

## What I already know

* 目标文件：
  * `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`（主改）
  * `lib/features/export/presentation/widgets/preview_thumbnail.dart`（入口改：传整个 bytes 列表 + 当前 index）
  * `lib/features/export/presentation/widgets/preview_card.dart`（_ReadyView 多图分支改：把整个列表传给每个 thumbnail）
* 现有测试：
  * `test/features/export/presentation/widgets/preview_full_screen_dialog_test.dart`（**含 `minScale: 0.5` 断言，需更新为 1.0**）
* 现状：
  * Dialog 只接收单 `Uint8List bytes`，无法切页
  * `InteractiveViewer.minScale: 0.5`、`panEnabled: true` 始终为 true
  * 无双击 / 单击 / 切页交互

## Assumptions

* 双击放大目标倍数 = **2.0x**（业界主流：iOS 相册 / Google Photos 都是 2x；maxScale 保持 4.0x 不变，2.0x 让双击后仍有 pinch 余地）
* 双击放大焦点 = **双击点**（不是图片中心，符合主流体验）
* 切页时**不**自动重置上一页的 transformation（但因切页只在 `scale == 1.0` 时可发生，切回去看到的也是 1.0）
* PageView 顺序 = `_ReadyView` 中 `bytes` 列表的顺序（即 grid 的扫描顺序）
* 多图时 AppBar 标题显示 `{i+1} / {total}` 取代固定的 "预览"
* 不引入新依赖（不引入 `photo_view` 包）

## Requirements

### R1: 全屏黑底 + 透明 chrome

* `Dialog.fullscreen(backgroundColor: Colors.black)`
* `Scaffold(backgroundColor: Colors.black, extendBody: true, extendBodyBehindAppBar: true)`
* `AppBar(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, foregroundColor: Colors.white, systemOverlayStyle: SystemUiOverlayStyle.light)`

### R2: tap-to-toggle chrome + 自动隐藏 + 常驻浮动关闭按钮

* 单击图片区 → AppBar 渐入渐出（≈ 200 ms `AnimatedSlide + AnimatedOpacity`）
* **自动隐藏**：进入 dialog 时 chrome 默认可见，**3 秒后**自动隐藏（Timer）；用户单击恢复 chrome 时，**重置** Timer
* 隐藏时**不**联动隐藏系统栏（规避 SystemChrome 恢复风险；黑底状态栏融入背景）
* **常驻浮动关闭按钮**：在 Scaffold body 上方叠加 `Positioned(top: safeTop + 8, left: 8)` 一个圆形半透明黑底 + 白 X 的 IconButton；**不**跟随 `_chromeVisible` toggle，永远可点击
* **AppBar 在 body Stack 内（不放 Scaffold.appBar）**：实施期发现 `Scaffold.appBar` 槽位的 `Material` 即使 `color: transparent` 也会吸收 hit-test，导致下层常驻浮动 X 在 AppBar 显示态下无法接收 tap。最终方案：把 AppBar 作为 body Stack 的一员，用 `Positioned(top: 0, left: 0, right: 0) + IgnorePointer(ignoring: !_chromeVisible) + AnimatedSlide + AnimatedOpacity` 包裹；浮动 X 放在 AppBar 同级的另一个 `Positioned`，永远位于 Stack 顶层。AppBar 内 `automaticallyImplyLeading: false` 不放 leading X，只显示居中标题。

### R3: 统一手势契约

* `InteractiveViewer.minScale = 1.0`、`maxScale = 4.0`、`boundaryMargin = EdgeInsets.all(double.infinity)`
* `panEnabled` 动态：`scale == 1.0 → false`；`scale > 1.0 → true`（通过 `TransformationController.addListener` 监听 + `setState`）
* 双击放大 / 复位：
  * 用 `onDoubleTapDown` 捕获 `localPosition`
  * **留白区容错**：检测双击点是否在 `BoxFit.contain` 后图片实际渲染矩形内；不在 → 用图片中心代替双击点（避免图片"跳出 viewport"）
  * 当前 `scale ≈ 1.0`（小于等于 1.01）→ 放大到 **2.0x**，以（修正后的）双击点为锚
  * 否则 → 复位到 identity
  * 通过 `AnimationController(250 ms) + Matrix4Tween + Curves.easeOutCubic` 平滑插值

### R4: 多图切页（含边缘弹切 / Photo-gallery 风）

* Dialog 入参从 `Uint8List bytes` 改为 `List<Uint8List> bytes` + `int initialIndex`
* 用 `PageView.builder` 横向布局，每页一个独立的 `_PreviewPage` widget（StatefulWidget，自持 `TransformationController` + `AnimationController`）
* **PageView physics**：使用**自定义 `_ImmersivePageScrollPhysics extends PageScrollPhysics`**，根据当前页 `_PreviewPage` 的 InteractiveViewer 状态决定是否允许 scroll：
  * 当前页 `scale ≈ 1.0`（未放大）→ physics 行为 = 标准 `PageScrollPhysics`（可切页）
  * 当前页 `scale > 1.0` 且**未触底**（图片在水平方向仍有 pan 余量）→ physics 拒绝 user offset（手势归 InteractiveViewer 做 pan）
  * 当前页 `scale > 1.0` 且**已触底**（图片已 pan 到左 / 右边缘）且拖动方向"向外"（向左 pan 已到右边缘 / 向右 pan 已到左边缘）→ physics 接管剩余 delta，平滑过渡到邻页（剩余 drag delta 自然推动 PageView offset）
* "触底" 判定算法：
  * `imageRenderedWidth = imageDisplayWidth * scale`（`imageDisplayWidth` 是 BoxFit.contain 决定的图片实际显示宽度）
  * 当前 matrix 的 translation.x = `tx`，viewport 宽 = `vw`
  * 左边缘触底：`tx >= maxTx`，其中 `maxTx ≈ (imageRenderedWidth - imageDisplayWidth) / 2`（matrix translation 已经到了左极限）
  * 右边缘触底：`tx <= -maxTx`
  * Tolerance：±0.5 px 容差，避免浮点误差
* 通信机制：父级 `_PreviewFullScreenDialogState` 维持 `_currentZoomed` + `_currentHorizontalEdge`（`EdgeState { atLeft, atRight, free }`）；`_PreviewPage` 通过 `TransformationController.addListener` 计算并回调父级
* AppBar 标题：
  * `bytes.length == 1` → `'预览'`
  * `bytes.length > 1` → `'${current + 1} / ${bytes.length}'`
* `PreviewThumbnail` 新增可选参数 `List<Uint8List>? allBytes` + `int initialIndex`；单图入口（stitch）传 null（退化）；多图入口（grid）传整个列表 + 当前 index

### R5: 入口侧适配

* `preview_card.dart` 的 `_ReadyView`：
  * 单图分支 不动（`PreviewThumbnail(bytes: bytes.first)`）
  * 多图分支 改为 `PreviewThumbnail(bytes: bytes[index], allBytes: bytes, initialIndex: index, semanticLabel: '...')`
* `PreviewThumbnail._openFullScreen` 把 `barrierDismissible: true` 改为 `false`（全屏 dialog 无屏障区可点，true 是死代码——明示语义）

### R6: 向下拖关闭手势

* **激活条件**：仅当当前页 `scale ≈ 1.0`（未放大）时启用；放大态禁用（避免和 InteractiveViewer 垂直 pan 冲突）
* 手势：外层 `GestureDetector(onVerticalDragStart / Update / End)`
* 拖动反馈：
  * `onVerticalDragUpdate`：累计 `deltaY`（仅向下，向上 clamp 到 0）
  * Scaffold body 整体 `Transform.translate(Offset(0, deltaY))`
  * 背景透明度：`opacity = (1.0 - deltaY / dragThreshold * 0.6).clamp(0.4, 1.0)`，让用户看到背景透出
* 释放：
  * `deltaY > 100` dp 或 fling velocity > 800 dp/s 向下 → `Navigator.pop()`
  * 否则 → 250 ms 弹回 `deltaY = 0`（带 `Curves.easeOutCubic`）
* **不**同时支持向上拖关闭（避免与系统手势冲突）

## Acceptance Criteria

* [ ] **R1**：`Scaffold.backgroundColor == Colors.black`、`extendBody*` 全开、AppBar 透明 + 浅色状态栏
* [ ] **R2**：进入默认 chrome 可见；**3 秒后自动隐藏**（Timer）；单击图片区切显隐；恢复时重置 Timer；动画 ≈ 200 ms
* [ ] **R2-close**：常驻浮动 X 按钮在 `Positioned(top: safeTop + 8, left: 8)`，**不**跟随 chrome toggle，永远可点击
* [ ] **R3a**：`InteractiveViewer.minScale == 1.0`
* [ ] **R3b**：未放大时尝试 pan 不生效；放大后可自由 pan
* [ ] **R3c**：双击未放大 + 双击点在图片渲染矩形内 → 200~300 ms 内 `TransformationController.value.getMaxScaleOnAxis()` 接近 2.0；锚点位于双击坐标
* [ ] **R3c2**：双击未放大 + 双击点在留白区 → 锚点回退到图片中心（图片中心放大到 2.0x，不跳出 viewport）
* [ ] **R3d**：双击已放大 → 200~300 ms 内 `TransformationController.value == Matrix4.identity()`
* [ ] **R3e**：双指 pinch 后双击仍可复位（手势不冲突）
* [ ] **R4a**：单图入口 dialog 显示 `'预览'`；多图入口显示 `'X / Y'`
* [ ] **R4b**：多图未放大 → 横向 drag 切页；指示器同步更新
* [ ] **R4c**：多图已放大 + 未触底 → 横向 drag 触发 pan，不切页
* [ ] **R4d**：多图已放大 + 已触底 + 拖动方向"向外" → drag delta 平滑驱动 PageView，过渡到邻页（拖动过程中可见邻页边缘从屏幕外滑入，主流相册体验）
* [ ] **R4e**：切到新页后，新页的 `_PreviewPage` 初始 transformation = identity（PageView.builder 默认 dispose 离屏 page 保证）
* [ ] **R4f**：**常驻浮动关闭按钮**在 `_chromeVisible == false` 时仍可点击
* [ ] **R5a**：`preview_card.dart` `_ReadyView` 多图分支传 `allBytes + initialIndex`；单图分支不变
* [ ] **R5b**：`PreviewThumbnail._openFullScreen` 的 `barrierDismissible` 改为 `false`（全屏 dialog 无屏障区，明示语义）
* [ ] **R6a**：未放大态垂直向下拖动 → Scaffold body translateY 跟手 + 背景透明度按 deltaY 渐变（0.4 ~ 1.0）
* [ ] **R6b**：释放时 `deltaY > 100` 或 fling 速度 > 800 dp/s 向下 → pop dialog
* [ ] **R6c**：释放时未达阈值 → 250 ms 弹回 identity
* [ ] **R6d**：放大态（scale > 1.01）垂直拖动 → 触发 InteractiveViewer pan，**不**触发关闭手势
* [ ] 既有测试更新通过（`minScale: 0.5` → `1.0`；测试 harness 接受 `List<Uint8List>`）
* [ ] 新增至少 6 个针对性 widget 测试（R1/R2/R3b/R3c-d/R4b/R4c）
* [ ] `flutter analyze` 干净；`dart format .` 已应用

## Definition of Done

* `flutter test` 通过
* `flutter analyze` clean
* `dart format .` 应用过
* 不引入新依赖
* `PreviewFullScreenDialog` / `PreviewThumbnail` 的 dartdoc 完整描述新契约
* 在 stitch / grid 两条预览路径都人工试验过手势与切页

## Out of Scope

* 不动 stitch 预览（始终单图，但**也用新手势契约**——只是不显示页码 + 无 PageView 切页）
* 不做"双击 1x → 2x → 复位"的三态切换；只有"≤ 1.01 / > 1.01"两态
* 不做长按 / 旋转 / 分享手势
* 不做 hero 动画 / shared element transition
* 不联动隐藏系统栏（状态栏 / 底部导航条全程可见）
* 不抽通用 `ImmersiveViewer` 组件
* 不处理 landscape 旋转、不处理 notch 内 chrome 避让
* 不更换关闭按钮位置 / 不加自定义页面指示器（保持在 AppBar title）

## Technical Approach

### Dialog 结构

```dart
class PreviewFullScreenDialog extends StatefulWidget {
  const PreviewFullScreenDialog({
    super.key,
    required this.bytes,
    this.initialIndex = 0,
  });
  final List<Uint8List> bytes;
  final int initialIndex;
}

class _PreviewFullScreenDialogState extends State<PreviewFullScreenDialog> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _chromeVisible = true;
  bool _currentZoomed = false;  // 当前页 scale > 1.01

  void _onZoomChanged(int index, bool zoomed) {
    if (index != _currentIndex) return;
    if (zoomed != _currentZoomed) setState(() => _currentZoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(context),
        body: PageView.builder(
          controller: _pageController,
          physics: _currentZoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: widget.bytes.length,
          onPageChanged: (i) => setState(() {
            _currentIndex = i;
            _currentZoomed = false;  // 切到新页默认未放大
          }),
          itemBuilder: (_, i) => _PreviewPage(
            bytes: widget.bytes[i],
            isCurrent: i == _currentIndex,
            onZoomChanged: (z) => _onZoomChanged(i, z),
            onTap: _toggleChrome,
          ),
        ),
      ),
    );
  }
}
```

### `_PreviewPage` 内部

```dart
class _PreviewPage extends StatefulWidget {
  const _PreviewPage({
    required this.bytes,
    required this.isCurrent,
    required this.onZoomChanged,
    required this.onTap,
  });
  final Uint8List bytes;
  final bool isCurrent;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;
}

class _PreviewPageState extends State<_PreviewPage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _tc;
  late final AnimationController _anim;
  Animation<Matrix4>? _resetTween;
  Offset _lastDoubleTapPos = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc = TransformationController()..addListener(_onMatrixChanged);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      if (_resetTween != null) _tc.value = _resetTween!.value;
    });
  }

  void _onMatrixChanged() {
    final scale = _tc.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged(zoomed);
    }
  }

  void _handleDoubleTapDown(TapDownDetails d) {
    _lastDoubleTapPos = d.localPosition;
  }

  void _handleDoubleTap() {
    final current = _tc.value;
    final target = _zoomed
        ? Matrix4.identity()
        : _zoomTo(2.0, _lastDoubleTapPos);
    _resetTween = Matrix4Tween(begin: current, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _anim
      ..reset()
      ..forward();
  }

  Matrix4 _zoomTo(double scale, Offset focal) {
    return Matrix4.identity()
      ..translate(-focal.dx * (scale - 1), -focal.dy * (scale - 1))
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: InteractiveViewer(
        transformationController: _tc,
        panEnabled: _zoomed,       // 未放大 → 禁 pan
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: Center(
          child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}
```

### AppBar

```dart
PreferredSize(
  preferredSize: const Size.fromHeight(kToolbarHeight),
  child: IgnorePointer(
    ignoring: !_chromeVisible,  // 隐藏期间不拦截图片区点击
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _chromeVisible ? 1.0 : 0.0,
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: Text(widget.bytes.length > 1
              ? '${_currentIndex + 1} / ${widget.bytes.length}'
              : '预览'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  ),
);
```

### `PreviewThumbnail` 入口改造

```dart
class PreviewThumbnail extends StatelessWidget {
  const PreviewThumbnail({
    super.key,
    required this.bytes,
    this.semanticLabel,
    this.allBytes,         // 多图：整个列表
    this.initialIndex = 0, // 多图：当前 index
  });
  final Uint8List bytes;
  final String? semanticLabel;
  final List<Uint8List>? allBytes;
  final int initialIndex;

  void _openFullScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PreviewFullScreenDialog(
        bytes: allBytes ?? [bytes],
        initialIndex: allBytes != null ? initialIndex : 0,
      ),
    );
  }
  // ... rest unchanged
}
```

### `preview_card.dart` 调整

仅多图分支：

```dart
PreviewThumbnail(
  bytes: bytes[index],
  allBytes: bytes,                                  // 新增
  initialIndex: index,                              // 新增
  semanticLabel: '预览图片 ${index + 1} / ${bytes.length}',
);
```

### 手势 arena 冲突分析

* `GestureDetector(onTap, onDoubleTap, onDoubleTapDown)` 注册 `TapGestureRecognizer + DoubleTapGestureRecognizer`
* `InteractiveViewer` 内部注册 `ScaleGestureRecognizer`（含 pan + pinch）
* `PageView` 注册水平 `DragGestureRecognizer`
* 仲裁：
  * 单击 / 双击 → tap recognizer 胜（其他 recognizer 不会因为单点触摸触发）
  * 双指 pinch → scale recognizer 胜（tap 因为双指立即失败）
  * 未放大 + 单指横向拖 → PageView 胜（InteractiveViewer pan 被 `panEnabled: false` 禁用，scale recognizer 仍会注册 pan 移动但因 panEnabled=false 不消费 → PageView 横向 recognizer 胜出）
  * 已放大 + 单指拖 → PageView physics 已切换为 `NeverScrollableScrollPhysics`，不注册 recognizer → InteractiveViewer scale recognizer 胜（pan）

  > Risk：`scaleEnabled` 始终为 true，单指 drag 在 `panEnabled: false` 时仍可能被 ScaleGestureRecognizer 跟踪。需要在实现期验证：未放大时单指横向拖确实切页而非被 InteractiveViewer "吃掉"。如果有问题，备选方案：在未放大时把 InteractiveViewer 包成 `IgnorePointer + Image`（但会失去 pinch zoom 触发能力——退一步在未放大时仍允许 pinch 但禁 pan）。

## Decision (ADR-lite)

* **Context**: 用户需要主流照片查看器级别的沉浸式 + 多图切页交互
* **Decision**: 单 `PageView` + 每页独立 `_PreviewPage(StatefulWidget)` + 通过 `TransformationController.addListener` 把缩放状态 + **水平边缘状态**汇报到父级，父级用**自定义 `_ImmersivePageScrollPhysics`** 实现 photo-gallery 风格的"边缘弹切"（pan 到边缘后剩余 delta 自然过渡为切页）；双击以双击点为锚放大到 2.0x；未放大禁 pan；最小缩放 = 1.0；不联动系统栏
* **详细 ADR**：
  * `docs/adr/0001-immersive-page-scroll-physics.md` — 自定义 ScrollPhysics 实现"边缘弹切"
  * `docs/adr/0002-five-gesture-layering.md` — 5 个手势的分层架构与 arena 仲裁
* **"切页 ⇔ 复位" 契约**（用户明示要求）：用户必须先把当前页复位到 `scale == 1.0` 才能横滑切到邻页。此契约由两层机制天然保证，**无需额外代码**：
  1. PageView physics 跟随 `_currentZoomed` 切换 —— 放大期间是 `NeverScrollableScrollPhysics`，横滑被拒
  2. `PageView.builder` 默认在离屏时 dispose 远端 page —— 用户切到新页时，旧页的 `_PreviewPage` 销毁，TransformationController 一并销毁；切回时新 build 的 `_PreviewPage` 初始 transformation = identity，无需主动 reset
* **Consequences**:
  * `PreviewFullScreenDialog` API breaking change：单图入参从 `Uint8List` → `List<Uint8List>`（用最简的 `[bytes]` 兼容旧调用方）
  * 测试 harness 必须更新（`minScale 0.5 → 1.0`、构造参数变化）
  * 多页内存：每个 `_PreviewPage` 持有 controllers，`PageView.builder` 默认只 build 当前页 + 缓存 1 个邻页，可接受
  * 单指横向拖在未放大时由 PageView 接管 —— 上面 Risk 段已标注，实现期需验证

## Open Questions

* (none — 待用户确认)

## Technical Notes

* 新引入 import：`package:flutter/services.dart`（`SystemUiOverlayStyle`）
* 不需要 `trellis-research`：手势模式皆为 Flutter 标准 API
* 测试需要 `pumpAndSettle` 处理多个动画（chrome toggle 200 ms + zoom 250 ms + page change physics）
* 涉及 spec：`.trellis/spec/frontend/component-guidelines.md`（StatefulWidget 命名 / lifecycle）、`.trellis/spec/frontend/state-management.md`（局部 UI 状态用 setState，无需 Riverpod）
