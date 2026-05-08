# Base Architecture

> Subtask of [`05-08-foundation`](../05-08-foundation/prd.md)

## Goal

Replace the default counter template with a real application shell: GoRouter routes, MD3 theme matching the UI design, ProviderScope-wrapped root, BottomNav layout, and the Home screen that lists the two creative entry cards.

## Deliverables

```
lib/
  main.dart                         # ProviderScope + AppRoot
  app/
    app.dart                        # MaterialApp.router root
    router.dart                     # GoRouter (/ home, /stitch, /grid, /export, /settings)
    theme/
      app_theme.dart                # MD3 ThemeData light + dark
      app_colors.dart               # Tokens lifted from UI design
  core/
    widgets/
      bottom_nav_bar.dart           # 4-tab nav: 作品库 / 长图拼接 / 宫格切图 / 设置
      app_scaffold.dart             # Wraps body + bottom nav
  features/
    home/
      presentation/
        screens/
          home_screen.dart          # Greeting + 2 feature cards + tips + recent works grid
        widgets/
          feature_card.dart         # Reusable card for stitch/grid entries
          tips_banner.dart          # Lightbulb tip card
          recent_works_grid.dart    # 3-col aspect-square thumbnails
```

## MD3 design tokens (extracted from UI design)

UI source: `_1_首页/code.html` lines 14–63

| Token | Light value | Usage |
|-------|-------------|-------|
| `primary` | `#4f378a` (or `#6750a4` for primary-container) | CTAs, active nav |
| `secondary` | `#625b71` | Secondary text/icons |
| `tertiary` | `#633b48` | Accents (tips badge) |
| `background` | `#fef7ff` | Body bg |
| `surface` | `#fef7ff` | Cards |
| `surface-container-low` | `#f9f1fd` | Feature cards |
| `outline-variant` | `#cbc4d2` | Borders |
| `error` | `#ba1a1a` | Destructive actions |

Font: Inter (already loaded by `flutter_lints`-compatible default; add as a `google_fonts` package or manual asset).

## Router map

| Path | Screen | Notes |
|------|--------|-------|
| `/` | `HomeScreen` | Greeting + feature cards |
| `/stitch` | `StitchEditorScreen` | Placeholder for now (real impl in `05-08-long-stitch`) |
| `/grid` | `GridEditorScreen` | Placeholder for now (real impl in `05-08-grid-split`) |
| `/export` | `ExportScreen` | Placeholder for now (real impl in `05-08-export-watermark`) |
| `/settings` | `SettingsScreen` | Stub |

## Acceptance Criteria

- [ ] `flutter run` boots into `HomeScreen` with greeting "你好，创作者"
- [ ] BottomNav has 4 tabs and switches routes via GoRouter
- [ ] Two feature cards on Home are visible with the right MD3 colors
- [ ] Tips banner and recent-works grid (3 placeholders) render
- [ ] Hot reload preserves navigation state
- [ ] All route paths resolve without 404

## Out of Scope

- Real stitch / grid / export screens (placeholder only)
- Drawer or settings content (only stub)
- Image asset for tips icon (use `Icons.lightbulb` or material symbols)

## Dependencies

- Requires: `05-08-project-init`
- Blocks: every feature task (everything mounts under these routes)

## References

- UI: `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_1_首页/code.html`
- CLAUDE.md → Target Architecture
- Spec: `.trellis/spec/frontend/directory-structure.md`, `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/state-management.md`
