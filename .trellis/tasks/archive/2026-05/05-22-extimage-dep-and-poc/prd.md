# ST1: PoC + 依赖锁图 (extended_image: ^10.0.1)

> **Parent**: `05-22-brainstorm-fullscreen-preview-extended-image`
> **Role**: Risk gate —— 验证 3 个红旗，决定后续 ST2/ST3/ST4 是否安全推进 Approach A
> **入口契约**: 父 PRD `Implementation Plan` 中的 ST1 段（"extended-image-dep-and-poc"）

## Goal

把 `extended_image: ^10.0.1` 引入项目依赖，做最小 PoC 代码，**验证 3 个红旗**:

- **(a)** GitHub issue **#736** "drag-to-dismiss + GesturePageView 组合脆弱" 在我们多图画廊
  用例下是否真实复现（Android 实机/模拟器 + iOS 模拟器）
- **(b)** GitHub issue **#761** "v10.0.1 iOS `.memory + BoxFit.contain`" 在我们的
  内存解码图片上是否受影响
- **(c)** **桌面 mouse drag 翻页** — 在 macOS / Windows / Linux 上能否正常用鼠标拖动画廊
  切页，是否需要额外的 `ScrollConfiguration(behavior with dragDevices: ...)` 注入

3 个红旗全部通过 → 后续 ST2/ST3/ST4 安全推进；任一复现 → 在 `poc-report.md`
明确标记 + 建议主 session 降级到 Approach B（保留外层 GestureDetector + 自实现
100dp 阈值）。

## Requirements

* **R1**: 在 `pubspec.yaml` `dependencies:` 区段加入 `extended_image: ^10.0.1`，
  插入位置紧邻现有图片相关包（如 `image: ^4.3.0` / `image_picker: ^1.1.2`）。
* **R2**: `flutter pub get` 干净解算；`flutter pub deps | grep extended_image`
  确认锁图。如出现任何 SAT 冲突 / 版本范围警告，立即停止并报告。
* **R3**: 创建 PoC widget 文件 `lib/_poc/extended_image_poc.dart`（命名空间
  以 `_poc/` 标记临时性质），导出一个独立 widget `ExtendedImagePoc`，**不**进入
  正式调用链。该 widget 必须演示完整三件套:
  * `ExtendedImageGesturePageView.builder` (3 张内存 PNG / JPG，硬编码或从
    `assets/icon/` 复用)
  * `ExtendedImage.memory(..., mode: ExtendedImageMode.gesture,
    initGestureConfigHandler: ...)` 配 `GestureConfig(inPageView: true, minScale: 1.0,
    maxScale: 4.0)`
  * `ExtendedImageSlidePage` 外层包裹 + `slideEndHandler` (100dp / 800dp/s) +
    `slidePageBackgroundHandler` (1.0→0.4 opacity)
  * 透明 `PageRouteBuilder(opaque: false, ...)` 入口
* **R4**: PoC widget 必须从 `main.dart` 或现有路由可访问（例如临时在 `MyApp`
  里加一个调试入口 / 或在 `lib/main.dart` 里加 `--dart-define=POC=1` flag 路径）。
  完成后**保留**该入口，由 ST4 在最后清理。
* **R5**: 在至少 1 移动平台 + 1 桌面平台手动验证 3 个红旗，把 verdict 写入
  `.trellis/tasks/05-22-extimage-dep-and-poc/poc-report.md`。报告必须包含:
  * 测试环境（platform / Flutter version / 设备型号）
  * 红旗 (a) #736 verdict + 复现步骤 / 通过证据
  * 红旗 (b) #761 verdict + 复现步骤 / 通过证据
  * 红旗 (c) 桌面 mouse drag verdict + 复现步骤 / 通过证据
  * 最终结论：3/3 通过 → 推进 Approach A；任一复现 → 标记建议切 Approach B
* **R6**: `flutter analyze` 0 issue（含 PoC 文件）；`dart format` 0 file。

## Acceptance Criteria

* [ ] `pubspec.yaml` 含 `extended_image: ^10.0.1`
* [ ] `flutter pub get` 干净解算（exit 0，无 SAT 冲突）
* [ ] `flutter pub deps | grep extended_image` 显示 10.0.1 在 lock graph 中
* [ ] `lib/_poc/extended_image_poc.dart` 存在并实现 R3 三件套
* [ ] PoC 入口可从 `main.dart` 访问（具体方式由实施者决定）
* [ ] `flutter analyze` 0 issue
* [ ] `dart format --set-exit-if-changed .` 0 file
* [ ] `poc-report.md` 写完，3 个红旗 verdict 明确
* [ ] 报告最末给出"Approach A 推进 / 切到 Approach B"明确建议

## Definition of Done

* Tests: PoC 不要求单元测试（PoC 是临时验证用途，ST2/ST3 会被正式重写测试覆盖）
* Lint / typecheck: 全绿
* PoC 报告写完且建议明确
* 不修改既有 `preview_full_screen_dialog.dart` / `preview_thumbnail.dart`（那是
  ST2 / ST3 的工作）

## Out of Scope

* 不删除现有 `_ImmersivePageScrollPhysics` 等老实现
* 不修改 `preview_full_screen_dialog.dart` / `preview_thumbnail.dart`
* 不重写既有测试（ST4 的工作）
* 不写新 ADR（ADR-0002 是 ST4 的工作）
* 不连带替换 PreviewThumbnail / grid / stitch 等其它图片显示场景

## Technical Notes

* 父 PRD: `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/prd.md`
* 关键 research:
  * `research/extended_image-overview.md` (锁图分析)
  * `research/extended_image-gallery-api.md` (Gallery API + 桌面 mouse drag 警告)
  * `research/extended_image-gesture-and-slide.md` (SlidePage + GestureConfig 三件套)
* 依赖政策: `.trellis/spec/frontend/dependencies-and-platforms.md` ("Verify
  lock-graph compatibility")
* PoC 命名空间约定: `lib/_poc/` 前缀 + `// TODO(ST4): remove after migration` 注释
  方便 ST4 阶段批量清理
