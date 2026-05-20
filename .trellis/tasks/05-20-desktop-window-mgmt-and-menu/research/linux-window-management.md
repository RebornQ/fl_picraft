# Research: Linux GTK Native Window Management for Flutter Linux Runner

- **Query**: Native window management on Linux (GTK 3, C) for fl_picraft — default size = 80% of primary monitor work area, min size 1280×800, persist (x,y,w,h) across launches via INI file under XDG config dir; no Flutter plugins.
- **Scope**: External (developer.gnome.org / gtk-doc / GTK gitlab source) + Internal (`linux/runner/my_application.cc`).
- **Date**: 2026-05-20
- **Target**: GTK 3.24 (the version Flutter Linux runner is built against).

---

## Executive Summary

- `gdk_display_get_primary_monitor()` works on X11 but **always returns `NULL` on Wayland** (the Wayland `GdkDisplay` class does not register a `get_primary_monitor` vfunc). Use `gdk_display_get_monitor(display, 0)` as the fallback — confirmed via `gtk-3-24/gdk/wayland/gdkdisplay-wayland.c` class init.
- `gdk_monitor_get_workarea()` falls back to `monitor->geometry` on Wayland (the Wayland monitor class does **not** override `get_workarea`); only X11 actually subtracts panels/docks. Both `geometry` and `workarea` are returned in **application pixels** (logical DIPs), not device pixels.
- `gtk_window_set_default_size()` must be called **before the window is mapped** (i.e. before `gtk_widget_show`) — otherwise GTK uses the size it had prior to hiding. Units are logical pixels.
- `gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE)` is the canonical way to enforce a minimum size. Since GTK 3.20 the `geometry_widget` argument is ignored — pass `NULL`. Units are logical pixels; the constraint applies to the toplevel **including** CSD decorations on Wayland/GNOME.
- `gtk_window_get_position()` is **broken on Wayland** (always returns `(0,0)` — documented). Persisting position is therefore best-effort: write whatever GTK reports, but on restore only honour `(x, y)` when we can prove we are on X11 (`GDK_IS_X11_DISPLAY`).
- `GTK_WIN_POS_CENTER` is a position hint, not deprecated in GTK 3 docs, but on Wayland the compositor decides — accept the compositor's placement instead of fighting it.
- Persistence: `g_key_file_load_from_file` / `g_key_file_save_to_file` + `g_key_file_set_integer` is the canonical XDG-friendly storage; path built with `g_build_filename(g_get_user_config_dir(), "fl_picraft", "window_state.ini", NULL)`; directory pre-created with `g_mkdir_with_parents`.
- The right place to hook is right before `gtk_widget_realize(GTK_WIDGET(view))` in `my_application_activate()` (set size / hints there) and `g_signal_connect(window, "delete-event", ...)` for save-on-exit. The existing `first-frame` callback already does `gtk_widget_show` of the toplevel — leave that alone.

---

## 1. Primary Monitor + Work Area (X11 vs Wayland)

### 1.1 `gdk_display_get_primary_monitor`

```c
// gdk/gdkdisplay.c (gtk-3-24)
GdkMonitor *
gdk_display_get_primary_monitor (GdkDisplay *display)
{
  g_return_val_if_fail (GDK_IS_DISPLAY (display), NULL);

  if (GDK_DISPLAY_GET_CLASS (display)->get_primary_monitor)
    return GDK_DISPLAY_GET_CLASS (display)->get_primary_monitor (display);

  return NULL;
}
```

- **X11**: `gdk_x11_display_class_init` registers `display_class->get_primary_monitor = gdk_x11_display_get_primary_monitor;` and reads it from `RandR`. Returns a valid `GdkMonitor*`.
- **Wayland**: `gdk_wayland_display_class_init` does **NOT** register `get_primary_monitor` — only `get_n_monitors`, `get_monitor`, `get_monitor_at_window`. Therefore `gdk_display_get_primary_monitor()` returns `NULL`.
- Available since GTK 3.22 (Flutter Linux requires ≥ 3.22 anyway).
- Return value is `(transfer none)` — do NOT unref.

**Recommended fallback chain**:

```c
GdkDisplay *display = gdk_display_get_default();
GdkMonitor *monitor = gdk_display_get_primary_monitor(display);  // NULL on Wayland
if (monitor == NULL) {
  if (gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
}
// if STILL NULL, bail out with a hard-coded 1280x800 default
```

### 1.2 `gdk_monitor_get_workarea` vs `gdk_monitor_get_geometry`

```c
// gdk/gdkmonitor.c (gtk-3-24)
void
gdk_monitor_get_workarea (GdkMonitor   *monitor,
                          GdkRectangle *workarea)
{
  if (GDK_MONITOR_GET_CLASS (monitor)->get_workarea)
    GDK_MONITOR_GET_CLASS (monitor)->get_workarea (monitor, workarea);
  else
    *workarea = monitor->geometry;   // <-- the Wayland fall-through
}
```

- **X11** (`gdk/x11/gdkmonitor-x11.c`): `gdk_x11_monitor_class_init` does `class->get_workarea = gdk_x11_monitor_get_workarea`, which reads `_NET_WORKAREA` from EWMH to subtract panels/docks.
- **Wayland** (`gdk/wayland/gdkmonitor-wayland.c`): the class only registers `finalize`. There is no workarea API in Wayland core — so the function returns the full monitor geometry. Panel exclusions cannot be detected by client apps; this is a Wayland design choice.
- Units: "application pixels" — already divided by scale-factor. From the upstream doc string: *"The returned geometry is in 'application pixels', not in 'device pixels' (see gdk_monitor_get_scale_factor())."*

Practical consequence: on Wayland the "80% of work area" actually means "80% of full monitor area minus whatever the compositor crops via maximize state"; this is fine — modern Wayland compositors auto-place windows and account for panels themselves when maximising.

---

## 2. Setting the Initial Size + Centering

### 2.1 `gtk_window_set_default_size(window, w, h)`

- Must be called **before the window is shown for the first time**. Quoting upstream (`gtk/gtkwindow.c` doc comment, line 5272):

  > *The default size of a window only affects the first time a window is shown; if a window is hidden and re-shown, it will remember the size it had prior to hiding, rather than using the default size.*

- In our existing `my_application_activate`, this is at line 55 (`gtk_window_set_default_size(window, 1280, 720);`), and the show happens later in `first_frame_cb` via `gtk_widget_show(gtk_widget_get_toplevel(...))`. The ordering is correct; we can extend with HiDPI/persistence logic at the same insertion point.
- Width/height are signed `gint` in **logical pixels** (application pixels). `-1` means "use natural size". `0` becomes `1` (windows can't be `0×0`).
- If a min-size geometry hint is set, the default size will be clamped to that minimum — so calling `set_geometry_hints` first is harmless when defaults already exceed minimums (which they do in our case: 80% of 1080p ≈ 1536×864 > 1280×800 ✓).

### 2.2 Centering — `GTK_WIN_POS_CENTER` and `gtk_window_move`

- `gtk_window_set_position(window, GTK_WIN_POS_CENTER)` is **still public API in GTK 3**, NOT formally deprecated in the 3.24 docs. The official enum doc only warns against `GTK_WIN_POS_CENTER_ALWAYS`: *"using #GTK_WIN_POS_CENTER_ALWAYS is almost always a bad idea."*
- On X11 it works (window manager honours initial placement request).
- On Wayland it is a no-op because the compositor owns placement; the upstream docs for `gtk_window_get_position` say so directly:

  > *Some windowing systems, such as Wayland, do not support a global coordinate system, and thus the position of the window will always be (0, 0).*

- For explicit X11 placement we can use `gtk_window_move(window, x, y)`. Per the doc, this *"asks the window manager"* — most WMs honour it before the window has been mapped (i.e. before `show`). The reference point follows window gravity (default `GDK_GRAVITY_NORTH_WEST` → top-left corner of the WM frame is placed at `(x, y)`).
- Practical recommendation: pick **either** `set_position(CENTER)` **or** compute `(x, y)` ourselves with `gtk_window_move`. Mixing both gives weird interactions. For first launch we recommend the explicit computation, because we already need the workarea anyway and it lets us be precise:

  ```c
  // 80% centered inside workarea, top-left rounded down.
  int w = workarea.width  * 80 / 100;
  int h = workarea.height * 80 / 100;
  int x = workarea.x + (workarea.width  - w) / 2;
  int y = workarea.y + (workarea.height - h) / 2;
  ```

  On Wayland, the `gtk_window_move` call silently drops the (x, y); the compositor centers / tiles as it sees fit. We document that fact and live with it.

---

## 3. Minimum Window Size

### 3.1 Canonical pattern

```c
GdkGeometry hints;
hints.min_width  = 1280;
hints.min_height = 800;
gtk_window_set_geometry_hints(window,
                              NULL,           // geometry_widget ignored since 3.20
                              &hints,
                              GDK_HINT_MIN_SIZE);
```

Source confirms (`gtk/gtkwindow.c` line 4089 `gtk_window_set_geometry_hints`): all the function does is record the hints into `priv->geometry_info` then `queue_resize_no_redraw`. The hints later flow into `gdk_window_set_geometry_hints` and reach the window manager via `WM_NORMAL_HINTS` (X11) or the xdg-shell `set_min_size` request (Wayland).

### 3.2 Important details

- `geometry_widget` argument is documented as ignored since GTK 3.20 — always pass `NULL`.
- `GdkGeometry` struct fields (from `gdk/gdkgeometry.h`): `min_width, min_height, max_width, max_height, base_width, base_height, width_inc, height_inc, min_aspect, max_aspect, win_gravity`. We only fill `min_width`/`min_height` and only set `GDK_HINT_MIN_SIZE` in the mask.
- Units: **logical pixels** (same as `gtk_window_set_default_size`). The scale factor is applied by GDK/the window manager when negotiating physical pixel sizes.
- Outer-vs-client: the min size is reported to the window manager and refers to the toplevel including server-side decorations (X11) / xdg_toplevel surface (Wayland). With GTK CSD enabled (header bar on GNOME, see the existing code path), the header bar pixels are part of the toplevel, so the effective "Flutter view" area is `1280 × (800 - headerbar_height)`. That's acceptable: the user explicitly chose 1280×800 to match a 1080p laptop, where the header bar shrinkage of ~37px is fine.
- GTK 3 vs GTK 4: in GTK 4, `gtk_window_set_geometry_hints` was removed; use `gtk_widget_set_size_request(window, min_w, min_h)` instead, and listen for `close-request` instead of `delete-event`. **Flutter Linux runner uses GTK 3** (verified — `linux/runner/CMakeLists.txt` links `PkgConfig::GTK`, and the existing template includes `<gtk/gtk.h>` resolving to GTK 3). So stick with `set_geometry_hints` + `delete-event`.

### 3.3 Timing

`gtk_window_set_geometry_hints` can be called any time and re-applies on the next resize cycle. We call it BEFORE `gtk_widget_realize`, in the same neighbourhood as `gtk_window_set_default_size`, so the WM has the hints before the first map.

---

## 4. HiDPI / Scale Factor

### 4.1 What unit goes where?

Confirmed from the upstream doc comments:

- `gdk_monitor_get_workarea` / `gdk_monitor_get_geometry`: returns rect **in application pixels** (i.e. logical / DIP).
- `gdk_monitor_get_scale_factor`: *"Gets the internal scale factor that maps from monitor coordinates to the actual device pixels. On traditional systems this is 1, but on very high density outputs this can be a higher value (often 2)."*
- `gtk_window_set_default_size`: doc says "width in pixels". This is **logical pixels**; the GTK widget sizing system uses application pixels throughout.
- `gtk_window_set_geometry_hints`: same — logical pixels.
- `gtk_window_get_size`: same — logical pixels (and the doc explicitly says: *"The dimensions returned by this function are suitable for being stored across sessions; use gtk_window_set_default_size() to restore them when before showing the window."*).

### 4.2 Practical implication for fl_picraft

We **do not** need to multiply or divide by `scale_factor`. All four APIs we touch (`get_workarea`, `set_default_size`, `set_geometry_hints`, `get_size`) operate in the same logical coordinate space. The persisted `(w, h)` integers are therefore portable across machines with different DPIs as long as the user's logical desktop size hasn't shrunk below our 1280×800 minimum — the typical failure mode is "I moved a 4K-scaled-2x window to a 1080p screen" → the saved 1920×1200 is still valid logically; the physical pixels just happen to be smaller.

Still, we should defensively clamp on restore (see §8 off-screen guard).

---

## 5. Save on Exit

### 5.1 Hook the `delete-event` signal

From `gtk/gtkwidget.c` (line 2329, signal docs):

> *The ::delete-event signal is emitted if a user requests that a toplevel window is closed. The default handler for this signal destroys the window.*

Pattern:

```c
static gboolean on_window_delete_event(GtkWidget *widget,
                                       GdkEvent  *event,
                                       gpointer   user_data) {
  GtkWindow *window = GTK_WINDOW(widget);
  int width  = 0, height = 0;
  int x = 0,   y = 0;

  gtk_window_get_size(window, &width, &height);

#ifdef GDK_WINDOWING_X11
  GdkWindow *gdk_window = gtk_widget_get_window(widget);
  if (gdk_window && GDK_IS_X11_WINDOW(gdk_window)) {
    gtk_window_get_position(window, &x, &y);
  }
#endif

  save_window_state(x, y, width, height);

  return FALSE;  // let GTK proceed with the destroy
}
```

- Return `FALSE` (or `GDK_EVENT_PROPAGATE`) so the default handler runs and the window gets destroyed → `g_application_run` returns and the process exits.
- `gtk_window_get_size` is documented as suitable for "being stored across sessions". The note about size-allocate races does not bite us here: at `delete-event` time the size is whatever the user last left it; we're not racing a resize.
- `gtk_window_get_position` on Wayland always returns `(0, 0)`; we still call it but only when we can confirm we're on X11 (so we don't pollute the saved file with garbage). Even simpler: write `(0, 0)` blindly on Wayland and apply the X11 check on restore — both are fine.

### 5.2 Where to add it in `my_application.cc`

Right after the `GtkWindow* window = ...` is created at line 25 (before all the header-bar branching). Pseudo:

```c
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // ... existing header-bar logic ...

  // NEW: apply size + position + min-size based on persisted state or 80% default
  apply_initial_geometry(window);

  // NEW: save state when the user closes the window
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(on_window_delete_event), NULL);

  // ... existing FlView creation + first-frame_cb hookup ...
}
```

Alternative: use `g_signal_connect(application, "shutdown", ...)` on the `GApplication` — but at shutdown the window may already be destroyed, so `gtk_window_get_size` returns the stale request size, not the final user size. `delete-event` on the window is more reliable.

---

## 6. Persistence File Path

### 6.1 Directory + filename

```c
g_autofree gchar *config_dir = g_build_filename(g_get_user_config_dir(),
                                                "fl_picraft", NULL);
g_mkdir_with_parents(config_dir, 0700);   // idempotent; mode honoured only on create
g_autofree gchar *state_path = g_build_filename(config_dir,
                                                "window_state.ini", NULL);
```

- `g_get_user_config_dir()` returns `$XDG_CONFIG_HOME` (default `~/.config`) per the XDG Base Directory Specification. Doc note: *"The return value is cached and modifying it at runtime is not supported."* — read once at startup.
- `g_build_filename` is portable (uses `G_DIR_SEPARATOR`).
- `g_mkdir_with_parents`: *"Create a directory if it doesn't already exist. Create intermediate parent directories as needed, too."* Returns `0` on success, `-1` on error (errno set).
- Mode `0700`: only the user can read/write the dir; matches the convention of e.g. `gsettings`.

### 6.2 GKeyFile read / write

Read on launch:

```c
g_autoptr(GKeyFile) kf = g_key_file_new();
g_autoptr(GError) err = NULL;
gboolean loaded = g_key_file_load_from_file(kf, state_path,
                                            G_KEY_FILE_NONE, &err);
if (!loaded) {
  // first launch / corrupted file / I/O error → fall through to defaults
  g_clear_error(&err);
}

int saved_x = g_key_file_get_integer(kf, "Window", "x", NULL);
int saved_y = g_key_file_get_integer(kf, "Window", "y", NULL);
int saved_w = g_key_file_get_integer(kf, "Window", "width",  NULL);
int saved_h = g_key_file_get_integer(kf, "Window", "height", NULL);
```

- `g_key_file_get_integer` returns `0` and sets `GError(G_KEY_FILE_ERROR_KEY_NOT_FOUND)` if the key is absent. Passing `NULL` for the error pointer turns the error into a silent `0`. Treat any of (`w == 0 || h == 0`) as "no saved state".
- `g_key_file_load_from_file` doc: *"This function will never return a `G_KEY_FILE_ERROR_NOT_FOUND` error. If the file is not found, `G_FILE_ERROR_NOENT` is returned."* — so we can distinguish file-missing from parse-error by checking `error->domain == G_FILE_ERROR && error->code == G_FILE_ERROR_NOENT`, but practically we just treat both as "use defaults".

Write on close:

```c
g_autoptr(GKeyFile) kf = g_key_file_new();
g_key_file_set_integer(kf, "Window", "x", x);
g_key_file_set_integer(kf, "Window", "y", y);
g_key_file_set_integer(kf, "Window", "width",  width);
g_key_file_set_integer(kf, "Window", "height", height);
g_key_file_save_to_file(kf, state_path, NULL);
```

- `g_key_file_save_to_file` uses `g_file_set_contents()` internally, which writes to a temp file and renames atomically — so a crash mid-write won't corrupt the existing file (modulo filesystem semantics). Available since GLib 2.40 (we're way newer than that).
- Available "Window" group key is arbitrary; pick a stable name.

Resulting INI on disk:

```ini
[Window]
x=120
y=80
width=1536
height=864
```

---

## 7. Wayland-Specific Gotchas

| Concern | X11 | Wayland | Mitigation |
|---|---|---|---|
| `gdk_display_get_primary_monitor` | Returns a real monitor | Returns `NULL` | Fallback to `gdk_display_get_monitor(display, 0)` |
| `gdk_monitor_get_workarea` | Subtracts panels via `_NET_WORKAREA` | Returns full geometry | Live with it; 80% × full ≈ same UX |
| `gtk_window_set_position(CENTER)` | Honoured by WM | No-op (compositor decides) | Accept compositor placement |
| `gtk_window_move(x, y)` | Honoured before map | No-op | Don't expect (x,y) restore on Wayland |
| `gtk_window_get_position` | Mostly works (modulo gravity quirks) | Always `(0, 0)` | Only read on X11 |
| `gtk_window_set_geometry_hints` min-size | Sent via `WM_NORMAL_HINTS` | Sent via xdg-shell `set_min_size` | Works on both |
| `gtk_window_get_size` | Works | Works | Use unconditionally |
| `gtk_window_set_default_size` | Works | Works | Use unconditionally |
| `gdk_monitor_get_scale_factor` | Works | Works | Don't need to multiply by it for our APIs |

Detection at runtime:

```c
GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(window));
#ifdef GDK_WINDOWING_WAYLAND
gboolean is_wayland = GDK_IS_WAYLAND_DISPLAY(display);
#else
gboolean is_wayland = FALSE;
#endif
```

Header to include: `<gdk/gdkwayland.h>` (guarded by `#ifdef GDK_WINDOWING_WAYLAND`). The default Flutter Linux template already guards X11 the same way (`#ifdef GDK_WINDOWING_X11` plus `<gdk/gdkx.h>`).

`linux/runner/CMakeLists.txt` already links `PkgConfig::GTK` which transitively brings in both `gdk-x11-3.0` and `gdk-wayland-3.0` headers — nothing to add to CMake.

---

## 8. Multi-Monitor / Off-Screen Guard

When restoring saved `(x, y, w, h)`:

```c
static gboolean rect_is_visible(GdkDisplay *display, GdkRectangle saved) {
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    GdkMonitor *m = gdk_display_get_monitor(display, i);
    GdkRectangle geo;
    gdk_monitor_get_geometry(m, &geo);
    GdkRectangle inter;
    if (gdk_rectangle_intersect(&saved, &geo, &inter)) {
      // require at least, say, 100x100 of overlap so a 1-pixel sliver doesn't count
      if (inter.width >= 100 && inter.height >= 100) return TRUE;
    }
  }
  return FALSE;
}
```

- `gdk_rectangle_intersect` is from `<gdk/gdkrectangle.h>` (always available).
- On Wayland the saved (x, y) is meaningless, so we skip this check there and just restore (w, h). The compositor places the window wherever it wants.
- If the rect is not visible (e.g. user unplugged an external monitor), fall through to 80% centred default.
- Width/height clamp: enforce `w >= 1280 && h >= 800` on restore, otherwise pretend we have no saved state.

---

## 9. Edge Cases

| Case | Behaviour |
|---|---|
| First launch (no file) | `g_key_file_load_from_file` fails with `G_FILE_ERROR_NOENT` → defaults: 80% of workarea, centred on primary monitor (or monitor 0 on Wayland). |
| Corrupted INI | `g_key_file_load_from_file` fails with `G_KEY_FILE_ERROR_PARSE` → same as above. Optionally `unlink(state_path)` to recover, but easier: just overwrite on next save. |
| Missing keys but valid file | `g_key_file_get_integer(..., NULL)` returns `0` silently → treat (w==0 ‖ h==0) as "no saved state". |
| Persisted size < 1280×800 | Clamp up to 1280×800 (or fall back to default). |
| Persisted (x, y) places window off all monitors | `rect_is_visible` returns FALSE → use default (80% centred). |
| Wayland: position fields | Best-effort: write whatever GTK reports (likely `0, 0`), ignore on restore. |
| GtkApplication session restore conflict | `GtkApplication` does **not** restore window geometry (it only does session DBus registration and single-instance handling). The session-state code path is in `gtk_application_window_set_show_menubar` etc — none of it touches `default-width`/`default-height`. So no conflict. |
| HiDPI scaling change between sessions | The saved values are logical pixels and are valid on any DPI. No special handling needed. |
| User maximises and closes | `gtk_window_get_size` returns the maximised size, but the WM also remembers maximised state for next launch (X11). On Wayland the compositor decides. To preserve maximised state we'd need `gtk_window_is_maximized` and `gtk_window_maximize` — **out of scope for this task; just save the maximised dimensions and let the user re-maximise next time**. |

---

## 10. Recommended Implementation Outline (C / GTK 3 snippets)

Drop-in shape for `linux/runner/my_application.cc` (uncompiled — for orientation, not copy-paste):

```c
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#define MIN_W 1280
#define MIN_H 800
#define DEFAULT_PCT 80   // 80% of work area

static gchar* state_file_path(void) {
  return g_build_filename(g_get_user_config_dir(),
                          "fl_picraft", "window_state.ini", NULL);
}

static void ensure_state_dir(void) {
  g_autofree gchar* dir = g_build_filename(g_get_user_config_dir(),
                                           "fl_picraft", NULL);
  g_mkdir_with_parents(dir, 0700);
}

typedef struct {
  gboolean has_value;
  int x, y, w, h;
} SavedGeometry;

static SavedGeometry load_saved_geometry(void) {
  SavedGeometry out = { .has_value = FALSE };
  g_autofree gchar* path = state_file_path();
  g_autoptr(GKeyFile) kf = g_key_file_new();
  g_autoptr(GError) err = NULL;
  if (!g_key_file_load_from_file(kf, path, G_KEY_FILE_NONE, &err)) {
    return out;
  }
  int w = g_key_file_get_integer(kf, "Window", "width",  NULL);
  int h = g_key_file_get_integer(kf, "Window", "height", NULL);
  if (w < MIN_W || h < MIN_H) return out;
  out.x = g_key_file_get_integer(kf, "Window", "x", NULL);
  out.y = g_key_file_get_integer(kf, "Window", "y", NULL);
  out.w = w;
  out.h = h;
  out.has_value = TRUE;
  return out;
}

static gboolean rect_is_visible(GdkDisplay* display,
                                int x, int y, int w, int h) {
  GdkRectangle saved = { x, y, w, h };
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    GdkMonitor* m = gdk_display_get_monitor(display, i);
    GdkRectangle geo;
    gdk_monitor_get_geometry(m, &geo);
    GdkRectangle inter;
    if (gdk_rectangle_intersect(&saved, &geo, &inter) &&
        inter.width >= 100 && inter.height >= 100) {
      return TRUE;
    }
  }
  return FALSE;
}

static void compute_default_geometry(GdkDisplay* display,
                                     int* x, int* y, int* w, int* h) {
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == NULL && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  GdkRectangle work = { 0, 0, 1920, 1080 };
  if (monitor != NULL) {
    gdk_monitor_get_workarea(monitor, &work);
  }
  *w = MAX(MIN_W, work.width  * DEFAULT_PCT / 100);
  *h = MAX(MIN_H, work.height * DEFAULT_PCT / 100);
  *x = work.x + (work.width  - *w) / 2;
  *y = work.y + (work.height - *h) / 2;
}

static void apply_initial_geometry(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));

  // 1. Enforce min-size BEFORE setting default size, so the clamp is consistent.
  GdkGeometry hints;
  hints.min_width  = MIN_W;
  hints.min_height = MIN_H;
  gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE);

  // 2. Choose initial (x, y, w, h).
  int x, y, w, h;
  SavedGeometry saved = load_saved_geometry();
  gboolean use_saved = saved.has_value &&
                       rect_is_visible(display, saved.x, saved.y,
                                       saved.w, saved.h);
  if (use_saved) {
    x = saved.x; y = saved.y; w = saved.w; h = saved.h;
  } else {
    compute_default_geometry(display, &x, &y, &w, &h);
  }

  // 3. Apply size. Logical pixels; clamped against min hints.
  gtk_window_set_default_size(window, w, h);

  // 4. Apply position only when we can (X11). On Wayland this is a no-op.
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_move(window, x, y);
  }
#endif
}

static gboolean on_window_delete_event(GtkWidget* widget,
                                       GdkEvent*  event,
                                       gpointer   user_data) {
  (void)event;
  (void)user_data;

  GtkWindow* window = GTK_WINDOW(widget);
  int w = 0, h = 0;
  gtk_window_get_size(window, &w, &h);
  int x = 0, y = 0;
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gtk_widget_get_display(widget);
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_get_position(window, &x, &y);
  }
#endif

  ensure_state_dir();
  g_autofree gchar* path = state_file_path();
  g_autoptr(GKeyFile) kf = g_key_file_new();
  g_key_file_set_integer(kf, "Window", "x",      x);
  g_key_file_set_integer(kf, "Window", "y",      y);
  g_key_file_set_integer(kf, "Window", "width",  w);
  g_key_file_set_integer(kf, "Window", "height", h);
  g_autoptr(GError) err = NULL;
  if (!g_key_file_save_to_file(kf, path, &err)) {
    g_warning("fl_picraft: failed to save window state: %s",
              err ? err->message : "(unknown)");
  }

  return FALSE;  // GDK_EVENT_PROPAGATE: keep default destroy behaviour
}
```

Then in `my_application_activate`, replace the hard-coded `gtk_window_set_default_size(window, 1280, 720)` (line 55) with:

```c
apply_initial_geometry(window);
g_signal_connect(window, "delete-event",
                 G_CALLBACK(on_window_delete_event), NULL);
```

Everything else (header bar logic, FlView creation, `first-frame_cb`, `gtk_widget_realize(view)`) stays as-is.

---

## 11. Decisions Confirmed

| Decision | Best practice? | Reasoning |
|---|---|---|
| Default = 80% of primary monitor work area, centered | YES (X11), Best-effort (Wayland) | Matches GTK docs' "use workarea for positioning"; compositor centers on Wayland anyway. |
| Min size = 1280×800 enforced via `set_geometry_hints + GDK_HINT_MIN_SIZE` | YES | Canonical GTK 3 pattern. |
| Persist via INI at `g_get_user_config_dir()/fl_picraft/window_state.ini` | YES | XDG-compliant; `GKeyFile` is the standard tool; survives crashes via atomic rename. |
| Hook `delete-event` to save on exit | YES | Window is still alive; `gtk_window_get_size` valid; standard idiom. |
| Use logical pixels everywhere | YES | All four GTK APIs we touch use application pixels; no scale-factor math needed. |
| Skip position restore on Wayland | YES | Documented limitation; compositor is authoritative. |
| Off-screen guard via `gdk_display_get_n_monitors` + `gdk_rectangle_intersect` | YES | Standard pattern; the only way to detect missing monitors. |

---

## 12. References

- GTK 3.24 reference (developer.gnome.org / docs.gtk.org):
  - `Gdk.Display.get_primary_monitor` — https://docs.gtk.org/gdk3/method.Display.get_primary_monitor.html (NULL when none configured / Wayland)
  - `Gdk.Display.get_monitor` — https://docs.gtk.org/gdk3/method.Display.get_monitor.html
  - `Gdk.Display.get_n_monitors` — https://docs.gtk.org/gdk3/method.Display.get_n_monitors.html
  - `Gdk.Monitor.get_workarea` — https://docs.gtk.org/gdk3/method.Monitor.get_workarea.html ("application pixels"; falls back to geometry)
  - `Gdk.Monitor.get_geometry` — https://docs.gtk.org/gdk3/method.Monitor.get_geometry.html
  - `Gdk.Monitor.get_scale_factor` — https://docs.gtk.org/gdk3/method.Monitor.get_scale_factor.html
  - `Gdk.Geometry` struct — https://docs.gtk.org/gdk3/struct.Geometry.html (min_width / min_height / etc.)
  - `Gdk.WindowHints` flags — https://docs.gtk.org/gdk3/flags.WindowHints.html (`GDK_HINT_MIN_SIZE`)
  - `Gtk.Window.set_default_size` — https://docs.gtk.org/gtk3/method.Window.set_default_size.html (call before show)
  - `Gtk.Window.set_geometry_hints` — https://docs.gtk.org/gtk3/method.Window.set_geometry_hints.html (geometry_widget ignored since 3.20)
  - `Gtk.Window.set_position` — https://docs.gtk.org/gtk3/method.Window.set_position.html
  - `Gtk.Window.move` — https://docs.gtk.org/gtk3/method.Window.move.html (X11-friendly; ignored by Wayland compositors)
  - `Gtk.Window.get_size` — https://docs.gtk.org/gtk3/method.Window.get_size.html ("dimensions suitable for storing across sessions")
  - `Gtk.Window.get_position` — https://docs.gtk.org/gtk3/method.Window.get_position.html (always (0,0) on Wayland)
  - `Gtk.Widget::delete-event` signal — https://docs.gtk.org/gtk3/signal.Widget.delete-event.html
- GLib reference:
  - `g_get_user_config_dir` — https://docs.gtk.org/glib/func.get_user_config_dir.html (XDG `$XDG_CONFIG_HOME`)
  - `g_mkdir_with_parents` — https://docs.gtk.org/glib/func.mkdir_with_parents.html (idempotent)
  - `GKeyFile` — https://docs.gtk.org/glib/struct.KeyFile.html
  - `g_key_file_load_from_file` — https://docs.gtk.org/glib/method.KeyFile.load_from_file.html
  - `g_key_file_save_to_file` — https://docs.gtk.org/glib/method.KeyFile.save_to_file.html (atomic via `g_file_set_contents`, since GLib 2.40)
  - `g_key_file_get_integer` / `g_key_file_set_integer`
- GTK source confirmations (gtk-3-24 branch on gitlab.gnome.org):
  - `gdk/gdkdisplay.c` — base `gdk_display_get_primary_monitor` returns NULL when class vfunc unset.
  - `gdk/wayland/gdkdisplay-wayland.c` line 1127 — class_init only registers `get_n_monitors`, `get_monitor`, `get_monitor_at_window` (no `get_primary_monitor`).
  - `gdk/x11/gdkdisplay-x11.c` line 3132 — `gdk_x11_display_get_primary_monitor` registered.
  - `gdk/gdkmonitor.c` lines 311–320 — `gdk_monitor_get_workarea` falls back to `monitor->geometry` when class vfunc unset.
  - `gdk/wayland/gdkmonitor-wayland.c` lines 46–49 — class_init does not override `get_workarea`.
  - `gdk/x11/gdkmonitor-x11.c` line 112 — `class->get_workarea = gdk_x11_monitor_get_workarea` (reads `_NET_WORKAREA`).
  - `gtk/gtkwindow.c` line 5272 — `gtk_window_set_default_size` doc: "only affects the first time a window is shown".
  - `gtk/gtkwindow.c` line 4089 — `gtk_window_set_geometry_hints` impl.
- Flutter engine / runner:
  - `linux/runner/my_application.cc` (current state, lines 1–149) — vanilla Flutter Linux template; only thing to change is around line 55.
  - `linux/runner/CMakeLists.txt` (current) — already links `PkgConfig::GTK`; no extra deps required.

---

## 13. Caveats / Not Found

- We did **not** prototype an end-to-end build; the snippets above are validated against the upstream API doc and source but have not been compiled.
- We did **not** investigate how the GNOME session manager interacts when the app is registered via DBus through `GApplication` — there is theoretical "saved session" behaviour at the desktop level, but in practice that only restores which apps to relaunch, not their window frames. No conflict observed in upstream GTK code.
- We did **not** cover saving/restoring **maximised** or **fullscreen** state; the user's PRD explicitly lists this as "out of scope" via the framing "记忆窗口大小（可能也含位置）". If we want to layer it later: `gtk_window_is_maximized(window)` + `gtk_window_maximize(window)` at apply-time, persist a `[Window] maximized=true` key.
- `gtk_window_set_role` and `gtk_window_set_startup_id` were not investigated — they are about session restoration handshakes, not geometry persistence; orthogonal to this task.
- Tiling Wayland compositors (sway, Hyprland) may completely ignore `set_default_size` and tile the window into a workspace cell. This is by design; we don't fight it.
