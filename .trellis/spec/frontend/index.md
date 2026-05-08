# Frontend Development Guidelines

> Best practices for Flutter development in this project.

---

## Overview

This directory contains guidelines for Flutter development following Clean Architecture + Feature-First + Riverpod + Material Design 3.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Module organization, feature-first layout | ✅ Complete |
| [Component Guidelines](./component-guidelines.md) | Widget patterns, props, Material Design 3 | ✅ Complete |
| [Provider Guidelines](./hook-guidelines.md) | Riverpod providers, state patterns | ✅ Complete |
| [State Management](./state-management.md) | Riverpod patterns, when to use providers | ✅ Complete |
| [Quality Guidelines](./quality-guidelines.md) | Linting, testing, code review | ✅ Complete |
| [Type Safety](./type-safety.md) | Dart null safety, sealed classes, generics | ✅ Complete |
| [Dependencies & Platforms](./dependencies-and-platforms.md) | pubspec, Android/iOS/macOS manifests | ✅ Complete |

---

## Quick Reference

### Tech Stack

- **Framework**: Flutter 3.10+
- **State Management**: Riverpod
- **Architecture**: Clean Architecture + Feature-First
- **UI**: Material Design 3
- **Typography**: Inter font family
- **Testing**: flutter_test

### Key Design Tokens

> Authoritative source: `lib/app/theme/app_colors.dart` (lifted from
> `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_1_首页/code.html`).
> Do not duplicate the table elsewhere — see
> [Component Guidelines → Design Tokens](./component-guidelines.md#design-tokens-from-ui-design-html-mocks).

| Token | Light value | Usage |
|-------|-------------|-------|
| Primary | `#4F378A` | CTAs, active nav, primary feature card |
| Secondary | `#625B71` | Secondary text/icons |
| Tertiary | `#633B48` | Accents, badges (tips) |
| Surface / Background | `#FEF7FF` | Body bg, cards |
| Surface-container-low | `#F9F1FD` | Feature cards |

### Common Commands

```bash
flutter pub get        # Install dependencies
flutter run            # Run app
flutter test           # Run tests
flutter analyze        # Static analysis
dart format .          # Format code
```

---

**Language**: All documentation should be written in **English**.