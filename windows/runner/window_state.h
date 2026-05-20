#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

#include <optional>
#include <string>

// A saved window rectangle, persisted between launches.
//
// Stored as physical pixels (post-DPI), together with the DPI value that
// was active when the rect was captured so we can sanity-check on restore
// and (optionally) re-derive a logical size if needed.
struct WindowState {
  int x;             // outer rect left, physical px
  int y;             // outer rect top, physical px
  int width;         // outer rect width, physical px
  int height;        // outer rect height, physical px
  unsigned int dpi;  // DPI at capture time (typically 96/120/144/192)
};

// Returns the absolute path to "%APPDATA%\fl_picraft\window_state.ini".
// Ensures the parent directory exists. Returns an empty string on failure.
std::wstring GetWindowStateIniPath();

// Reads persisted state. Returns std::nullopt if the file is missing,
// any of the 5 expected keys is absent, or any value falls outside a
// sane range. Does NOT validate against current monitors — use
// IsRectVisibleOnAnyMonitor() for that.
std::optional<WindowState> LoadWindowState();

// Persists the given state to the INI file. Forces a write-cache flush
// before returning so an abrupt shutdown still lands the values on disk.
// Returns true on success.
bool SaveWindowState(const WindowState& state);

// Computes a centered rectangle at |fraction| (0.0–1.0) of the primary
// monitor's work area — in PHYSICAL pixels — paired with that monitor's
// DPI. The width/height are clamped so they never drop below the
// 1280x800 minimum client size (matters when the primary monitor is
// tiny, e.g. a 720p secondary promoted to primary).
WindowState ComputeDefaultRectOnPrimaryMonitor(double fraction = 0.8);

// Returns true if at least ~100x100 of |state|'s outer rect overlaps
// SOME currently-attached monitor's work area. Used to reject off-screen
// saved state after monitor topology changes (e.g. an external display
// was unplugged).
bool IsRectVisibleOnAnyMonitor(const WindowState& state);

#endif  // RUNNER_WINDOW_STATE_H_
