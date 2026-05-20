# Subtask: Linux 原生窗口策略（GTK 3 80% 默认 / set_geometry_hints / GKeyFile 持久化）

**Parent**: [`.trellis/tasks/05-20-desktop-window-mgmt-and-menu`](../05-20-desktop-window-mgmt-and-menu/prd.md)

## Scope

在 `linux/runner/my_application.cc`（GTK 3 + C）中实现：

- 首次启动窗口 = 主屏 workarea 80%（X11 居中 / Wayland 由 compositor 决定）。
- 最小尺寸 = 1280×800（`gtk_window_set_geometry_hints` + `GDK_HINT_MIN_SIZE`）。
- 持久化 = `g_get_user_config_dir()/fl_picraft/window_state.ini`（GKeyFile）。
- 退出点 = `delete-event` 信号回调，写盘后 `return FALSE` 让 GTK 继续 destroy。

## Detail（节选自父 PRD §D 与 ADR-lite §D-F / §D-G）

### 改动文件

| File | Action |
|---|---|
| `linux/runner/my_application.cc` | 顶部加 `#ifdef GDK_WINDOWING_WAYLAND #include <gdk/gdkwayland.h>`；新增 helpers（`state_file_path` / `ensure_state_dir` / `load_saved_geometry` / `rect_is_visible` / `compute_default_geometry` / `apply_initial_geometry` / `on_window_delete_event`）；替换第 55 行 `gtk_window_set_default_size(window, 1280, 720)` 为 `apply_initial_geometry(window)` + `g_signal_connect(window, "delete-event", ...)` |
| `linux/runner/CMakeLists.txt` | **无需改动**（`PkgConfig::GTK` 已经传递性带入 `gdk-x11-3.0` 和 `gdk-wayland-3.0`） |

### Wayland 降级矩阵（已在父 PRD ADR-lite §D-G 锁定）

| 行为 | X11 | Wayland |
|---|---|---|
| `gdk_display_get_primary_monitor` | 真实主屏 | NULL → fallback `gdk_display_get_monitor(display, 0)` |
| `gdk_monitor_get_workarea` | 减去 panel | 等价 `geometry`（可接受） |
| `gtk_window_move(x, y)` | WM 接受 | 静默 no-op |
| `gtk_window_get_position` | 大致正确 | 恒返回 `(0, 0)` —— 必须 `GDK_IS_X11_DISPLAY` 守卫 |
| `gtk_window_set_geometry_hints` 最小尺寸 | `WM_NORMAL_HINTS` | xdg-shell `set_min_size` —— 都生效 |
| `gtk_window_set_default_size` | 生效 | 生效 |
| `gtk_window_get_size` | 生效 | 生效 |

### `apply_initial_geometry` 主体（伪代码节选）

```c
static void apply_initial_geometry(GtkWindow* window) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));

  GdkGeometry hints = { .min_width = 1280, .min_height = 800 };
  gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE);

  int x, y, w, h;
  SavedGeometry saved = load_saved_geometry();
  if (saved.has_value && rect_is_visible(display, saved.x, saved.y, saved.w, saved.h)) {
    x = saved.x; y = saved.y; w = saved.w; h = saved.h;
  } else {
    compute_default_geometry(display, &x, &y, &w, &h);  // 80% × workarea, 居中
  }
  gtk_window_set_default_size(window, w, h);

#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) gtk_window_move(window, x, y);
#endif
}
```

## Acceptance Criteria

- [ ] **X11 路径**：删除 `~/.config/fl_picraft/window_state.ini` 后启动，窗口 ≈ 主屏 workarea 80% 居中；resize → 退出 → 再启动 → 尺寸 + 位置都恢复。
- [ ] **Wayland 路径**：同上，但位置由 compositor 决定（不要求精确居中），尺寸恢复正确。
- [ ] 拖窗口边角缩小至 < 1280×800 → 卡住（两个会话都生效）。
- [ ] 拔掉外接屏 / 切换 Wayland session → 重启 → 窗口在某可见屏上。
- [ ] HiDPI 缩放（GNOME 2x scale）下 80% 计算正确（用 logical pixels，不需额外换算）。
- [ ] `flutter build linux` 成功；不需要新增 CMake 依赖。

## Out of Scope

- GTK 4 兼容（Flutter Linux runner 锁 GTK 3）。
- maximized / fullscreen 状态持久化。
- GSettings 替代 INI。
- tiling Wayland 合成器（sway / Hyprland）的位置 / 尺寸 hint 兼容性（人家本来就 tile，本任务不强求）。

## Smoke Verify Script

```bash
rm -f ~/.config/fl_picraft/window_state.ini
flutter run -d linux
# X11: 期望 80% 居中
# Wayland: 期望 80% 尺寸，位置由 compositor 决定
# resize 并退出，再 flutter run → 期望恢复
```
