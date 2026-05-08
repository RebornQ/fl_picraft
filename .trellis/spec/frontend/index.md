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

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#6750a4` | CTAs, key elements |
| Secondary | `#625b71` | Secondary actions |
| Tertiary | `#7d5260` | Accents, badges |
| Neutral | `#79747e` | Backgrounds |

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