# Subtask: macOS Settings 菜单桥接到 /settings 路由

**Parent**: [`.trellis/tasks/05-20-desktop-window-mgmt-and-menu`](../05-20-desktop-window-mgmt-and-menu/prd.md)

## Scope

把 macOS 系统菜单栏 `App → Settings…`（⌘,）打通到 Flutter 内的 `/settings` 路由。包含：

- macOS 原生侧：XIB 改文案 + 连 IBAction + 新建 `MenuChannelBridge.swift`
- Dart 侧：新建 `lib/core/native/menu_channel.dart` + `lib/main.dart` 接入

## Detail（节选自父 PRD §A 与 §E）

### 改动文件

| File | Action |
|---|---|
| `macos/Runner/Base.lproj/MainMenu.xib` | 文案 `Preferences…` → `Settings…`（U+2026），追加 `<connections><action selector="openSettings:" target="Voe-Tx-rLC" id="set-1-aci"/></connections>` |
| `macos/Runner/AppDelegate.swift` | 新增 `var menuBridge: MenuChannelBridge?` 与 `@IBAction func openSettings(_ sender: Any?) { menuBridge?.openSettings() }` |
| `macos/Runner/MainFlutterWindow.swift` | `awakeFromNib` 中构造 `MenuChannelBridge(messenger: flutterViewController.engine.binaryMessenger)` 并赋给 AppDelegate |
| `macos/Runner/MenuChannelBridge.swift` | **新建** — 薄封装 `FlutterMethodChannel("app.fl_picraft/menu", ...)`，暴露 `openSettings()` |
| `lib/core/native/menu_channel.dart` | **新建** — `MethodChannel('app.fl_picraft/menu').setMethodCallHandler`，监听 `openSettings` 触发 `appRouter.go('/settings')` |
| `lib/main.dart` | `runApp` 之前 `WidgetsFlutterBinding.ensureInitialized()` + `MenuChannel.bind(...)` |
| `test/core/native/menu_channel_test.dart` | **新建** — mock `MethodChannel`，验证 `openSettings` 调到 `onOpenSettings` 回调 |

### 关键约束

- `target="Voe-Tx-rLC"`（AppDelegate xib id），**不要**用 `target="-1"`（First Responder）。
- 文案 `Settings…` 必须是 U+2026 单字符省略号（与 xib 内现有约定一致）。
- 用 `appRouter.go('/settings')` 而非 `.push('/settings')` —— 自动消重复堆栈。
- Channel name = `app.fl_picraft/menu`（reverse-DNS 风格，给未来 channel 留命名空间）。
- Smoke 验证范围：仅 macOS（Windows / Linux 不接入系统菜单栏，属于父任务的 Out of Scope）。

## Acceptance Criteria

- [ ] `flutter run -d macos` 后，点菜单栏 `App → Settings…` 或按 ⌘,，切到 Settings 路由。
- [ ] 当前位于 `/settings` 时再次点击 → 无重复堆栈、无报错。
- [ ] 从任意路由（`/`、`/stitch`、`/grid`、`/export`）触发都生效。
- [ ] `flutter analyze` clean；`flutter test` 新增的 menu_channel_test 通过。
- [ ] 未引入新 pubspec 依赖。

## Out of Scope

- 完整的 Settings 页面 UI（仍是 PlaceholderBody）。
- Windows / Linux 的菜单栏接入（父任务 Out of Scope）。
- 双向通道（Dart → native）—— 当前 channel 只用 native → Dart 方向。

## Smoke Verify Script

```bash
flutter clean && flutter pub get && flutter run -d macos
# 在 app 中按 ⌘, → 期望切到 /settings
```
