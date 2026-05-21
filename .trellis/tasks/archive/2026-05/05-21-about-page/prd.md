# 新增关于页面

## Goal

为 fl_picraft 应用新增一个「关于」页面，向用户展示应用基本信息（图标、名称、副标题、版本）、开源依赖致谢、项目源码与问题反馈入口。需求来源：用户希望让设置模块具备完整的产品信息可见性。

## Glossary（本任务相关术语）

* **关于（About）**：从设置页进入的产品信息展示页，承载「应用元信息 + 开源致谢 + 外部资源入口」三类内容。**不**承载用户偏好设置（属于 Settings 域）。
* **应用元信息（App Info）**：应用名、应用描述、版本号、应用图标、官方外链 URL 的集合。代码中聚合为 `class AppInfo`。
* **Settings 域**：用户偏好与应用行为配置（暗色模式 / 默认导出格式 / 语言等）。当前 stub，未来填充。
* **About 域**：独立 feature `features/about/`。Settings 仅持有进入 About 的入口 ListTile，**不**直接持有 About 的内容代码。

## What I already know

* **设置页面当前状态**：`lib/features/settings/presentation/screens/settings_screen.dart` 仍是 stub，body 只有一个 `PlaceholderBody("设置项即将推出。")`，目前没有任何真实设置项 — 是介入设置页结构的合适时机。
* **路由结构**：`lib/app/router.dart` 使用 `StatefulShellRoute.indexedStack`，`/settings` 注册在第 4 个 branch（`_settingsNavigatorKey`），其内嵌 `Navigator` 可承载子路由（如 `/settings/about`）。
* **应用元信息**：`pubspec.yaml` → `name: fl_picraft`, `version: 1.0.0+1`，`description: A picture craft for Flutter project.`；`app.dart` 中 `title: 'Fl PiCraft'`。
* **设计系统**：Material 3 主题（`lib/app/theme/app_theme.dart`），遵循 `.trellis/spec/frontend/component-guidelines.md`。
* **现有平台图标资源**：仅在原生平台（`android/app/src/main/res/mipmap-*/ic_launcher*.webp`、`ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`），Flutter 端没有 `assets/` 目录，pubspec 的 `assets:` 部分尚未启用。`mipmap-xxxhdpi/ic_launcher.webp` 是最大可用尺寸（192×192，hasAlpha=true，已烘焙 launcher 圆角）。
* **现有依赖**：未引入 `package_info_plus` 和 `url_launcher`。
* **既有命名规范**（grill 后确认）：
  - **聚合常量**：`class Breakpoints`、`class MenuChannel`、`class AppNavDestination` —— 一组紧密相关的常量用 class + `static const` 聚合。
  - **顶层 kXxx 常量**：`kIsolatePixelThreshold`、`kDefaultSubtitleBandHeightPercent` —— 适合**独立的领域阈值**。
  - **AppBar title**：项目全部纯中文（`'设置'`、`'导出'`、`'预览'`、`'长图拼接'`、`'清空已选图片'`）。
  - **路由 name**：扁平、全局唯一（`home / stitch / grid / settings / export`）。
* **响应式规范**（`.trellis/spec/frontend/responsive-layout.md`）：top-level screen 不在最外层 cap maxWidth（fill the container），但**内部具体组件**可以 `Center + ConstrainedBox(maxWidth: ...)` 限宽以避免 ultra-wide window 上的视觉空洞。

## Decisions (confirmed via grill)

### D1 — 域边界与目录组织
* **D1.1**：About 是**独立 feature**，新建 `lib/features/about/presentation/screens/about_screen.dart`。Settings 仅在 `settings_screen.dart` 内放置「关于」入口 ListTile，**不**持有 About 内容代码。
* **D1.2**：路由 path 保持 `/settings/about`（语义上"从设置进入"），但 builder 引用 `features/about/` 下的 `AboutScreen`。挂在 settings branch 下的 `GoRoute(path: 'about', name: 'about', builder: ...)`。

### D2 — 常量聚合（命名规范）
* **D2.1**：所有应用元信息常量聚合到 `lib/core/constants/app_info.dart` 的 `class AppInfo`：
  ```dart
  class AppInfo {
    AppInfo._();

    static const String name = 'Fl PiCraft';
    static const String description = 'A picture craft for Flutter project.';
    static const String iconAssetPath = 'assets/icon/app_icon.webp';
    static const String gitHubRepoUrl = 'https://github.com/RebornQ/fl_picraft';
    static const String gitHubIssuesUrl = 'https://github.com/RebornQ/fl_picraft/issues';
  }
  ```
* **D2.2**：与 `class Breakpoints` 风格对齐 —— 私有构造函数 + `static const` 字段，禁止实例化。

### D3 — 文案统一
* **D3.1**：`SettingsScreen` 入口 ListTile title = `'关于'`；`AboutScreen` AppBar title = `'关于'`。两处文案完全一致，避免用户跨页面时的认知中断。
* **D3.2**：「关于」入口 ListTile：`leading: Icon(Icons.info_outline)`、`trailing: Icon(Icons.chevron_right)`。
* **D3.3**：AboutScreen 三个外链/操作 ListTile 采用 **title + subtitle 双行结构**，subtitle 显示目标 URL（去掉 `https://` 协议前缀），让用户在点击前明确目标：

  | 顺序 | title | subtitle | leading icon | 行为 |
  |---|---|---|---|---|
  | 1 | 项目源码 | `github.com/RebornQ/fl_picraft` | `Icons.code` | 外部浏览器打开 `AppInfo.gitHubRepoUrl` |
  | 2 | 问题反馈 | `github.com/RebornQ/fl_picraft/issues` | `Icons.bug_report_outlined` | 外部浏览器打开 `AppInfo.gitHubIssuesUrl` |
  | 3 | 开源许可 | （不设 subtitle） | `Icons.description_outlined` | `showLicensePage(...)` |
* **D3.4** 顺序理由：产品 identity (源码) → 用户交互 (反馈) → 法律信息 (许可)，与 iOS Settings / 主流 Android 应用习惯一致。

### D4 — 图标展示
* **D4.1**：尺寸 **112×112 dp**（介于 Material 3 about 页常见的 96-128 dp 范围中段，与 launcher 实际尺寸接近）。
* **D4.2**：**不**额外加 `ClipRRect` —— 源文件 `ic_launcher.webp` 已经烘焙了透明 alpha 圆角形状。直接 `Image.asset(AppInfo.iconAssetPath, width: 112, height: 112)`。
* **D4.3**：资源路径 `assets/icon/app_icon.webp`（从 `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp` 复制）。pubspec `flutter.assets` 启用 `- assets/icon/`。

### D5 — 版本号展示
* **D5.1**：动态读取 `PackageInfo.fromPlatform()`（`package_info_plus` 提供），异步流程用 `FutureBuilder<PackageInfo>`（一次性异步无需 Riverpod Notifier）。
* **D5.2**：展示格式：
  - 通用情况：`v{version}（build {buildNumber}）`，例：`v1.0.0（build 1）` —— 中文全角括号 + 中文 "build" 词混排，与项目 AppBar 中文风格协调。
  - 边界：`buildNumber` 为空（如 web 平台）时退化为 `v{version}`，省略括号。
* **D5.3**：在测试中通过 `PackageInfo.setMockInitialValues(...)` 注入固定值。

### D6 — License 弹窗参数
* **D6.1**：调用 `showLicensePage(context, applicationName: AppInfo.name, applicationVersion: <格式化版本号>, applicationIcon: <Image.asset 64×64>)`。
* **D6.2**：**不**传 `applicationLegalese` —— 项目无明确 copyright 文本，依靠 Flutter 自动收集的依赖 LICENSE 列表即可覆盖法律可见性。
* **D6.3**：弹窗内 applicationIcon 用 64×64（小于 about 页的 112×112，避免抢占弹窗空间）。

### D7 — 外链失败兜底
* **D7.1**：调用 `url_launcher` 前先 `canLaunchUrl(uri)`，失败或 launch 异常时通过 `ScaffoldMessenger.of(context).showSnackBar(...)`。
* **D7.2**：SnackBar 文案：`'无法打开链接，请检查网络或手动访问：' + 截断后的 URL`。
* **D7.3**：`LaunchMode.externalApplication`（避免 in-app webview 卡顿）。

### D8 — 响应式宽度
* **D8.1**：`AboutScreen` 的 Scaffold body **不**在最外层 wrap `ConstrainedBox` —— 遵循 `responsive-layout.md` 的"top-level screens fill the container"原则。
* **D8.2**：在 body 内部用 `Center + ConstrainedBox(maxWidth: 600)` 包裹"主内容列"（图标 + 文字 + ListTile Card），让 large 窗口（>1200 dp）下内容居中显示、不会铺满 1920 dp 宽度。
* **D8.3**：参考 `responsive-layout.md` 第 552-565 行的 "Gotcha: ConstrainedBox alone never centers" 示例代码。

### D9 — MVP 扩展
* **D9.1**：纳入 ① 问题反馈入口（GitHub Issues）、② 应用描述副标题。
* **D9.2**：**不**纳入长按复制版本号、邮件反馈、检查更新、隐私政策。

## Requirements

1. 在 `SettingsScreen` 中新增 ListTile：`leading: Icon(Icons.info_outline)`, `title: Text('关于')`, `trailing: Icon(Icons.chevron_right)`；点击触发 `context.push('/settings/about')`。
2. `AboutScreen` 落在 `features/about/presentation/screens/about_screen.dart`，竖向布局，主内容由 `Center + ConstrainedBox(maxWidth: 600)` 限宽：
   1. **应用图标**：`Image.asset(AppInfo.iconAssetPath, width: 112, height: 112)`，不加 ClipRRect。
   2. **应用名称**：`AppInfo.name`，`textTheme.headlineSmall`，居中。
   3. **副标题**：`AppInfo.description`，`textTheme.bodyMedium` + `colorScheme.onSurfaceVariant`，居中。
   4. **版本号**：`v{version}（build {buildNumber}）`（空 buildNumber 时省略括号），`textTheme.labelLarge` + `colorScheme.onSurfaceVariant`。`FutureBuilder<PackageInfo>` 加载中显示 `'v…'` 或空白占位。
   5. **分隔间距**：SizedBox 8 / 12 / 24 dp 三档；图标到名称 12 dp、名称到副标题 8 dp、副标题到版本号 12 dp、版本号到 Card 24 dp。
   6. **入口 Card**：包裹 `Column` 容纳三个 ListTile，顺序：项目源码 / 问题反馈 / 开源许可（subtitle、icon、行为见 D3.3）。
3. `AboutScreen` AppBar = `AppBar(title: const Text('关于'))`。
4. 浅色 / 深色主题双适配，颜色全部走 `Theme.of(context).colorScheme` 与 `textTheme`，**不**硬编码。
5. 外链点击：`canLaunchUrl` 失败或 launch 抛错 → 中文 SnackBar 提示（见 D7）。

## Acceptance Criteria

* [ ] 在 `/settings` 可看到「关于」入口（带 info_outline leading + chevron trailing），点击后到达 `/settings/about`，AppBar 显示「关于」。
* [ ] AboutScreen 顶部水平居中显示 112×112 dp 应用图标（来自 `assets/icon/app_icon.webp`），无 ClipRRect。
* [ ] 显示的应用名称 = `AppInfo.name` = 'Fl PiCraft'；副标题 = `AppInfo.description`。
* [ ] 版本号格式 = `v1.0.0（build 1）`（基于 pubspec `version: 1.0.0+1`），通过 `package_info_plus` 动态读取；构建时 `--build-name=2.0.0 --build-number=42` 覆盖后显示 `v2.0.0（build 42）`。
* [ ] Card 内 ListTile 顺序：项目源码 / 问题反馈 / 开源许可。前两项 subtitle 显示对应 URL（去 `https://` 前缀）。
* [ ] 点击「项目源码」/「问题反馈」打开外部浏览器到对应 URL；失败时显示中文 SnackBar。
* [ ] 点击「开源许可」打开 LicensePage，header 显示 64×64 图标、应用名、格式化版本号；可看到 Flutter / Riverpod / GoRouter 等所有依赖 LICENSE。
* [ ] 在 large (>1200 dp) 窗口下，主内容列宽度被限制在 600 dp，水平居中，不铺满。
* [ ] 浅色 / 深色主题切换正常，无写死颜色。
* [ ] `flutter analyze`、`dart format .`、`flutter test` 全部通过。

## Definition of Done

* Widget 测试：
  - `test/features/about/about_screen_test.dart`：覆盖应用名 / 描述 / 版本号占位（mock `PackageInfo`）/ 3 个 ListTile title + subtitle / 顺序。
  - `test/features/settings/settings_screen_test.dart`：覆盖「关于」入口存在 + tap 触发跳转（用 mock GoRouter 或验证 `context.push` 调用）。
* `flutter analyze`、`dart format .`、`flutter test` 全绿。
* AboutScreen 遵循 `.trellis/spec/frontend/component-guidelines.md` 的 const 构造、prop ordering、Scaffold + AppBar 结构。
* 仅引入 `package_info_plus` 与 `url_launcher` 两个新直接依赖。
* `pubspec.yaml` `flutter.assets` 段正确启用 `assets/icon/` 路径。
* `lib/core/constants/app_info.dart` 中 `class AppInfo` 私有构造，所有字段 `static const`。

## Out of Scope

* 检查更新 / 应用商店跳转。
* 隐私政策 / 用户协议页面（后续任务）。
* 邮件反馈入口（GitHub Issues 已覆盖反馈场景）。
* 长按复制版本号（本轮 expansion 未纳入）。
* Settings 域其他真实设置项的填充（保持本任务仅做关于入口的最小改动）。
* Build commit hash 注入（需要构建脚本协作，超出范围）。
* `applicationLegalese` 自定义文本（依靠 Flutter 自动收集的依赖 LICENSE）。
* 自定义 LICENSE 列表 UI（用内置 `showLicensePage`）。

## Technical Approach

### Architecture

* **新增 feature**：`lib/features/about/`，目录结构 `presentation/screens/about_screen.dart`（仅 presentation 层，无 data/domain — 关于页无业务实体）。
* **入口**：`lib/features/settings/presentation/screens/settings_screen.dart` 内将 `PlaceholderBody` 包到 `ListView` 顶部，下方追加「关于」`ListTile`（最小侵入；未来 settings 项继续 append）。
* **常量**：`lib/core/constants/app_info.dart` 暴露 `class AppInfo`。
* **外链 helper**：在 `AboutScreen` 内私有方法 `_launchExternal(BuildContext, String url)`，内含 `canLaunchUrl` 检查 + SnackBar 兜底。逻辑短小，无需提取到 core 层。

### Routing

* 在 `_settingsNavigatorKey` 的 branch 下追加 `GoRoute(path: 'about', name: 'about', builder: (context, state) => const AboutScreen())`，完整 location `/settings/about`。
* 入口跳转用 `context.push('/settings/about')`（子路由 push 语义，AppBar 自动 back button 返回 settings）。

### Version Label Composition

```dart
String formatAppVersion(PackageInfo info) {
  final v = info.version;            // e.g. '1.0.0'
  final b = info.buildNumber;        // e.g. '1' or '' on web
  return b.isEmpty ? 'v$v' : 'v$v（build $b）';
}
```

* 测试中通过 `PackageInfo.setMockInitialValues(appName: '...', packageName: '...', version: '1.0.0', buildNumber: '1', ...)` 注入。

### Dependencies

* `package_info_plus: ^8.1.0`（pub 最新稳定，flutter.dev 官方）
* `url_launcher: ^6.3.1`（pub 最新稳定，flutter.dev 官方）

### Assets

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/icon/
```

* 二进制：`assets/icon/app_icon.webp` ← `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp` 复制。

## Decision (ADR-lite)

**Context**：需要展示应用基本信息 + 第三方许可，且 settings feature 当前是 stub，正好介入。

**Decision**：
1. **About 作为独立 feature**（D1）—— About 与 Settings 是两个不同的产品域，将 about_screen 放在 settings feature 下会污染 settings 的语义边界，且未来若要从其他入口（启动闪屏 / 首页 info icon）跳到 About，独立 feature 更通用。
2. **`class AppInfo` 聚合常量而非顶层 kXxx**（D2）—— 应用元信息是一组紧密相关的常量集合，符合项目内 `class Breakpoints / class AppNavDestination` 的聚合命名惯例；顶层 `kXxx` 更适合独立的领域阈值（如 `kIsolatePixelThreshold`）。
3. **内置 `showLicensePage()` 而非自定义**（D6）—— 零额外维护、覆盖全量传递依赖、风格与 MD3 一致；自定义实现需手动维护依赖清单。
4. **Flutter asset 引入 webp 而非临时占位图标**（D4）—— 与 launcher 视觉一致，零格式转换成本（Flutter 原生支持 webp）。
5. **`package_info_plus` 动态读取版本**（D5）—— 与构建命令 `--build-name/--build-number` 覆盖一致，避免发版时漏改字符串。
6. **入口 ListTile 顺序：源码→反馈→许可**（D3.4）—— 信息从"产品 identity" → "用户互动" → "法律信息"渐进，符合 iOS Settings / 主流 Android 应用习惯。

**Consequences**：
* + About 与 Settings 解耦，独立测试与跳转重定向都简单。
* + License 列表自动跟随依赖变化，无需手工维护。
* + AppInfo 聚合便于未来扩展（如添加 `kAppStoreUrl` 等）。
* − 新增 2 个直接依赖（`package_info_plus`、`url_launcher`），但都是官方维护、风险可控。
* − Flutter `assets/` 目录首次启用，需要确认 PR 包含 `assets/icon/app_icon.webp` 二进制文件。

## Technical Notes

* 关键文件：
  - `lib/features/about/presentation/screens/about_screen.dart`（新增 feature 主屏）
  - `lib/features/settings/presentation/screens/settings_screen.dart`（修改 — 加入口）
  - `lib/core/constants/app_info.dart`（新增 — `class AppInfo`）
  - `lib/app/router.dart`（修改 — settings branch 加子路由）
  - `pubspec.yaml`（修改 — deps + assets）
  - `assets/icon/app_icon.webp`（新增二进制 ← mipmap-xxxhdpi 复制）
  - `test/features/about/about_screen_test.dart`（新增）
  - `test/features/settings/settings_screen_test.dart`（新增）
* 参考 spec：`directory-structure.md`（新 feature 落点）、`component-guidelines.md`（widget 结构）、`state-management.md`（FutureBuilder 简单异步）、`quality-guidelines.md`（lint + test bar）、`responsive-layout.md`（Center + ConstrainedBox 限宽模式）、`error-handling.md`（SnackBar 中文文案）、`dependencies-and-platforms.md`（pubspec 依赖 & 平台 manifest）、`type-safety.md`（buildNumber 空字符串处理）。
* `package_info_plus` mock：测试 setUp 中调用 `PackageInfo.setMockInitialValues(appName: 'Fl PiCraft', packageName: 'com.example.fl_picraft', version: '1.0.0', buildNumber: '1', buildSignature: '', installerStore: '')`。
