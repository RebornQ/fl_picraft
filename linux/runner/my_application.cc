#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// =====================================================================
// Window state persistence
//
// Default window size = 80% of primary monitor work area, centered.
// Minimum size        = 1280x800 (enforced via GdkGeometry min hints).
// Persisted to        = $XDG_CONFIG_HOME/fl_picraft/window_state.ini (GKeyFile).
// Save trigger        = "delete-event" signal on the toplevel window.
//
// Wayland gotchas (see ADR-lite §D-G in
// .trellis/tasks/05-20-desktop-window-mgmt-and-menu/prd.md):
//   * gdk_display_get_primary_monitor returns NULL -> fallback monitor 0.
//   * gdk_monitor_get_workarea returns geometry (no panel exclusion).
//   * gtk_window_move is a silent no-op (compositor owns placement) -> skip.
//   * gtk_window_get_position always returns (0, 0) -> skip read.
// All four GTK APIs used here (set_default_size, set_geometry_hints,
// get_workarea, get_size) operate in logical (application) pixels, so no
// scale-factor math is required.
// =====================================================================

static constexpr int kMinWidth = 1280;
static constexpr int kMinHeight = 800;
static constexpr int kDefaultPercent = 80;
// Saved rect must overlap at least this much (in logical pixels) with some
// monitor to be considered visible. Mirrors the Win32-side threshold for
// cross-platform consistency.
static constexpr int kVisibilityThreshold = 100;

typedef struct {
  gboolean has_value;
  int x;
  int y;
  int w;
  int h;
} SavedGeometry;

static gchar* state_file_path() {
  return g_build_filename(g_get_user_config_dir(), "fl_picraft",
                          "window_state.ini", nullptr);
}

static void ensure_state_dir() {
  g_autofree gchar* dir =
      g_build_filename(g_get_user_config_dir(), "fl_picraft", nullptr);
  // Idempotent; mode 0700 only applies on creation. Matches XDG convention.
  g_mkdir_with_parents(dir, 0700);
}

static SavedGeometry load_saved_geometry() {
  SavedGeometry out = {FALSE, 0, 0, 0, 0};
  g_autofree gchar* path = state_file_path();
  g_autoptr(GKeyFile) kf = g_key_file_new();
  // Missing file / parse error -> fall through to defaults. We pass nullptr
  // for the GError because we treat any failure the same way.
  if (!g_key_file_load_from_file(kf, path, G_KEY_FILE_NONE, nullptr)) {
    return out;
  }
  // g_key_file_get_integer returns 0 silently when the key is absent (when
  // the GError pointer is NULL), so the floor check below also doubles as a
  // missing-key guard.
  int w = g_key_file_get_integer(kf, "Window", "width", nullptr);
  int h = g_key_file_get_integer(kf, "Window", "height", nullptr);
  if (w < kMinWidth || h < kMinHeight) {
    return out;
  }
  out.x = g_key_file_get_integer(kf, "Window", "x", nullptr);
  out.y = g_key_file_get_integer(kf, "Window", "y", nullptr);
  out.w = w;
  out.h = h;
  out.has_value = TRUE;
  return out;
}

static gboolean rect_is_visible(GdkDisplay* display, int x, int y, int w,
                                int h) {
  GdkRectangle saved = {x, y, w, h};
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    GdkRectangle geo;
    // Use geometry (not workarea) so the visibility check is identical on
    // X11 and Wayland — workarea is undefined / equal to geometry on Wayland.
    gdk_monitor_get_geometry(monitor, &geo);
    GdkRectangle inter;
    if (gdk_rectangle_intersect(&saved, &geo, &inter) &&
        inter.width >= kVisibilityThreshold &&
        inter.height >= kVisibilityThreshold) {
      return TRUE;
    }
  }
  return FALSE;
}

static void compute_default_geometry(GdkDisplay* display, int* x, int* y,
                                     int* w, int* h) {
  // Wayland has no primary-monitor concept; gdk_display_get_primary_monitor
  // returns NULL there. Fall back to monitor 0.
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  GdkRectangle work = {0, 0, 1920, 1080};  // Last-resort default.
  if (monitor != nullptr) {
    // On X11 this subtracts panels via _NET_WORKAREA; on Wayland it returns
    // the full monitor geometry (no panel exclusion is available there).
    gdk_monitor_get_workarea(monitor, &work);
  }
  // Defensive clamp: 80% × workarea must not drop below the 1280×800 floor.
  // Same guarantee as the Win32 and macOS runners — if the work area is
  // smaller than 1600×1000, the 80% calculation would otherwise undercut the
  // min hint and the window would refuse to shrink to the requested default.
  *w = MAX(kMinWidth, work.width * kDefaultPercent / 100);
  *h = MAX(kMinHeight, work.height * kDefaultPercent / 100);
  *x = work.x + (work.width - *w) / 2;
  *y = work.y + (work.height - *h) / 2;
}

static void apply_initial_geometry(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));

  // 1. Enforce min-size first so subsequent setters respect it. The
  //    geometry_widget argument is ignored since GTK 3.20 — always pass NULL.
  GdkGeometry hints;
  hints.min_width = kMinWidth;
  hints.min_height = kMinHeight;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);

  // 2. Pick saved-and-still-visible geometry, else compute 80% × workarea.
  int x = 0, y = 0, w = 0, h = 0;
  SavedGeometry saved = load_saved_geometry();
  if (saved.has_value &&
      rect_is_visible(display, saved.x, saved.y, saved.w, saved.h)) {
    x = saved.x;
    y = saved.y;
    w = saved.w;
    h = saved.h;
  } else {
    compute_default_geometry(display, &x, &y, &w, &h);
  }

  // 3. Apply size (logical pixels). MUST be called before the window is
  //    first shown — gtk_window_set_default_size only affects the very
  //    first show. The default size is clamped against the min hints set
  //    above, but our clamp in compute_default_geometry guarantees w/h are
  //    already >= 1280x800.
  gtk_window_set_default_size(window, w, h);

  // 4. Apply position only on X11. On Wayland gtk_window_move is silently
  //    a no-op (the compositor owns placement) so don't bother calling it.
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_move(window, x, y);
  }
#endif
}

static gboolean on_window_delete_event(GtkWidget* widget, GdkEvent* event,
                                       gpointer user_data) {
  (void)event;
  (void)user_data;

  GtkWindow* window = GTK_WINDOW(widget);
  int w = 0;
  int h = 0;
  // gtk_window_get_size returns logical pixels — upstream docs explicitly
  // call this out as "suitable for being stored across sessions".
  gtk_window_get_size(window, &w, &h);

  int x = 0;
  int y = 0;
#ifdef GDK_WINDOWING_X11
  // Position is only meaningful on X11. On Wayland gtk_window_get_position
  // always returns (0, 0) by design — leave the saved coordinates at 0 and
  // rely on the compositor to place the window on restore.
  GdkDisplay* display = gtk_widget_get_display(widget);
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_get_position(window, &x, &y);
  }
#endif

  ensure_state_dir();
  g_autofree gchar* path = state_file_path();
  g_autoptr(GKeyFile) kf = g_key_file_new();
  g_key_file_set_integer(kf, "Window", "x", x);
  g_key_file_set_integer(kf, "Window", "y", y);
  g_key_file_set_integer(kf, "Window", "width", w);
  g_key_file_set_integer(kf, "Window", "height", h);
  g_autoptr(GError) error = nullptr;
  // g_key_file_save_to_file is atomic via g_file_set_contents (write to
  // temp + rename) since GLib 2.40, so a crash mid-write cannot corrupt the
  // existing file.
  if (!g_key_file_save_to_file(kf, path, &error)) {
    g_warning("fl_picraft: failed to save window state to %s: %s", path,
              error ? error->message : "(unknown)");
  }

  // GDK_EVENT_PROPAGATE (FALSE): let the default handler destroy the window
  // so the application can shut down normally.
  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Fl PiCraft");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Fl PiCraft");
  }

  // Apply the persisted (or default 80% × workarea, centered) window
  // geometry, enforce the 1280×800 min size, and arrange to persist the
  // current geometry on close. See the "Window state persistence" block
  // above for details.
  apply_initial_geometry(window);
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(on_window_delete_event), nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
