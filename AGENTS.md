# Repository Guidelines

## Project Structure & Module Organization

- `lib/`: Dart source code (app entrypoint is `lib/main.dart`).
- `test/`: Widget/unit tests (example: `test/widget_test.dart`).
- Platform folders: `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`.
- Root config: `pubspec.yaml` (dependencies + SDK), `analysis_options.yaml` (lints).
- Local artifacts: `docs/` exists in the workspace but is currently gitignored; don’t rely on it
  being present in PRs.

## Build, Test, and Development Commands

Run these from the repo root:

- `flutter pub get`: Install dependencies.
- `flutter run`: Run the app on a connected device/emulator.
- `flutter test`: Run all tests.
- `flutter analyze`: Static analysis (must be clean for PRs).
- `dart format .`: Auto-format the codebase.
- `flutter build apk` / `flutter build ios --no-codesign`: Create release builds (as applicable).

## Coding Style & Naming Conventions

- Formatting: use `dart format .` (don’t hand-format).
- Lints: this repo uses `flutter_lints` via `analysis_options.yaml`; fix warnings instead of
  ignoring.
- Naming: `UpperCamelCase` for types/widgets, `lowerCamelCase` for variables/functions,
  `snake_case.dart` for files (e.g., `api_client.dart`).

## Testing Guidelines

- Framework: `flutter_test`.
- File naming: keep tests in `test/` and name them `*_test.dart`.
- Run a single test file: `flutter test test/widget_test.dart`.

## Commit & Pull Request Guidelines

- Commit history is minimal (only “init project”), so no convention is established yet. Prefer
  Conventional Commits (e.g., `feat: …`, `fix: …`, `chore: …`).
- PRs should include: what changed, how to verify, and screenshots/GIFs for UI changes.
- Before opening a PR: run `dart format .`, `flutter analyze`, and `flutter test`.

## Security & Configuration Tips

- Never commit secrets (API keys/tokens). Prefer build-time configuration via `--dart-define` and
  document required values in the PR description.

## Target Architecture

**Pattern**: Clean Architecture + Feature-First + Riverpod + Dio + Material Design 3

### Planned Directory Structure

```
lib/
  app/                  # App-level config (routes, theme, DI)
    app.dart
    router.dart
    theme/
  core/                 # Shared utilities, constants, extensions
    network/            # Dio client, interceptors
    storage/            # Local persistence
    theme/              # MD3 theme, design tokens from design.md
    error/
    utils/              # Common helpers
    widgets/
  features/
    <feature>/
      data/           # Repositories impl, data sources, models
      domain/         # Entities, repository interfaces, use cases
        presentation/   # Screens, widgets, Riverpod providers
```

Each feature is self-contained with `data/`, `domain/`, `presentation/` layers. Cross-feature
dependencies go through `domain/` interfaces.

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
