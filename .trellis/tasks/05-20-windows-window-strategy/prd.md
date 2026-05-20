# Subtask: Windows 原生窗口策略（Win32 80% 默认 / WM_GETMINMAXINFO / INI 持久化）

**Parent**: [`.trellis/tasks/05-20-desktop-window-mgmt-and-menu`](../05-20-desktop-window-mgmt-and-menu/prd.md)

## Scope

在 Windows Win32 C++ 中实现：

- 首次启动窗口 = 主屏工作区 80%（excluding taskbar），居中。
- 最小 client area = 1280×800（DPI-aware，物理像素由 `AdjustWindowRectExForDpi` 折算）。
- 持久化 = INI 文件 `%APPDATA%\fl_picraft\window_state.ini`，存物理像素 + DPI 快照。
- 退出点 = `WM_CLOSE`，用 `GetWindowPlacement.rcNormalPosition`（规避 maximized 偏差）。

## Detail（节选自父 PRD §C 与 ADR-lite §D-D / §D-E）

### 改动文件

| File | Action |
|---|---|
| `windows/runner/window_state.h` | **新建** — `WindowState` struct + `GetWindowStateIniPath` / `Load` / `Save` / `ComputeDefault` / `IsRectVisibleOnAnyMonitor` |
| `windows/runner/window_state.cpp` | **新建** — INI 读写（`GetPrivateProfileIntW` / `WritePrivateProfileStringW`）+ `SHGetKnownFolderPath(FOLDERID_RoamingAppData)` + `MonitorFromPoint` + `EnumDisplayMonitors` |
| `windows/runner/main.cpp` | 启动时 `LoadWindowState`，无效则 `ComputeDefaultRectOnPrimaryMonitor(0.8)`；把物理像素 ÷ `GetDpiForMonitor / 96.0` 换成逻辑像素传给 `Win32Window::Create(title, origin, size)` |
| `windows/runner/win32_window.cpp` | `Win32Window::MessageHandler` switch 新增 `WM_GETMINMAXINFO`（DPI-scaled 1280×800 + `AdjustWindowRectExForDpi` → `ptMinTrackSize`）和 `WM_CLOSE`（`GetWindowPlacement.rcNormalPosition` + `GetDpiForWindow` → `SaveWindowState`） |
| `windows/runner/CMakeLists.txt` | `RUNNER_SOURCES` 加 `window_state.cpp`；`target_link_libraries(... shcore.lib shell32.lib)` |

### `WM_GETMINMAXINFO` 关键代码

```cpp
case WM_GETMINMAXINFO: {
  constexpr LONG kMinClientW = 1280, kMinClientH = 800;
  UINT dpi = ::GetDpiForWindow(hwnd);
  if (dpi == 0) dpi = 96;
  double scale = dpi / 96.0;
  RECT r { 0, 0,
           static_cast<LONG>(kMinClientW * scale),
           static_cast<LONG>(kMinClientH * scale) };
  ::AdjustWindowRectExForDpi(&r, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi);
  auto* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
  mmi->ptMinTrackSize.x = r.right - r.left;
  mmi->ptMinTrackSize.y = r.bottom - r.top;
  return 0;
}
```

### `WM_CLOSE` 关键代码

```cpp
case WM_CLOSE: {
  WINDOWPLACEMENT wp{ sizeof(WINDOWPLACEMENT) };
  if (::GetWindowPlacement(hwnd, &wp)) {
    const RECT& n = wp.rcNormalPosition;  // restored rect, NOT maximized
    SaveWindowState({ n.left, n.top,
                      n.right - n.left, n.bottom - n.top,
                      ::GetDpiForWindow(hwnd) });
  }
  break;  // 让 DefWindowProc 继续 DestroyWindow
}
```

## Acceptance Criteria

- [ ] 删除 `%APPDATA%\fl_picraft\window_state.ini` 后启动，窗口 ≈ 主屏工作区 80% 居中（taskbar 已排除）。
- [ ] 拖拽 resize → 退出 → 再启动 → 恢复尺寸 + 位置。
- [ ] 拖窗口边角缩小至 client area < 1280×800 → 卡住（不同 DPI 缩放下都生效）。
- [ ] 最大化（双击标题栏）→ 退出 → 再启动 → 恢复到 maximized 之前的尺寸（`rcNormalPosition` 行为）。
- [ ] 切换显示器 DPI 缩放 100% → 150% → 重启 → 窗口尺寸合理，未异常变小/变大。
- [ ] 拔掉外接屏 → 重启 → 窗口落到主屏（`IsRectVisibleOnAnyMonitor` 兜底）。
- [ ] `flutter build windows` 成功；`shcore.lib` 与 `shell32.lib` 都已链接。

## Out of Scope

- 注册表替代 INI。
- maximized / fullscreen 状态持久化（只持久化 normal 尺寸位置）。
- WM_QUERYENDSESSION / WM_ENDSESSION 在 Windows shutdown 时保存（不在 AC 内）。
- 自适应 DPI 重缩放（保存物理像素，跨机直接还原物理像素；用户可自行 resize）。

## Smoke Verify Script

```cmd
rmdir /s /q "%APPDATA%\fl_picraft"
flutter run -d windows
:: 期望 80% 居中
:: resize 并退出，再 flutter run → 恢复
```
