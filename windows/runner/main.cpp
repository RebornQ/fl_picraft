#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellscalingapi.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "window_state.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Decide the initial outer rect in PHYSICAL pixels:
  // 1. Start with 80% of the primary monitor's work area, centered.
  // 2. Override with a persisted rect if one exists AND still intersects
  //    a currently-attached monitor (i.e. the saved monitor wasn't
  //    unplugged between sessions).
  WindowState initial = ComputeDefaultRectOnPrimaryMonitor(0.8);
  if (auto saved = LoadWindowState();
      saved && IsRectVisibleOnAnyMonitor(*saved)) {
    initial = *saved;
  }

  // Win32Window::Create() expects LOGICAL (96-DPI) pixels — it re-scales
  // internally using the DPI of the monitor at |origin|. Compute scale
  // from the DPI of the monitor at |initial|'s origin so the round-trip
  // preserves the physical size we intend.
  POINT origin_pt = {initial.x, initial.y};
  HMONITOR target_mon =
      ::MonitorFromPoint(origin_pt, MONITOR_DEFAULTTONEAREST);
  UINT target_dpi_x = 96, target_dpi_y = 96;
  ::GetDpiForMonitor(target_mon, MDT_EFFECTIVE_DPI, &target_dpi_x,
                     &target_dpi_y);
  double scale = target_dpi_x / 96.0;
  if (scale <= 0.0) {
    scale = 1.0;
  }

  // Win32Window::Point uses unsigned int; clamp negatives to 0. A saved
  // origin on a secondary monitor positioned left/above primary would
  // otherwise wrap to a huge positive value and produce a garbage
  // window position. Degrading to (0,0) lands the window on primary,
  // visible — better than the wrap-around. A full multi-monitor solution
  // would refactor Win32Window::Create to accept signed physical coords;
  // out of scope for this change.
  auto NonNeg = [](double v) -> unsigned int {
    if (v < 0.0) {
      return 0u;
    }
    // Cap well below INT_MAX so Win32Window::Create's internal
    // Scale(x, scale_factor) cast-to-int can't overflow.
    if (v > 100000.0) {
      return 100000u;
    }
    return static_cast<unsigned int>(v);
  };

  FlutterWindow window(project);
  Win32Window::Point origin(NonNeg(initial.x / scale),
                            NonNeg(initial.y / scale));
  Win32Window::Size size(
      static_cast<unsigned int>(initial.width / scale),
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
