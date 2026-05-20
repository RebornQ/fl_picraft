#include "window_state.h"

#include <knownfolders.h>
#include <shellscalingapi.h>
#include <shlobj.h>

#include <climits>
#include <cstdlib>  // wcstol
#include <string>

namespace {

constexpr const wchar_t kAppFolder[] = L"fl_picraft";
constexpr const wchar_t kStateFile[] = L"window_state.ini";
constexpr const wchar_t kSection[] = L"Window";

// Mirrors the WM_GETMINMAXINFO floor in win32_window.cpp. Kept here as a
// cross-platform-aligned defensive clamp so the 80%-of-work-area default
// can never fall below the minimum on an unusually small primary monitor.
constexpr int kMinClientWidth = 1280;
constexpr int kMinClientHeight = 800;

std::wstring AppendPath(const std::wstring& base, const wchar_t* leaf) {
  std::wstring result = base;
  if (!result.empty() && result.back() != L'\\') {
    result += L'\\';
  }
  result += leaf;
  return result;
}

int ReadInt(const wchar_t* key, int fallback, const std::wstring& file) {
  // We use GetPrivateProfileStringW + wcstol (NOT GetPrivateProfileIntW),
  // because GetPrivateProfileIntW silently coerces any negative value to
  // zero per its docs ("If the value of the key is less than zero, the
  // return value is zero"). That would corrupt window positions on
  // secondary monitors placed left or above the primary monitor (where
  // virtual-screen coordinates are negative).
  //
  // Returns |fallback| when:
  //   - the key is missing (empty buffer after default fill), or
  //   - the value is not a well-formed signed decimal integer
  //     (no digits, or trailing non-digit garbage).
  constexpr DWORD kBufSize = 32;  // 32-bit signed dec + sign + NUL fits
  wchar_t buf[kBufSize] = L"";
  ::GetPrivateProfileStringW(kSection, key, L"", buf, kBufSize, file.c_str());
  if (buf[0] == L'\0') {
    return fallback;
  }
  wchar_t* end = nullptr;
  long val = ::wcstol(buf, &end, 10);
  if (end == buf || *end != L'\0') {
    return fallback;
  }
  return static_cast<int>(val);
}

struct VisibilityCheckCtx {
  RECT target;
  LONG overlap_area;
};

BOOL CALLBACK VisibilityEnumProc(HMONITOR mon, HDC, LPRECT, LPARAM lparam) {
  auto* ctx = reinterpret_cast<VisibilityCheckCtx*>(lparam);
  MONITORINFO mi{};
  mi.cbSize = sizeof(MONITORINFO);
  if (!::GetMonitorInfoW(mon, &mi)) {
    return TRUE;
  }
  RECT inter{};
  if (::IntersectRect(&inter, &ctx->target, &mi.rcWork)) {
    LONG w = inter.right - inter.left;
    LONG h = inter.bottom - inter.top;
    if (w > 0 && h > 0) {
      ctx->overlap_area += w * h;
    }
  }
  return TRUE;  // continue enumeration
}

}  // namespace

std::wstring GetWindowStateIniPath() {
  PWSTR roaming = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData,
                                    KF_FLAG_CREATE,  // create %APPDATA% if absent
                                    nullptr, &roaming))) {
    return L"";
  }
  std::wstring app_dir = AppendPath(roaming, kAppFolder);
  ::CoTaskMemFree(roaming);

  // Idempotent directory creation. Ignore "already exists".
  if (!::CreateDirectoryW(app_dir.c_str(), nullptr) &&
      ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return L"";
  }
  return AppendPath(app_dir, kStateFile);
}

std::optional<WindowState> LoadWindowState() {
  std::wstring path = GetWindowStateIniPath();
  if (path.empty()) {
    return std::nullopt;
  }

  // Sentinel for "key missing". Any value outside the validated range
  // below is rejected regardless of whether it hit the sentinel.
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
  if (path.empty()) {
    return false;
  }

  auto WriteKey = [&](const wchar_t* k, int v) -> bool {
    std::wstring buf = std::to_wstring(v);
    return ::WritePrivateProfileStringW(kSection, k, buf.c_str(),
                                        path.c_str()) != 0;
  };

  // Use boolean variables (not short-circuit AND) so every key write is
  // attempted even if an earlier one failed — keeps the file maximally
  // populated for next-launch recovery.
  bool ok_x = WriteKey(L"X", s.x);
  bool ok_y = WriteKey(L"Y", s.y);
  bool ok_w = WriteKey(L"Width", s.width);
  bool ok_h = WriteKey(L"Height", s.height);
  bool ok_d = WriteKey(L"Dpi", static_cast<int>(s.dpi));

  // Flush write-cache per WritePrivateProfileString remarks. Without this
  // a quick shutdown can lose the last write.
  ::WritePrivateProfileStringW(nullptr, nullptr, nullptr, path.c_str());

  return ok_x && ok_y && ok_w && ok_h && ok_d;
}

WindowState ComputeDefaultRectOnPrimaryMonitor(double fraction) {
  // Primary monitor = the one containing (0,0) in virtual-screen coords.
  HMONITOR mon = ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{};
  mi.cbSize = sizeof(MONITORINFO);
  if (!::GetMonitorInfoW(mon, &mi)) {
    // Extremely unusual — fall back to a 1280x800 window at (0,0) on a
    // notional 96-DPI monitor. Keeps the app launchable even with a
    // misbehaving display driver.
    return WindowState{0, 0, kMinClientWidth, kMinClientHeight, 96};
  }
  // rcWork excludes taskbar / appbars; in PMv2 these are physical pixels.
  LONG work_w = mi.rcWork.right - mi.rcWork.left;
  LONG work_h = mi.rcWork.bottom - mi.rcWork.top;

  UINT dpi_x = 96, dpi_y = 96;
  // GetDpiForMonitor lives in shcore.dll (linked via shcore.lib).
  ::GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y);
  double scale = dpi_x / 96.0;
  if (scale <= 0.0) {
    scale = 1.0;
  }

  // Defensive clamp: never let the 80% default drop below the minimum
  // client size (DPI-scaled to physical pixels). Mirrors macOS/Linux.
  int min_physical_w = static_cast<int>(kMinClientWidth * scale);
  int min_physical_h = static_cast<int>(kMinClientHeight * scale);
  int desired_w = static_cast<int>(work_w * fraction);
  int desired_h = static_cast<int>(work_h * fraction);
  if (desired_w < min_physical_w) {
    desired_w = min_physical_w;
  }
  if (desired_h < min_physical_h) {
    desired_h = min_physical_h;
  }
  // If the clamp pushed us above the work area (truly tiny monitor),
  // cap at the work area so the window fits.
  if (desired_w > work_w) {
    desired_w = work_w;
  }
  if (desired_h > work_h) {
    desired_h = work_h;
  }

  int x = mi.rcWork.left + (work_w - desired_w) / 2;
  int y = mi.rcWork.top + (work_h - desired_h) / 2;

  return WindowState{x, y, desired_w, desired_h, dpi_x};
}

bool IsRectVisibleOnAnyMonitor(const WindowState& s) {
  VisibilityCheckCtx ctx{
      RECT{s.x, s.y, s.x + s.width, s.y + s.height}, 0};
  ::EnumDisplayMonitors(nullptr, nullptr, VisibilityEnumProc,
                        reinterpret_cast<LPARAM>(&ctx));
  // Require >= 100x100 visible pixels — small enough that a partially
  // off-screen window is OK, large enough that a stale rect on a removed
  // monitor is rejected.
  return ctx.overlap_area >= 100 * 100;
}
