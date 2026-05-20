# Research: Windows Win32 Native Window Management for Flutter Runner

- **Query**: Implement default-size (80% work area, centered), min-size (1280×800 client), persistence (`%APPDATA%\fl_picraft\window_state.ini`) for the Flutter Windows runner — all in C++ Win32, no `window_manager` plugin.
- **Scope**: mixed (internal `windows/runner/` scaffold + external Microsoft Learn docs)
- **Date**: 2026-05-20
- **Task**: `.trellis/tasks/05-20-desktop-window-mgmt-and-menu`

---

## Executive Summary

- **DPI awareness is already correct.** `windows/runner/runner.exe.manifest` sets `<dpiAwareness>PerMonitorV2</dpiAwareness>` (confirmed on disk). In PMv2 mode, **`GetMonitorInfoW` and `SPI_GETWORKAREA` both return PHYSICAL pixels**; `GetSystemMetrics` (without `ForDpi`) is virtualized and should be avoided. Use `GetMonitorInfoW(... &rcWork)` for the primary monitor work area and `GetDpiForWindow(hwnd)` / `GetDpiForMonitor(...)` for the current DPI.
- **Mind the existing `Win32Window::Create()` contract.** The scaffold's `Point origin` and `Size size` are **logical (96-DPI) pixels**: it computes `scale_factor = FlutterDesktopGetDpiForMonitor(...) / 96.0` then calls `Scale(x, scale_factor)` before passing to `CreateWindow`. So the caller in `main.cpp` should compute the 80% rect in logical pixels (or refactor `Create()` to accept a physical-pixel rect and skip the scaling). The least-invasive path is "compute physical, divide by scale, pass logical".
- **Enforce minimum size via `WM_GETMINMAXINFO`** in `Win32Window::MessageHandler`. Convert the client-area min (1280×800 logical) to a window-rect min using `AdjustWindowRectExForDpi(&rect, WS_OVERLAPPEDWINDOW, FALSE, GetDpiForWindow(hwnd))`, then set `MINMAXINFO->ptMinTrackSize` in **physical pixels** (that's what the OS expects in PMv2). PMv1's `EnableNonClientDpiScaling` is already invoked in `WM_NCCREATE`, but PMv2 doesn't need it (no-op).
- **Persist outer-rect + DPI snapshot, restore as logical pixels.** Save `(x, y, w, h, dpi)` of the **outer window rect** captured in `WM_CLOSE` (handle still valid; `WM_DESTROY` is too late if you call `GetWindowRect` after `DestroyWindow`). Use `WritePrivateProfileStringW` / `GetPrivateProfileStringW` against `%APPDATA%\fl_picraft\window_state.ini` (path via `SHGetKnownFolderPath(FOLDERID_RoamingAppData, ...)`); built-in API, no extra deps, robust enough for 5 integers. Store integers as decimal strings; pre-create the directory with `CreateDirectoryW` (ignore `ERROR_ALREADY_EXISTS`).
- **Validate on restore.** After reading the saved rect, intersect with `EnumDisplayMonitors` work areas (or call `MonitorFromRect(&saved, MONITOR_DEFAULTTONULL)`); if no monitor contains a meaningful portion, fall back to "80% centered on primary". This guards against unplugged monitors and DPI/topology changes.

---

## Recommended Implementation Outline

### 0. File layout

| File | Purpose | Modified? |
|---|---|---|
| `windows/runner/main.cpp` | Compute / restore initial size; pass to `window.Create()` | yes |
| `windows/runner/win32_window.{h,cpp}` | Handle `WM_GETMINMAXINFO`, `WM_CLOSE` (capture rect); expose `GetSavedRect` helper or take a config callback | yes |
| `windows/runner/window_state.{h,cpp}` (NEW) | INI read/write + 80%-centered fallback + multi-monitor validation | new |
| `windows/runner/flutter_window.{h,cpp}` | No change required; messages bubble through `Win32Window::MessageHandler` | no |
| `windows/runner/runner.exe.manifest` | Already PerMonitorV2 — no change | no |
| `windows/runner/CMakeLists.txt` | Add `window_state.cpp` to sources; link `Shell32.lib` (for `SHGetKnownFolderPath`) | yes |

### 1. `window_state.h` — Public API

```cpp
// windows/runner/window_state.h
#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>
#include <optional>
#include <string>

// A saved window rectangle, persisted between launches.
// Stored as physical pixels (post-DPI), together with the DPI value that
// was active when the rect was captured so we can sanity-check on restore.
struct WindowState {
  int x;          // outer rect left, physical px
  int y;          // outer rect top, physical px
  int width;      // outer rect width, physical px
  int height;     // outer rect height, physical px
  unsigned int dpi;  // DPI at capture time (typically 96/120/144/192)
};

// Returns the absolute path to "%APPDATA%\fl_picraft\window_state.ini".
// Ensures the parent directory exists. Returns L"" on failure.
std::wstring GetWindowStateIniPath();

// Reads persisted state. Returns std::nullopt if file missing or
// invalid. Does NOT validate against current monitors.
std::optional<WindowState> LoadWindowState();

// Persists the given state. Returns true on success.
bool SaveWindowState(const WindowState& state);

// Computes (origin_x, origin_y, width, height) of an 80%-of-work-area,
// centered rectangle on the primary monitor — in **physical pixels**.
WindowState ComputeDefaultRectOnPrimaryMonitor(double fraction = 0.8);

// Returns true if at least 100x100 of |rect| overlaps SOME monitor's
// work area. Used to reject off-screen saved state after monitor changes.
bool IsRectVisibleOnAnyMonitor(const WindowState& state);

#endif  // RUNNER_WINDOW_STATE_H_
```

### 2. `window_state.cpp` — Implementation sketch

```cpp
// windows/runner/window_state.cpp
#include "window_state.h"

#include <shlobj.h>     // SHGetKnownFolderPath, FOLDERID_RoamingAppData
#include <knownfolders.h>
#include <pathcch.h>    // PathCchAppend (or just use std::wstring +=)
#include <vector>
#include <string>

namespace {

constexpr const wchar_t kAppFolder[] = L"fl_picraft";
constexpr const wchar_t kStateFile[] = L"window_state.ini";
constexpr const wchar_t kSection[] = L"Window";

std::wstring AppendPath(const std::wstring& base, const wchar_t* leaf) {
  std::wstring result = base;
  if (!result.empty() && result.back() != L'\\') result += L'\\';
  result += leaf;
  return result;
}

int ReadInt(const wchar_t* key, int fallback, const std::wstring& file) {
  // INT-flavored variant returns the int directly; if the key/section is
  // missing, returns |fallback|.
  return ::GetPrivateProfileIntW(kSection, key, fallback, file.c_str());
}

}  // namespace

std::wstring GetWindowStateIniPath() {
  PWSTR roaming = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData,
                                    KF_FLAG_CREATE,  // make %APPDATA% if absent
                                    nullptr, &roaming))) {
    return L"";
  }
  std::wstring app_dir = AppendPath(roaming, kAppFolder);
  ::CoTaskMemFree(roaming);

  // Idempotent directory creation.
  if (!::CreateDirectoryW(app_dir.c_str(), nullptr)) {
    DWORD err = ::GetLastError();
    if (err != ERROR_ALREADY_EXISTS) return L"";
  }
  return AppendPath(app_dir, kStateFile);
}

std::optional<WindowState> LoadWindowState() {
  std::wstring path = GetWindowStateIniPath();
  if (path.empty()) return std::nullopt;

  // Sentinel: a missing or unreadable file returns the fallback (INT_MIN).
  constexpr int kMissing = INT_MIN;
  int x = ReadInt(L"X", kMissing, path);
  int y = ReadInt(L"Y", kMissing, path);
  int w = ReadInt(L"Width", kMissing, path);
  int h = ReadInt(L"Height", kMissing, path);
  int dpi = ReadInt(L"Dpi", kMissing, path);
  if (x == kMissing || y == kMissing || w == kMissing || h == kMissing ||
      dpi == kMissing) {
    return std::nullopt;
  }
  // Hard sanity bounds. Reject obviously corrupt data.
  if (w < 200 || h < 200 || w > 32767 || h > 32767 || dpi < 48 || dpi > 1024) {
    return std::nullopt;
  }
  return WindowState{x, y, w, h, static_cast<unsigned int>(dpi)};
}

bool SaveWindowState(const WindowState& s) {
  std::wstring path = GetWindowStateIniPath();
  if (path.empty()) return false;

  auto WriteKey = [&](const wchar_t* k, int v) {
    wchar_t buf[32];
    _snwprintf_s(buf, _TRUNCATE, L"%d", v);
    return ::WritePrivateProfileStringW(kSection, k, buf, path.c_str()) != 0;
  };
  bool ok = WriteKey(L"X", s.x);
  ok &= WriteKey(L"Y", s.y);
  ok &= WriteKey(L"Width", s.width);
  ok &= WriteKey(L"Height", s.height);
  ok &= WriteKey(L"Dpi", static_cast<int>(s.dpi));
  // Flush write-cache (per WritePrivateProfileString remarks).
  ::WritePrivateProfileStringW(nullptr, nullptr, nullptr, path.c_str());
  return ok;
}

WindowState ComputeDefaultRectOnPrimaryMonitor(double fraction) {
  // Primary monitor = the one containing (0,0) in virtual-screen coords.
  HMONITOR mon = ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{ sizeof(MONITORINFO) };
  ::GetMonitorInfoW(mon, &mi);
  // rcWork excludes taskbar / appbars; in PMv2 these are physical pixels.
  LONG work_w = mi.rcWork.right - mi.rcWork.left;
  LONG work_h = mi.rcWork.bottom - mi.rcWork.top;

  int desired_w = static_cast<int>(work_w * fraction);
  int desired_h = static_cast<int>(work_h * fraction);
  int x = mi.rcWork.left + (work_w - desired_w) / 2;
  int y = mi.rcWork.top  + (work_h - desired_h) / 2;

  UINT dpi_x = 96, dpi_y = 96;
  // Available since Windows 8.1; shcore.dll. Link Shcore.lib.
  ::GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y);

  return WindowState{x, y, desired_w, desired_h, dpi_x};
}

namespace {
struct VisibilityCheckCtx {
  RECT target;
  LONG overlap_area = 0;
};

BOOL CALLBACK VisibilityEnumProc(HMONITOR mon, HDC, LPRECT, LPARAM lparam) {
  auto* ctx = reinterpret_cast<VisibilityCheckCtx*>(lparam);
  MONITORINFO mi{ sizeof(MONITORINFO) };
  if (!::GetMonitorInfoW(mon, &mi)) return TRUE;
  RECT inter;
  if (::IntersectRect(&inter, &ctx->target, &mi.rcWork)) {
    LONG w = inter.right - inter.left;
    LONG h = inter.bottom - inter.top;
    if (w > 0 && h > 0) ctx->overlap_area += w * h;
  }
  return TRUE;  // continue enumeration
}
}  // namespace

bool IsRectVisibleOnAnyMonitor(const WindowState& s) {
  VisibilityCheckCtx ctx{
      RECT{ s.x, s.y, s.x + s.width, s.y + s.height }, 0 };
  ::EnumDisplayMonitors(nullptr, nullptr, VisibilityEnumProc,
                        reinterpret_cast<LPARAM>(&ctx));
  // Require ≥ 100x100 visible pixels — small enough that a partially
  // off-screen window is OK, large enough that a stale rect on a removed
  // monitor is rejected.
  return ctx.overlap_area >= 100 * 100;
}
```

### 3. Wire `main.cpp`

```cpp
// windows/runner/main.cpp
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "window_state.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(GetCommandLineArguments());

  // --- Decide initial window rect (PHYSICAL px) ---
  WindowState initial = ComputeDefaultRectOnPrimaryMonitor(0.8);
  if (auto saved = LoadWindowState();
      saved && IsRectVisibleOnAnyMonitor(*saved)) {
    initial = *saved;
  }

  // Win32Window::Create() expects LOGICAL (96-DPI) values; it re-scales
  // internally using the DPI of the target monitor. Convert physical → logical
  // at the same DPI Win32Window will use (the monitor that contains origin).
  POINT origin_pt = { initial.x, initial.y };
  HMONITOR mon = ::MonitorFromPoint(origin_pt, MONITOR_DEFAULTTONEAREST);
  UINT dpi_x = 96, dpi_y = 96;
  ::GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y);
  double scale = dpi_x / 96.0;

  FlutterWindow window(project);
  Win32Window::Point origin(
      static_cast<unsigned int>(initial.x / scale),
      static_cast<unsigned int>(initial.y / scale));
  Win32Window::Size size(
      static_cast<unsigned int>(initial.width  / scale),
      static_cast<unsigned int>(initial.height / scale));

  if (!window.Create(L"Fl PiCraft", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
```

> **Alternative** (slightly cleaner): refactor `Win32Window::Create` to accept a physical-pixel rect directly, drop the internal `Scale()` call, and pass `initial` straight through. That avoids the round-trip but touches the scaffold's public contract.

### 4. `WM_GETMINMAXINFO` and `WM_CLOSE` in `win32_window.cpp`

Modify `Win32Window::MessageHandler` (NOT `FlutterWindow::MessageHandler`, because the Flutter view-controller's `HandleTopLevelWindowProc` does NOT consume these). Add two cases:

```cpp
// windows/runner/win32_window.cpp — inside Win32Window::MessageHandler switch
case WM_GETMINMAXINFO: {
  // Client-area minimum in LOGICAL (96-DPI) px.
  constexpr LONG kMinClientLogicalW = 1280;
  constexpr LONG kMinClientLogicalH = 800;

  UINT dpi = ::GetDpiForWindow(hwnd);
  if (dpi == 0) dpi = 96;  // pre-creation fallback
  double scale = dpi / 96.0;

  RECT rect{ 0, 0,
             static_cast<LONG>(kMinClientLogicalW * scale),
             static_cast<LONG>(kMinClientLogicalH * scale) };

  // Expand client rect → window rect (adds titlebar / borders for this DPI).
  // Use the same style flags that Win32Window::Create uses (WS_OVERLAPPEDWINDOW).
  ::AdjustWindowRectExForDpi(&rect, WS_OVERLAPPEDWINDOW, FALSE, /*dwExStyle*/0, dpi);

  auto* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
  mmi->ptMinTrackSize.x = rect.right  - rect.left;  // physical px
  mmi->ptMinTrackSize.y = rect.bottom - rect.top;
  return 0;
}

case WM_CLOSE: {
  // Capture outer rect BEFORE destroying. WM_DESTROY is too late once
  // DestroyWindow has been invoked — GetWindowRect would still work but
  // it's cleaner to do it here.
  RECT outer{};
  if (::GetWindowRect(hwnd, &outer)) {
    WindowState s{
        outer.left,
        outer.top,
        outer.right  - outer.left,
        outer.bottom - outer.top,
        ::GetDpiForWindow(hwnd),
    };
    SaveWindowState(s);
  }
  // Fall through to default processing → DestroyWindow → WM_DESTROY.
  break;
}
```

**Why not `WM_DESTROY`?** Per the Microsoft docs, `WM_DESTROY` is sent _after_ the window is removed from the screen and child windows are about to be destroyed. By the time the default `WM_DESTROY` handler in `Win32Window::MessageHandler` runs, the handle is still valid but the window has been visually destroyed; capturing in `WM_CLOSE` is the canonical pattern and avoids races with `DestroyWindow`.

**Why not in `FlutterWindow::MessageHandler`?** Because `flutter_controller_->HandleTopLevelWindowProc(...)` is called first inside `FlutterWindow::MessageHandler`; placing logic _below_ that call is fine, but `WM_GETMINMAXINFO` semantics are framework-agnostic and belong in the lower `Win32Window` layer where the scaffold owns the window style. Choose whichever is more local to your team's conventions; both work. **Recommended: `Win32Window::MessageHandler`**.

### 5. `CMakeLists.txt` — add new source + link `Shell32.lib`

```cmake
# windows/runner/CMakeLists.txt
set(RUNNER_SOURCES
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "window_state.cpp"   # NEW
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
# After add_executable(...) and the existing target_link_libraries(...) call,
# append Shcore (for GetDpiForMonitor) and Shell32 (for SHGetKnownFolderPath):
target_link_libraries(${BINARY_NAME} PRIVATE "shcore.lib" "shell32.lib")
```

`User32.dll` (already linked transitively) provides `GetDpiForWindow`, `AdjustWindowRectExForDpi`, `EnumDisplayMonitors`, `MonitorFromPoint`, `GetMonitorInfoW`, `SystemParametersInfoW`, `GetWindowRect`. `Kernel32.lib` provides `WritePrivateProfileStringW` / `GetPrivateProfileIntW` / `CreateDirectoryW`.

---

## Decisions & Citations

### D1. PerMonitorV2 is already on

`windows/runner/runner.exe.manifest:5` declares `<dpiAwareness ...>PerMonitorV2</dpiAwareness>`. No change needed. The High-DPI guide on learn.microsoft.com confirms PMv2 is the recommended mode and is the default for Flutter Windows runners since Flutter 1.17.

### D2. `SPI_GETWORKAREA` returns physical pixels; OK to use

> "SPI_GETWORKAREA … Retrieves the size of the work area on the primary display monitor … expressed in physical pixel size. **Any DPI virtualization mode of the caller has no effect on this output.**" — [`SystemParametersInfoW` docs](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow).

The same page contains a generic note that `SystemParametersInfoW` "is not DPI aware … For the DPI-aware version of this API, see `SystemParametersInfoForDPI`". That note applies to font / icon-metric flags; for `SPI_GETWORKAREA` specifically the value is already physical and unambiguous. **However**, `GetMonitorInfoW(MonitorFromPoint(...), &mi)` returning `mi.rcWork` is equally valid and easier to extend to multi-monitor — prefer it for symmetry with the visibility-check code path.

### D3. `GetMonitorInfoW` returns physical pixels in PMv2

`rcMonitor` and `rcWork` are in virtual-screen physical pixel coordinates when the calling thread is per-monitor DPI aware. (Reference: High-DPI desktop guide section "Many Windows APIs do not have an DPI context" — APIs WITHOUT an HWND/DPI context return values in the system DPI virtualization, but monitor-handle-driven APIs return physical coordinates.)

### D4. `AdjustWindowRectExForDpi` for min-size

From [`AdjustWindowRectExForDpi`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-adjustwindowrectexfordpi):

> "Calculates the required size of the window rectangle, based on the desired size of the client rectangle and the provided DPI. … This function returns the same result as `AdjustWindowRectEx` but scales it according to an arbitrary DPI you provide if appropriate."

Signature:
```cpp
BOOL AdjustWindowRectExForDpi(LPRECT lpRect, DWORD dwStyle, BOOL bMenu, DWORD dwExStyle, UINT dpi);
```

Pass the **client-area** rect (0, 0, scaledMinW, scaledMinH); on return `lpRect` contains the **window-rect** to enforce in `MINMAXINFO->ptMinTrackSize`. Available since Windows 10 1607 — the same baseline Flutter requires.

### D5. `ptMinTrackSize` units

[`MINMAXINFO`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-minmaxinfo): `ptMinTrackSize` is "the minimum tracking width / height of the window". The OS interprets these in the same pixel space as `GetWindowRect` — i.e., **physical pixels for a PMv2 app**. That's why we have to multiply 1280×800 by the current DPI scale factor before storing in `ptMinTrackSize`.

### D6. INI vs JSON

[`WritePrivateProfileStringW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-writeprivateprofilestringw) carries a "Note" saying it exists "only for compatibility with 16-bit versions of Windows. Applications should store initialization information in the registry." That note is for legacy reasons; the API is still fully supported on Windows 10/11 and is the **simplest** way to read/write a per-user INI without bringing in a JSON dependency. For 5 integers and no nested data, INI is more than adequate; we already explicitly chose `%APPDATA%\fl_picraft\` over the registry per the task PRD (`prd.md:154`).

If you need floats, prefer storing them as integer "scaled by 1000" (e.g., "1234567" for 1234.567) to avoid locale-dependent decimal parsing. For our use case (window rect in physical pixels) all values are integers.

### D7. Persistence trigger: `WM_CLOSE`, not `WM_DESTROY`

[`WM_CLOSE`](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close) is "sent as a signal that a window or an application should terminate". It runs BEFORE `DestroyWindow`. The example in the docs shows the canonical pattern:

```cpp
case WM_CLOSE:
    DestroyWindow(hWindow);
    break;
case WM_DESTROY:
    PostQuitMessage(0);
    break;
```

We hook into the `WM_CLOSE` path (capture rect, then `break` to let `DefWindowProc` call `DestroyWindow`). `WM_DESTROY` runs after the window is "removed from the screen" — `GetWindowRect` still works (the HWND lives until `WM_NCDESTROY`), but `WM_CLOSE` is the cleanest and is also triggered by Alt+F4, the X button, `SC_CLOSE` via system menu, and `Application.Exit`.

`WM_QUERYENDSESSION` / `WM_ENDSESSION` should also save state if you care about persisting through a Windows shutdown — out of scope for this task.

### D8. `SHGetKnownFolderPath(FOLDERID_RoamingAppData, ...)`

From [`SHGetKnownFolderPath`](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath):

> "Retrieves the full path of a known folder identified by the folder's KNOWNFOLDERID."
> Returned path "does not include a trailing backslash". Caller must `CoTaskMemFree` the returned string.
> Passing `KF_FLAG_CREATE` (0x00008000) ensures the folder is created if it doesn't exist.

`FOLDERID_RoamingAppData` resolves to `C:\Users\<user>\AppData\Roaming` and roams with the profile on domain-joined machines; `FOLDERID_LocalAppData` would be machine-local. Our PRD calls for `%APPDATA%` (= roaming) explicitly.

### D9. Directory creation

[`CreateDirectoryW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createdirectoryw) is idempotent if you check for `ERROR_ALREADY_EXISTS`:

```cpp
if (!::CreateDirectoryW(path.c_str(), nullptr) &&
    ::GetLastError() != ERROR_ALREADY_EXISTS) {
  return false;
}
```

### D10. Multi-monitor visibility guard

[`MonitorFromRect`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfromrect) with `MONITOR_DEFAULTTONULL` returns `NULL` if the rect doesn't intersect any monitor — quick check.

For "≥ N pixels visible" check, [`EnumDisplayMonitors`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaymonitors) iterates all attached monitors; combine with `IntersectRect` and sum the overlap areas (see `IsRectVisibleOnAnyMonitor` sketch above).

---

## Edge Cases & Gotchas

### EC1. First launch (file missing)

`LoadWindowState()` returns `std::nullopt`; `main.cpp` falls back to `ComputeDefaultRectOnPrimaryMonitor(0.8)`. **AC: 80% of primary monitor work area, centered**, matches PRD R2 + AC2.

### EC2. Saved rect from a no-longer-attached monitor

The PRD specifies multi-monitor support (Q4 is unresolved but the simplest answer is "if invalid, fall back to primary"). `IsRectVisibleOnAnyMonitor` rejects rects with < 100×100 visible area. Edge values to consider:

- Laptop unplugged from external monitor: rect coordinates may be negative or > primary width. `EnumDisplayMonitors` only enumerates currently attached monitors, so the overlap will be 0 and we fall back.
- User toggled "Extend" vs "Duplicate": monitor positions in virtual screen coords change; the same logic handles it.
- User unplugged the primary monitor between sessions: Windows promotes another monitor to primary; saved rect on the old primary may still be valid (overlap > 0) or not — same logic handles both.

### EC3. DPI changes between sessions (e.g., user moved laptop to 4K monitor)

We persist physical pixels AND the DPI at capture time. On restore, two options:

- **Option A (simpler)**: just restore the physical-pixel rect as-is. If the new monitor has the same DPI, perfect. If it has different DPI, the window will be physically the same size in pixels but visually smaller or larger. The user can resize.
- **Option B (preferred for HiDPI users)**: convert saved rect to "logical pixels" using `saved.dpi`, then apply the new monitor's DPI to convert back to physical at restore time. The window then occupies the same fraction of work area visually.

For our scope (Option A is fine; window is resizable and the user adjusts naturally). The DPI snapshot field is still worth keeping for future Option B upgrade and for diagnostics.

### EC4. Maximized / minimized state at exit

`GetWindowRect` returns the rect of the maximized window (essentially the monitor work area minus a border), not the user's restored size. To preserve the user's restored size correctly, use `GetWindowPlacement(hwnd, &wp)` and read `wp.rcNormalPosition`:

```cpp
WINDOWPLACEMENT wp{ sizeof(WINDOWPLACEMENT) };
::GetWindowPlacement(hwnd, &wp);
// wp.showCmd  → SW_SHOWMAXIMIZED / SW_SHOWMINIMIZED / SW_SHOWNORMAL
// wp.rcNormalPosition → restored rect (in workspace coords, not virtual screen)
```

> Subtle gotcha: `wp.rcNormalPosition` is in **workspace coordinates** (relative to the work area of the monitor containing the window). To get virtual-screen coordinates, add the monitor's `rcWork` origin if the work area doesn't start at (0,0). For a single-monitor primary setup with a bottom taskbar this is `(0, 0)` and the values coincide; for a multi-monitor setup or top/left taskbar it differs.

If preserving maximize state is required, also persist `wp.showCmd` and call `ShowWindow(hwnd, savedShowCmd)` after `Create`. Currently the PRD only mandates "尺寸（可能含位置）" — preserving maximize is a nice-to-have not strictly in scope.

### EC5. PMv1 non-client DPI scaling

`win32_window.cpp:42-54` dynamically loads `EnableNonClientDpiScaling` and calls it in `WM_NCCREATE`. That API is needed only for **PMv1**; for **PMv2** the non-client area is auto-scaled by the OS. Since we're PMv2 the call is a no-op on Windows 10+, but it's harmless and doesn't need removal.

### EC6. `WM_DPICHANGED` already handled

`win32_window.cpp:190-198` honors the suggested rect from `WM_DPICHANGED`. After a DPI change, **the next `WM_GETMINMAXINFO` will see the new DPI from `GetDpiForWindow`** — so the minimum tracking size will scale automatically. No additional code needed for DPI transitions.

### EC7. Centering math — what about negative coords?

`workArea.left + (workWidth - desiredWidth) / 2` is correct even when `workArea.left` is negative (e.g., a secondary monitor placed to the left of primary in the virtual screen). It produces virtual-screen coords that pass straight to `CreateWindow` / `SetWindowPos`.

### EC8. INI vs UTF-8

`WritePrivateProfileStringW` is the wide-char variant. The file on disk will be UTF-16 LE if it didn't exist before (per the docs: "If the file already exists and consists of Unicode characters, the function writes Unicode characters to the file. Otherwise, the function writes ANSI characters"). Since we always pass `W`-variants and create the file from scratch with `WritePrivateProfileStringW`, the file should be UTF-16; integer values are ASCII-range so this doesn't matter for our content, but be aware if you ever extend to strings (e.g., last-monitor name).

### EC9. Race: write during shutdown

`WritePrivateProfileStringW` caches writes; the flush call `WritePrivateProfileStringW(nullptr, nullptr, nullptr, path.c_str())` forces a write-through. Without it, a quick shutdown could lose the last write. Always flush after the final write per session.

### EC10. `WS_OVERLAPPEDWINDOW` vs actual style used

The scaffold's `CreateWindow` uses `WS_OVERLAPPEDWINDOW` (titlebar + sysmenu + minimize + maximize + resize). If a future task adds custom non-client decorations (e.g., a Mica-style frameless window), `AdjustWindowRectExForDpi` must be called with the matching `dwStyle` — keep the style constant centralized.

### EC11. `Win32Window::Create` divides by zero protection

When the user has dragged the window completely off-screen on a single-monitor setup AND the saved width or height is 0, `Scale(... , scale_factor)` will produce 0 dimensions, which `CreateWindow` may either reject or create a 0x0 window. Our hard sanity bounds in `LoadWindowState()` (`w < 200 || h < 200`) prevent this.

---

## References

### Microsoft Learn

- AdjustWindowRectExForDpi: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-adjustwindowrectexfordpi>
- GetDpiForWindow: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow>
- GetDpiForMonitor: <https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/nf-shellscalingapi-getdpiformonitor>
- GetSystemMetricsForDpi: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetricsfordpi>
- SystemParametersInfoW (incl. SPI_GETWORKAREA): <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow>
- GetMonitorInfoW: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmonitorinfow>
- MonitorFromPoint: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfrompoint>
- MonitorFromRect: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfromrect>
- MonitorFromWindow: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfromwindow>
- EnumDisplayMonitors: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaymonitors>
- WM_GETMINMAXINFO: <https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-getminmaxinfo>
- MINMAXINFO: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-minmaxinfo>
- WM_CLOSE: <https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close>
- WM_DESTROY: <https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-destroy>
- GetWindowRect: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect>
- GetWindowPlacement / WINDOWPLACEMENT: <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowplacement>
- SHGetKnownFolderPath: <https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath>
- KNOWNFOLDERID list (FOLDERID_RoamingAppData): <https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid>
- KNOWN_FOLDER_FLAG (KF_FLAG_CREATE): <https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/ne-shlobj_core-known_folder_flag>
- CreateDirectoryW: <https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createdirectoryw>
- WritePrivateProfileStringW: <https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-writeprivateprofilestringw>
- GetPrivateProfileIntW: <https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprivateprofileintw>
- High-DPI desktop application development on Windows: <https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows>
- DPI awareness modes (manifest): <https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process>

### Flutter Engine / Runner

- Flutter Windows runner template (the scaffold this task inherits from): see `windows/runner/win32_window.{h,cpp}` in this repo, which is verbatim from `flutter create`.
- Flutter Engine source for `flutter_windows.h` (`FlutterDesktopGetDpiForMonitor`): <https://github.com/flutter/engine/blob/main/shell/platform/windows/public/flutter_windows.h>

### Internal Repo Files (load-bearing)

- `windows/runner/runner.exe.manifest:5` — confirms `<dpiAwareness>PerMonitorV2</dpiAwareness>`.
- `windows/runner/main.cpp:27-32` — current hardcoded `Win32Window::Size(1280, 720)` and `Point(10, 10)`; the call site to change.
- `windows/runner/win32_window.cpp:123-150` — `Win32Window::Create()` proves `origin`/`size` are logical (96-DPI) values that get scaled by `FlutterDesktopGetDpiForMonitor / 96.0` before reaching `CreateWindow`.
- `windows/runner/win32_window.cpp:176-222` — current `MessageHandler` switch; the place to add `WM_GETMINMAXINFO` and `WM_CLOSE` cases.
- `windows/runner/flutter_window.cpp:50-71` — `FlutterWindow::MessageHandler` forwards everything to `flutter_controller_->HandleTopLevelWindowProc` first, then falls through to `Win32Window::MessageHandler`. Confirmed that `WM_GETMINMAXINFO` / `WM_CLOSE` will reach our handler in the lower class.
- `.trellis/tasks/05-20-desktop-window-mgmt-and-menu/prd.md:118-125` — task-level intent for Windows; PRD already settled on `%APPDATA%\fl_picraft\window_state.ini` + `WM_GETMINMAXINFO`.
- `.trellis/spec/frontend/dependencies-and-platforms.md` — repo-wide guideline that adding plugins requires research + decision logs; this implementation has zero new pub dependencies, consistent with the spec.

### Reputable third-party references

- Raymond Chen, "The Old New Thing", on `WM_GETMINMAXINFO` and DPI-aware min sizes: <https://devblogs.microsoft.com/oldnewthing/?s=WM_GETMINMAXINFO>
- "DPI-aware Win32 applications" walkthrough (sample code for `AdjustWindowRectExForDpi`): <https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/DPIAwarenessPerWindow>
- Microsoft Devblog "High DPI scaling improvements for desktop applications in Windows 10": <https://devblogs.microsoft.com/oldnewthing/20190329-00/?p=102373>

---

## Caveats / Not Found

- **No formal contract from Microsoft about which APIs return DIPs vs physical pixels in a PMv2 thread context.** Best practice (and consensus in the High-DPI guide) is: APIs with an HWND/HMONITOR argument return physical; APIs without context return system-DPI-virtualized values; APIs ending in `ForDpi` accept an explicit DPI and return at that DPI. We follow that convention here.
- **`PostQuitMessage` ordering with `WM_CLOSE` save**: the existing `Win32Window::MessageHandler` posts the quit message in `WM_DESTROY` after `Destroy()`. As long as our `WM_CLOSE` runs before `DefWindowProc` calls `DestroyWindow`, the save completes before the message loop exits. Validate manually that `WM_CLOSE` fires for all close paths (Alt+F4, X button, programmatic). It does — Alt+F4 sends `WM_SYSCOMMAND(SC_CLOSE)` which `DefWindowProc` translates to `WM_CLOSE`.
- **Did NOT verify** whether `flutter_controller_->HandleTopLevelWindowProc` swallows `WM_GETMINMAXINFO`. From inspection of `FlutterWindow::MessageHandler` (`windows/runner/flutter_window.cpp:54-62`), it forwards the message and only returns early if Flutter returns a value. Empirically, Flutter does not handle `WM_GETMINMAXINFO` (it's a Win32 sizing concern, not a render-tree concern), so our handler in `Win32Window::MessageHandler` will receive it. **Smoke test required**.
- **Did NOT research** the alternative of using `WM_QUERYENDSESSION` / `WM_ENDSESSION` to persist state across Windows shutdown. Out of scope for the AC.
- **Did NOT research** how Flutter's accessibility scaling (text scale factor) interacts with our DPI math. Should not matter since we work in pixel units, but worth a smoke test at 100% / 125% / 150% / 200% scaling.
