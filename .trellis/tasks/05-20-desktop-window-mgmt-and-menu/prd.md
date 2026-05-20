# 桌面平台窗口管理与系统菜单响应

## Goal

让 fl_picraft 在三大桌面平台（macOS / Windows / Linux）拥有「专业桌面应用」级别的窗口体验：

1. **macOS Settings 菜单接入** — 让 macOS 系统菜单栏 `App → Settings…`（⌘,）能直达 Flutter 内的 `/settings` 路由，符合 macOS 13+ 的 HIG。
2. **统一的窗口策略** — 三端首次启动默认占屏 80%；退出前记忆窗口尺寸（可能也含位置），下次启动恢复；强制最小尺寸约束。
3. **全部用原生平台代码实现** — 不引入 `window_manager` / `bitsdojo_window` 等 Flutter 插件，直接在 Swift / Win32 C++ / GTK C 代码中完成；持久化使用各平台的原生偏好存储（NSUserDefaults / Win32 Registry 或 %APPDATA% INI / XDG `~/.config/<app>/state.ini`）。

## What I already know

### 现状（已扫描）

- `lib/main.dart` 极简：`runApp(ProviderScope(AppRoot))`，**没有** `WidgetsFlutterBinding.ensureInitialized()`，**没有** 任何 MethodChannel。
- `lib/app/router.dart` 已注册 `/settings` 路由，对应 `lib/features/settings/presentation/screens/settings_screen.dart`（目前是 `PlaceholderBody` 占位）。
- macOS：
  - `macos/Runner/MainFlutterWindow.swift` 是默认的 `NSWindow` 子类，未做任何尺寸 / 最小尺寸 / 位置恢复逻辑。
  - `macos/Runner/AppDelegate.swift` 仅重写两个标准方法，**未持有任何 MethodChannel**。
  - `macos/Runner/Base.lproj/MainMenu.xib` 已经声明 `<menuItem title="Preferences…" keyEquivalent="," id="BOF-NM-1cW"/>`，但 **没有 `<connections>`**，所以点了无反应。
- Windows：
  - `windows/runner/main.cpp` 硬编码 `Win32Window::Size size(1280, 720)`，`Point origin(10, 10)`。
  - `windows/runner/win32_window.cpp` 是 boilerplate，未处理 `WM_GETMINMAXINFO`、未做持久化。
- Linux：
  - `linux/runner/my_application.cc` 硬编码 `gtk_window_set_default_size(window, 1280, 720)`，**没有** `gtk_window_set_geometry_hints` 最小尺寸限制，未做持久化。

### 项目约束

- `CLAUDE.md` 锚定 Clean Architecture + Feature-First + Riverpod + Dio + MD3，但本任务主要在 native + 极薄 Dart 桥接层，不需要拆 data/domain/presentation 三层。
- `.trellis/spec/frontend/dependencies-and-platforms.md` 强调添加任何依赖都要走「先调研、记决策、锁版本」的流程 —— 本任务的设计目标恰恰是 **不引入新依赖**。
- Flutter SDK：`^3.10.8`；当前已锁定 Riverpod / GoRouter / image / file_picker / super_drag_and_drop 等技术栈。

## Assumptions (temporary)

- A1：「原生 Native 实现」= 所有窗口初始化、最小尺寸约束、尺寸记忆/恢复都写在 macOS Swift / Windows C++ / Linux C 代码中；**不引入** Flutter 端窗口管理插件。持久化也走平台原生偏好存储。
- A2：macOS Settings 菜单 → Flutter 路由的跳转，是「native 触发、MethodChannel 通知 Dart、Dart 调 GoRouter」三步式标准桥接。
- A3：「记忆窗口大小」**只包含尺寸**，不含屏幕位置（待用户确认 —— 见 Open Question Q2）。
- A4：「屏幕大小的 80%」指应用启动时所在的「主显示器（primary monitor）」的可用工作区（去掉菜单栏/任务栏）大小的 80%（待用户确认 —— 见 Open Question Q4）。
- A5：~~1920×1080~~ **1280×800** 是最终最小尺寸（用户 2026-05-20 决定从 1920×1080 改为 1280×800，避免与「80% 屏幕」默认值冲突且兼容主流笔电屏）。

## Open Questions

- Q1（拆分）：本任务的 subtask 切分粒度？候选：
  - **A. 两个 subtask**：①macOS Settings 菜单桥接；②三端窗口策略（80% / 最小 / 记忆-恢复）合一
  - **B. 四个 subtask**：①Settings 菜单；②macOS 窗口；③Windows 窗口；④Linux 窗口
  - **C. 不拆**：单 PRD 单 PR，所有改动一起进
- Q2（边界扩展）：除「尺寸」外，是否一并记忆**窗口位置**？多数桌面应用都会一起做。
- Q3（最小尺寸合理性）：~~待定~~ **已决议：1280×800**（用户 2026-05-20 选择，原因：1920×1080 会与「80% 屏幕」默认值产生「默认 < 最小」的逻辑悖论，且让 1080p 笔电不可用）。
- Q4（多显示器）：多显示器场景下「屏幕 80%」算哪一块？候选：
  - A. 系统主显示器（primary，含菜单栏 / 任务栏那块）
  - B. 鼠标当前所在的显示器
  - C. 上次退出时所在的显示器（与 Q2 联动）
- Q5（macOS 菜单文案）：标准 Xcode 模板的 macOS 13+ HIG 推荐 "Settings…"；当前 xib 是 "Preferences…"。是否改成 "Settings…"？
- Q6（首次启动行为）：第一次启动（无持久化记录时）窗口是 80% **居中**，还是直接套用平台默认（如 Win32 的 `(10,10)` 起点）？

## Requirements (evolving)

- R1：macOS 系统菜单栏 `<AppName> → Settings…`（⌘,）点击后，应用焦点导航到 Flutter 的 `/settings` 路由；当前已在 settings 页则不重复 push。
- R2：三端默认窗口尺寸 = 主显示器可用工作区的 80%（具体规则见 Q4 决议）。
- R3：每次正常退出（含点 X、Cmd+Q、Alt+F4）时持久化当前窗口尺寸（可能含位置）。
- R4：下次启动时若存在持久化记录则恢复；不存在则走 R2 的 80% 默认。
- R5：窗口最小尺寸 = **1280×800**（已决议），用户拖小窗口时硬卡住。
- R6：所有窗口管理代码用平台原生 API 实现，不引入 Flutter 窗口插件。
- R7：持久化存储用平台原生偏好系统（NSUserDefaults / Win32 持久化 / XDG config）。

## Acceptance Criteria (evolving)

- [ ] AC1（macOS 菜单）：在已发布的 macOS 构建上，点击菜单栏 `App → Settings…` 或按 ⌘,，应用切换到 Settings 标签页/路由；从任意路由触发都生效。
- [ ] AC2（默认尺寸）：三端首次启动（清空持久化后）窗口尺寸 ≈ 主显示器可用区 80%，居中显示。
- [ ] AC3（最小尺寸）：三端用鼠标拖拽窗口边角无法把任一维度拖到小于 **1280×800**。
- [ ] AC4（持久化-恢复）：正常退出后再次启动，窗口尺寸（位置可选）与退出前一致。
- [ ] AC5（无插件）：`pubspec.yaml` 未引入 `window_manager` / `bitsdojo_window` / `flutter_acrylic` 等窗口管理类插件；`flutter pub deps` 中不存在相应包。
- [ ] AC6（lint/test 干净）：`flutter analyze` clean；`flutter test` 全绿；`dart format .` 无 diff。

## Definition of Done (team quality bar)

- 测试更新：
  - Dart 层 MethodChannel handler 加 unit test（mock platform channel 模拟 macOS 调用）；
  - native 端的窗口逻辑用对应平台的最小化集成测试或人工 smoke 验证清单覆盖。
- 三端 `flutter build` 都成功（macOS / Windows 至少本地能跑；Linux 至少能 `flutter build linux` 成功）。
- `flutter analyze` / `dart format .` / `flutter test` 全部通过。
- 修改了行为，需在 `.trellis/spec/frontend/dependencies-and-platforms.md` 或新增 spec 文件中记录「桌面窗口策略 & macOS 菜单桥接约定」。
- 风险考量：持久化文件损坏 / 多显示器拓扑变化 / DPI 变化 → 见 `Technical Approach` 兜底逻辑。

## Out of Scope (explicit)

- Web 平台（不适用窗口管理）。
- 移动端 Android / iOS（不适用）。
- 完整的 Settings 页面 UI（仅是「能跳到该路由」，Settings 内容由后续任务负责）。
- Windows / Linux 系统菜单栏的接入（用户只提了 macOS）。
- 应用图标 / 窗口标题 / 主题菜单 / 全局快捷键扩展等。
- 多窗口（multi-window）支持。
- 「记住上次所在的 tab」之类的 Flutter 端状态恢复（与本任务正交）。

## Technical Approach (FINAL — research-validated)

### A. macOS Settings 菜单桥接（Subtask 1）

**核心决策**：用 XIB IBAction + 自定义 IBAction `@objc func openSettings(_:)` on `AppDelegate`，配合 `FlutterMethodChannel("app.fl_picraft/menu")`。

1. `macos/Runner/Base.lproj/MainMenu.xib`：
   - 把 `<menuItem title="Preferences…" id="BOF-NM-1cW">`（line 36）改为 `<menuItem title="Settings…" id="BOF-NM-1cW">`，**必须用 U+2026 单字符省略号**（与文件内其它菜单项一致）。
   - 在该 `<menuItem>` 内追加 `<connections><action selector="openSettings:" target="Voe-Tx-rLC" id="set-1-aci"/></connections>` —— `target="Voe-Tx-rLC"` 是当前 xib 里 AppDelegate 的 id（**绝对不要**写 `target="-1"`，那会丢进 responder chain）。
2. `macos/Runner/MenuChannelBridge.swift`（新建）：薄封装 `FlutterMethodChannel(name: "app.fl_picraft/menu", binaryMessenger: ...)`，暴露 `openSettings()` 方法。
3. `macos/Runner/MainFlutterWindow.swift`：在 `awakeFromNib` 中拿 `flutterViewController.engine.binaryMessenger` 构造 `MenuChannelBridge`，并把引用塞进 `(NSApp.delegate as? AppDelegate)?.menuBridge`。
4. `macos/Runner/AppDelegate.swift`：新增 `var menuBridge: MenuChannelBridge?` 与 `@IBAction func openSettings(_ sender: Any?) { menuBridge?.openSettings() }`。
5. Dart 端 `lib/core/native/menu_channel.dart`（新建）：用 `MethodChannel('app.fl_picraft/menu').setMethodCallHandler` 监听 `openSettings`，回调 `appRouter.go('/settings')`（用 `.go(...)` 而非 `.push(...)` —— 自动去重，避免重复堆栈）。
6. `lib/main.dart`：把 `runApp(...)` 之前加 `WidgetsFlutterBinding.ensureInitialized()`，并 `MenuChannel.bind(onOpenSettings: () => appRouter.go('/settings'))`。

**关键事实**（来自调研）：
- macOS 13+ HIG 官方文案是 `Settings…`，Apple 自己的 SwiftUI `OpenSettingsAction` (macOS 14+) 是 SwiftUI 限定 —— AppKit 项目必须自己写 IBAction。
- `FlutterViewController.engine.binaryMessenger` 在 `awakeFromNib` 阶段已可用；时序上 channel 一定早于第一次菜单点击就绪。
- `MenuChannelBridge` 强引用 channel，`MainFlutterWindow` 强引用 bridge，无内存泄漏；app 退出时连带释放。

### B. macOS 窗口策略（Subtask 2）

**核心决策**：用 `NSWindow.setFrameAutosaveName("fl_picraft.main")` 取代手写 `NSUserDefaults` 读写 —— AppKit 自动在用户每次 resize/move 时存盘，多屏拓扑变化时自动 `constrainFrameRect:to:` 兜底。最小尺寸用 `contentMinSize`（不含标题栏）而非 `minSize`。

1. `macos/Runner/MainFlutterWindow.swift` 的 `awakeFromNib`：
   - `self.contentViewController = FlutterViewController()`（保留现有）
   - `self.contentMinSize = NSSize(width: 1280, height: 800)`（contentMinSize 比 minSize 高优先，准确表达「最小可用画布 1280×800」语义）
   - 计算 80% 居中默认 frame：用 `self.screen ?? NSScreen.main ?? NSScreen.screens.first` + `screen.visibleFrame`（已排除 dock / menu bar / 刘海）
   - `self.setFrame(defaultFrame, display: true)` —— **注意**：`setFrame(_:display:)` 是 AppKit 文档明确说「**不受 minSize 约束**」的特殊设置器（其他 setFrame 变体会被 clamp），所以可以精确设置 80% 值
   - **接下来必须先设 frame 再 set autosave name**：`_ = self.setFrameAutosaveName("fl_picraft.main")` —— 当 UserDefaults 已有保存值时，AppKit 立即覆盖我们刚设的 default；当 UserDefaults 还没有时，保留 default。
2. 不需要手写 `applicationWillTerminate` 存盘 —— AppKit autosave 已经在用户每次 resize/move 时同步写入 `NSWindow Frame fl_picraft.main` 这个 UserDefaults key。
3. 多屏拓扑变化由 AppKit 内置 `constrainFrameRect(_:to:)` 自动处理，无需手写「rect 是否可见」校验。

**关键事实**（来自调研）：
- frame 单位是逻辑点 (points)，跨 Retina / 非 Retina 自动适配，无需 `backingScaleFactor` 换算。
- `visibleFrame` 已排除刘海（M 系列 MacBook Pro），80% 计算天生 notch-safe。
- 首次启动当 UserDefaults 还没有 autosave 记录时，AppKit 的 `setFrameAutosaveName` 仅返回 `false`（已被占用情况下），不会覆盖我们的 default frame —— 行为完全符合「首次 80% 居中、后续恢复」。

### C. Windows 窗口策略（Subtask 3）

**核心决策**：用 INI 文件 `%APPDATA%\fl_picraft\window_state.ini` 持久化「物理像素 + DPI 快照」；`WM_GETMINMAXINFO` 在 `Win32Window::MessageHandler` 处理；`WM_CLOSE`（不是 `WM_DESTROY`）捕获 outer rect。

1. 新建 `windows/runner/window_state.{h,cpp}`：
   - `GetWindowStateIniPath()`：用 `SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_CREATE, ...)` 取 `%APPDATA%`，拼出 `fl_picraft\window_state.ini`，`CreateDirectoryW` idempotent 建目录。
   - `LoadWindowState()`：`GetPrivateProfileIntW` 读 `[Window]` 区段下 5 个 int（X/Y/Width/Height/Dpi），缺失或越界则返回 `nullopt`。
   - `SaveWindowState(state)`：`WritePrivateProfileStringW` 写 5 个 int，结尾用 `WritePrivateProfileStringW(NULL, NULL, NULL, path)` 强制 flush 写缓存。
   - `ComputeDefaultRectOnPrimaryMonitor(0.8)`：`MonitorFromPoint({0,0}, MONITOR_DEFAULTTOPRIMARY)` + `GetMonitorInfoW().rcWork` + `GetDpiForMonitor`，居中算式返回物理像素 + DPI。
   - `IsRectVisibleOnAnyMonitor()`：`EnumDisplayMonitors` 累加每个 `IntersectRect` 面积，要求 ≥ 100×100 才认为可见。

2. `windows/runner/main.cpp`：
   - 在构造 `FlutterWindow` 前先 `LoadWindowState()`，若不可见则 fallback `ComputeDefaultRectOnPrimaryMonitor(0.8)`。
   - 把物理像素除以 `GetDpiForMonitor / 96.0` 换成 **逻辑像素**，再传 `Win32Window::Create(title, origin, size)`（Scaffold 的 contract 是逻辑像素，内部会再 scale）。

3. `windows/runner/win32_window.cpp` 的 `MessageHandler` switch 新增两个 case：
   - **`WM_GETMINMAXINFO`**：`GetDpiForWindow(hwnd)` 取 DPI → 把 1280×800 client area 乘 DPI scale → `AdjustWindowRectExForDpi(&rect, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi)` 算出含 titlebar/border 的 outer rect → 写 `mmi->ptMinTrackSize`（物理像素）。
   - **`WM_CLOSE`**：`GetWindowPlacement(hwnd, &wp)` 取 `wp.rcNormalPosition`（restored 状态的 rect，避开 maximized 状态 race） + `GetDpiForWindow(hwnd)` → `SaveWindowState(...)` → `break` 让 DefWindowProc 继续走 DestroyWindow。

4. `windows/runner/CMakeLists.txt`：
   - 把 `window_state.cpp` 加入 `RUNNER_SOURCES`。
   - `target_link_libraries(${BINARY_NAME} PRIVATE "shcore.lib" "shell32.lib")` —— shcore 提供 `GetDpiForMonitor`，shell32 提供 `SHGetKnownFolderPath`。

**关键事实**（来自调研）：
- `runner.exe.manifest` 已声明 PerMonitorV2，无需改动；PMv2 下 `GetMonitorInfoW` / `SPI_GETWORKAREA` 返回物理像素，`AdjustWindowRectExForDpi` 用于 client→outer 转换。
- `WM_CLOSE` 在 `DestroyWindow` 之前到达，是捕获 outer rect 的标准时机；`WM_DESTROY` 太迟。
- 持久化「物理像素 + 当前 DPI 快照」便于未来升级到「等比缩放」恢复策略，本任务采用「直接还原物理像素」简化方案。
- `Win32Window::Create` 的 contract 接受逻辑像素（96-DPI 基准）；调用前必须从物理转换。

### D. Linux 窗口策略（Subtask 4）

**核心决策**：GTK 3 + `g_get_user_config_dir()/fl_picraft/window_state.ini`（GKeyFile）；Wayland 上位置恢复降级为 no-op；最小尺寸用 `gtk_window_set_geometry_hints + GDK_HINT_MIN_SIZE`。

1. 改 `linux/runner/my_application.cc`：
   - 顶部加 `#ifdef GDK_WINDOWING_WAYLAND #include <gdk/gdkwayland.h>` 守卫。
   - 新增 helper：
     - `state_file_path()` / `ensure_state_dir()` 用 `g_build_filename(g_get_user_config_dir(), "fl_picraft", ...)` + `g_mkdir_with_parents(..., 0700)`。
     - `load_saved_geometry()` 用 `g_key_file_load_from_file` + `g_key_file_get_integer`；w/h 小于 1280×800 视为 invalid。
     - `rect_is_visible(display, x, y, w, h)`：枚举 `gdk_display_get_monitor(display, i)` for `i in 0..gdk_display_get_n_monitors`，`gdk_rectangle_intersect` ≥ 100×100 才算可见。
     - `compute_default_geometry(display, &x, &y, &w, &h)`：用 `gdk_display_get_primary_monitor` ?? `gdk_display_get_monitor(display, 0)`（**Wayland fallback**） + `gdk_monitor_get_workarea`（Wayland 上等价于 `geometry`） × 80% + 居中。
     - `apply_initial_geometry(window)`：先 `gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE)`（min=1280×800），再 `gtk_window_set_default_size(window, w, h)`；位置仅在 `GDK_IS_X11_DISPLAY(display)` 时 `gtk_window_move(window, x, y)`。
     - `on_window_delete_event(widget, event, data)`：`gtk_window_get_size` 读尺寸；`GDK_IS_X11_DISPLAY` 守卫下 `gtk_window_get_position` 读位置；用 `g_key_file_save_to_file`（内部走 `g_file_set_contents` 原子重命名）写盘；返回 `FALSE` 让 GTK 继续 destroy。
   - 把 `my_application_activate` 第 55 行 `gtk_window_set_default_size(window, 1280, 720)` 替换为 `apply_initial_geometry(window)` + `g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete_event), NULL)`。
   - **`linux/runner/CMakeLists.txt` 无需改动** —— `PkgConfig::GTK` 已经传递性带入 `gdk-x11-3.0` 和 `gdk-wayland-3.0`。

**关键事实**（来自调研）：
- `gdk_display_get_primary_monitor` 在 **Wayland 上必然返回 NULL**（Wayland 协议无 primary monitor 概念）—— 必须 fallback `gdk_display_get_monitor(display, 0)`。
- `gdk_monitor_get_workarea` 在 Wayland 上 = `geometry`（不剔除 panel）；可接受，因为 Wayland 自己会在 maximize 时排除 panel。
- 所有 4 个 GTK API（`get_workarea` / `set_default_size` / `set_geometry_hints` / `get_size`）都在「应用像素」(logical DIPs) 工作，**不需要乘 scale factor**。
- `gtk_window_get_position` 在 Wayland 上恒返回 `(0,0)`（设计如此），所以 X11 守卫 `GDK_IS_X11_DISPLAY` 是必须的。
- Flutter Linux runner 锁 GTK 3；本方案与 GTK 4 不兼容（GTK 4 用 `gtk_widget_set_size_request` 替代 `set_geometry_hints`、用 `close-request` 替代 `delete-event`），但不在当前 SDK 范围。

### E. Dart 桥接层（Subtask 1 的一部分）

新建 `lib/core/native/menu_channel.dart`：

```dart
// 草案 —— 详细实现在 Subtask 1 的 PR 内
import 'package:flutter/services.dart';

class MenuChannel {
  static const _channel = MethodChannel('app.fl_picraft/menu');
  static void bind({required void Function() onOpenSettings}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') {
        onOpenSettings();
        return null;
      }
      throw MissingPluginException();
    });
  }
}
```

`lib/main.dart` 调整为：

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MenuChannel.bind(onOpenSettings: () => appRouter.go('/settings'));
  runApp(const ProviderScope(child: AppRoot()));
}
```

注：用 `appRouter.go('/settings')` 自动消重复堆栈（已在该路由时是 no-op-ish），符合 E6 idempotency 要求。

### F. 兜底 / 容错（全平台共识）

- 持久化文件不存在 / 损坏 / 解析失败 → 走 80% 默认，不弹错。
- 持久化的 frame 在当前显示器拓扑下不可见 → 三端各自有不同机制兜底：
  - macOS：`frameAutosaveName` 内置 `constrainFrameRect:to:`
  - Windows：`IsRectVisibleOnAnyMonitor` ≥ 100×100 守卫
  - Linux：`rect_is_visible` 同上
- DPI 变化：macOS / Linux 用逻辑点本身就跨 DPI 安全；Windows 我们记录「物理像素 + DPI 快照」，本任务采用「直接还原物理像素」（用户可自行 resize）。

## Decision (ADR-lite)

### D-A. macOS 菜单文案与 IBAction 选择器

**Context**：macOS 13+ HIG 把 App 菜单的入口从「Preferences…」改成「Settings…」；AppKit/XIB 项目没有现成的 `openSettings:` selector（那是 SwiftUI 14+ 的）。

**Decision**：xib 改名为「Settings…」（U+2026），自定义 `@IBAction func openSettings(_:)` on `AppDelegate`，xib `target` 直连 `Voe-Tx-rLC`（AppDelegate id），不走 First Responder。

**Consequences**：与 Apple SwiftUI 14+ 的 selector 名一致，未来若迁 SwiftUI 改动小；不依赖 responder chain，行为可预测；老用户从 Preferences 升级时菜单文案变化属于 HIG-compliant。

### D-B. macOS 窗口持久化方案：`frameAutosaveName` 取代手写 UserDefaults

**Context**：原本 PRD 草稿采用「`applicationWillTerminate` 序列化 NSRect 到 UserDefaults」。调研发现 AppKit 自带 `setFrameAutosaveName(_:)` 一行接入。

**Decision**：用 Strategy A（`frameAutosaveName`），不手写 UserDefaults 读写。

**Consequences**：代码减少 ~50 行；用户每次 resize/move 都被即时同步（不依赖 graceful quit）；多屏拓扑变化由 AppKit 自动 clamp；HiDPI 跨机迁移免操心。代价：「rect 仍可见」校验交给系统，少了显式控制点 —— 若未来产品要求自定义「rect 不可见时居中」逻辑，再切回 Strategy B。

### D-C. macOS 最小尺寸：`contentMinSize` 而非 `minSize`

**Context**：`minSize` 把 ~28pt titlebar 算进去，1280×800 minSize 等价于 content 区 1280×772，与用户「1280×800 可用画布」直觉相左。

**Decision**：`self.contentMinSize = NSSize(width: 1280, height: 800)`；`contentMinSize` 在 Apple 文档里明确「takes precedence over minSize」。

**Consequences**：用户拖小窗口时 Flutter 可见区域至少 1280×800；语义清晰。

### D-D. Windows 持久化格式：INI 而非注册表 / JSON

**Context**：原 PRD 草稿就锁定 `%APPDATA%\fl_picraft\window_state.ini`；调研验证 INI 是合适选择（5 个 int，无嵌套结构）。

**Decision**：`WritePrivateProfileStringW` / `GetPrivateProfileIntW` + `%APPDATA%\fl_picraft\window_state.ini`，键为 X/Y/Width/Height/Dpi（5 个 int）。

**Consequences**：零外部依赖（Kernel32 自带）；用户可手动编辑调试；UTF-16 LE 文件格式无歧义；写完调 `WritePrivateProfileStringW(NULL,NULL,NULL,path)` 强制 flush。

### D-E. Windows 退出点：`WM_CLOSE` 在 `Win32Window::MessageHandler`

**Context**：`WM_CLOSE` vs `WM_DESTROY` 时序差；位置选 `Win32Window::MessageHandler`（基类）或 `FlutterWindow::MessageHandler`（子类）。

**Decision**：在 `Win32Window::MessageHandler` 处理 `WM_CLOSE` 和 `WM_GETMINMAXINFO`；用 `GetWindowPlacement.rcNormalPosition`（不是 `GetWindowRect`）规避 maximized 状态的尺寸污染。

**Consequences**：与 Microsoft 官方推荐时序对齐；handle 仍 valid；`Alt+F4` / X 按钮 / `Application.Exit` 都覆盖；maximized 退出时下次启动恢复到 restored 尺寸而非最大化全屏。

### D-F. Linux 持久化：GKeyFile + XDG

**Context**：Linux 持久化候选 GKeyFile / GSettings / 手写 JSON。

**Decision**：`GKeyFile` + `g_get_user_config_dir()/fl_picraft/window_state.ini`，`g_key_file_save_to_file` 内部 `g_file_set_contents` 原子重命名。

**Consequences**：XDG 合规、零额外依赖（GLib 已链接）、原子写入防止崩溃损坏；与 Windows 的 INI 在概念上对称。

### D-G. Linux Wayland 降级策略

**Context**：Wayland 无 primary monitor 概念、不允许应用读写窗口位置、`workarea = geometry`。

**Decision**：
- `gdk_display_get_primary_monitor()` fallback `gdk_display_get_monitor(display, 0)`。
- 位置仅在 `GDK_IS_X11_DISPLAY` 下读写；Wayland 上位置字段照写 `(0,0)`，复用时跳过 `gtk_window_move`。
- 「rect 可见性」校验用 `geometry` 替代 `workarea`（Wayland 上两者相等）。

**Consequences**：X11 用户体验完整（80% 居中 / 位置记忆 / 多屏校验）；Wayland 用户体验降级到「尺寸记忆 + 由 compositor 决定位置」，符合 Wayland 协议设计意图。

### D-H. Subtask 拆分粒度：4 个独立 subtask

**Context**：候选「2 subtask（菜单 + 窗口三端合一）」/「4 subtask（菜单 + 三端各一）」/「单 PR」。

**Decision**：拆 4 个 subtask（用户 2026-05-20 决定）。

**Consequences**：每个 PR 体量可控，可独立 review / 回滚；三端窗口策略可并行实施；代价是「三端实现一致性」需在 parent task 的 spec / acceptance criteria 里显式约束。

## Technical Notes

- macOS HIG（13+）："Preferences…" → "Settings…" 改名是官方推荐，但旧应用沿用 Preferences 也兼容。
- Win32 持久化建议：用 `%APPDATA%\fl_picraft\window_state.ini` 比注册表更易调试、更便携，且与 Linux 的 XDG 方案对称。
- 平台 API 索引：
  - macOS：`NSScreen.visibleFrame`、`NSWindow.frameAutosaveName`（也可考虑用系统自带的 frame autosave）、`UserDefaults`
  - Windows：`GetMonitorInfo`、`WM_GETMINMAXINFO`、`GetWindowRect`、`SetWindowPos`
  - Linux：`gdk_monitor_get_workarea`、`gtk_window_set_geometry_hints`、`GKeyFile`、`g_get_user_config_dir`
- macOS 还可考虑直接用 `NSWindow.frameAutosaveName = "MainWindow"`，让系统自动负责 frame 持久化（最 native 的方案）。是否采用这个「零代码」方案，是 Q1 的延伸。

## Research References

- [`research/macos-window-and-menu.md`](research/macos-window-and-menu.md) — macOS 原生 NSWindow + Settings 菜单桥接：选定 `frameAutosaveName`、`contentMinSize`、自定义 IBAction `openSettings:`、`FlutterMethodChannel("app.fl_picraft/menu")`。
- [`research/windows-window-management.md`](research/windows-window-management.md) — Windows Win32：PerMonitorV2 已启用、`AdjustWindowRectExForDpi` 处理 client→outer 转换、`WM_CLOSE` 用 `GetWindowPlacement.rcNormalPosition` 规避 maximized 偏差、INI at `%APPDATA%\fl_picraft\`。
- [`research/linux-window-management.md`](research/linux-window-management.md) — Linux GTK 3：Wayland 上 `primary_monitor`/`workarea`/`get_position` 三大限制需守卫；GKeyFile + XDG config dir 持久化；`delete-event` save-on-exit。

## Implementation Plan (4 PRs)

按 4 个 subtask 拆分，先做 Subtask 1（菜单桥接，单平台、最小代价、可独立验证），再并行 Subtask 2/3/4（三端窗口策略）。

### PR-1: Subtask 1 — macOS Settings 菜单桥接

**Touched files**：
- `macos/Runner/Base.lproj/MainMenu.xib`（改文案 + 接 connections）
- `macos/Runner/AppDelegate.swift`（加 `menuBridge` 属性 + `openSettings:` IBAction）
- `macos/Runner/MainFlutterWindow.swift`（构造 `MenuChannelBridge` 并赋给 AppDelegate）
- `macos/Runner/MenuChannelBridge.swift`（新建）
- `lib/core/native/menu_channel.dart`（新建）
- `lib/main.dart`（加 `WidgetsFlutterBinding.ensureInitialized()` + `MenuChannel.bind(...)`)
- 单测：`test/core/native/menu_channel_test.dart`（mock `MethodChannel`，验证 `openSettings` 调到 `appRouter.go('/settings')`)

**Smoke verify**：
- macOS 上 `flutter run -d macos`，按 ⌘, 或菜单 `App → Settings…`，应用切到 Settings 路由。
- 重复按多次：每次都到 settings，无堆栈污染。

### PR-2: Subtask 2 — macOS 窗口策略

**Touched files**：
- `macos/Runner/MainFlutterWindow.swift`（`awakeFromNib` 加 `contentMinSize` / 80% default frame / `setFrameAutosaveName`）

**Smoke verify**：
- 删除 `~/Library/Preferences/com.example.flPicraft.plist`（autosave 落点）→ 启动 → 窗口 ≈ 主屏 visibleFrame 80% 居中。
- 拖拽 resize → 退出 → 再启动 → 恢复到退出时尺寸位置。
- 拖窗口边角尝试缩小到 1280×800 以下 → 卡住。
- 拔掉外接屏 / 切换主屏 → 重启 → 窗口在新主屏上可见。

### PR-3: Subtask 3 — Windows 窗口策略

**Touched files**：
- `windows/runner/window_state.h`（新建）
- `windows/runner/window_state.cpp`（新建）
- `windows/runner/main.cpp`（启动时计算/恢复 initial rect）
- `windows/runner/win32_window.cpp`（`WM_GETMINMAXINFO` + `WM_CLOSE` 两个 case）
- `windows/runner/CMakeLists.txt`（加 source + 链接 `shcore.lib` `shell32.lib`）

**Smoke verify**：
- 删除 `%APPDATA%\fl_picraft\window_state.ini` → 启动 → 窗口 ≈ 主屏工作区 80% 居中。
- 拖拽 resize → 退出 → 再启动 → 恢复。
- 拖窗口边角缩小至 1280×800 以下 → 卡住。
- 切换显示器 DPI 缩放（100% → 150%）→ 重启 → 窗口尺寸合理。

### PR-4: Subtask 4 — Linux 窗口策略

**Touched files**：
- `linux/runner/my_application.cc`（加 helpers + 改 `my_application_activate` 替换 `set_default_size`）
- `linux/runner/CMakeLists.txt`：无需改动（PkgConfig::GTK 传递性 OK）

**Smoke verify**（X11 + Wayland 各跑一遍）：
- 删除 `~/.config/fl_picraft/window_state.ini` → 启动 → 窗口 ≈ 主屏 80%（X11 居中 / Wayland 由 compositor 决定）。
- 拖拽 resize → 退出 → 再启动 → 尺寸恢复（位置在 X11 上恢复，在 Wayland 上由 compositor 决定）。
- 拖窗口边角缩小至 1280×800 以下 → 卡住（X11 和 Wayland 都生效）。

