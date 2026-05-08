# Foundation: Project Init & Base Architecture

> **Parent task** for the Fl PiCraft MVP. Two subtasks track project bootstrap and architectural scaffolding.

## Goal

Bring the Flutter project from the default counter template to a runnable application shell with dependencies, navigation, theming, and state management wired up. Every downstream feature (image import, stitching, grid split, export) builds on this foundation.

## Why this is parent-only

Two distinct deliverables:

1. **Pure plumbing** (pubspec, lints, platform manifests) — no UI/logic.
2. **Runtime scaffolding** (router, theme, ProviderScope, BottomNav) — UI surface, but no domain logic.

Splitting them keeps PRs reviewable and lets the developer land deps before touching `lib/`.

## Subtasks

| Subtask | What it covers |
|---------|---------------|
| [`05-08-project-init`](../05-08-project-init/prd.md) | pubspec deps, analysis_options, multi-platform manifests |
| [`05-08-base-architecture`](../05-08-base-architecture/prd.md) | GoRouter, MD3 theme, ProviderScope, BottomNav, Home shell |

## Acceptance Criteria (parent-level)

- [ ] `flutter run` launches into the Home screen with bottom navigation visible on all 6 platforms
- [ ] Hot reload preserves Riverpod state
- [ ] `flutter analyze` clean
- [ ] All children completed

## Out of Scope

- Domain models for stitch/grid features (each feature owns its own `domain/`)
- Network layer (the app is fully offline)
- Persistent storage of past works (gallery is a future enhancement)

## References

- Total PRD: [`docs/PRD/fl_picraft_prd_177bbaaa.plan.md`](../../../docs/PRD/fl_picraft_prd_177bbaaa.plan.md)
- UI Home: [`docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_1_首页/code.html`](../../../docs/UI%20Design/Fl_PiCraft_stitch_prd_ui_generator/_1_%E9%A6%96%E9%A1%B5/code.html)
- Frontend spec index: `.trellis/spec/frontend/index.md`
