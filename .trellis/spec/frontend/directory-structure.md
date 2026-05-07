# Directory Structure

> How Flutter code is organized in this project.

---

## Overview

This project follows **Clean Architecture + Feature-First** pattern with Riverpod for state management and Material Design 3 for UI.

Each feature is self-contained with `data/`, `domain/`, `presentation/` layers. Cross-feature dependencies go through `domain/` interfaces.

---

## Directory Layout

```
lib/
  app/                  # App-level config (routes, theme, DI)
    app.dart            # Root widget with providers
    router.dart         # GoRouter configuration
    theme/              # App theme, color schemes
  core/                 # Shared utilities, constants, extensions
    network/            # Dio client, interceptors (future)
    storage/            # Local persistence (shared_preferences, hive, etc.)
    theme/              # MD3 theme, design tokens from DESIGN.md
    error/              # Failure types, error handling
    utils/              # Common helpers, extensions
    widgets/            # Shared widgets (buttons, inputs, cards)
  features/
    <feature>/
      data/             # Repositories impl, data sources, models (DTOs)
        datasources/    # Local/remote data sources
        models/         # Data models (JSON serializable)
        repositories/   # Repository implementations
      domain/           # Entities, repository interfaces, use cases
        entities/       # Business entities
        repositories/   # Repository interfaces (abstract)
        usecases/       # Use case classes (optional, for complex logic)
      presentation/     # Screens, widgets, Riverpod providers
        providers/      # Riverpod providers (StateNotifier, StateProvider)
        screens/        # Full-screen widgets
        widgets/        # Feature-specific widgets
  main.dart             # Entry point
```

---

## Module Organization

### Feature Module Structure

Each feature under `lib/features/` follows the same pattern:

```
features/
  auth/                  # Example: authentication feature
    data/
      datasources/
        auth_local_ds.dart    # Local storage (tokens, user prefs)
        auth_remote_ds.dart   # API calls (if needed in future)
      models/
        user_model.dart       # DTO for API responses
      repositories/
        auth_repository_impl.dart
    domain/
      entities/
        user.dart             # Business entity
      repositories/
        auth_repository.dart  # Interface
      usecases/
        login_usecase.dart    # (Optional)
    presentation/
      providers/
        auth_provider.dart    # Riverpod StateNotifier
        auth_state.dart       # State class
      screens/
        login_screen.dart
        register_screen.dart
      widgets/
        auth_form.dart
```

### Cross-feature Dependencies

- Features should **never** import from another feature's `data/` or `presentation/` layers
- Cross-feature communication goes through `domain/` interfaces
- Use Riverpod providers for shared state between features

---

## Naming Conventions

### Files

| Type | Convention | Example |
|------|------------|---------|
| Screens | `*_screen.dart` | `login_screen.dart` |
| Widgets | `*_widget.dart` or descriptive name | `user_avatar.dart` |
| Providers | `*_provider.dart` | `auth_provider.dart` |
| State classes | `*_state.dart` | `auth_state.dart` |
| Entities | `*.dart` (singular noun) | `user.dart` |
| Models (DTOs) | `*_model.dart` | `user_model.dart` |
| Repositories | `*_repository.dart` (interface), `*_repository_impl.dart` (impl) | `auth_repository.dart` |
| Data sources | `*_ds.dart` or `*_datasource.dart` | `auth_local_ds.dart` |
| Use cases | `*_usecase.dart` | `login_usecase.dart` |

### Dart Naming (per official style)

- **Classes**: `UpperCamelCase` → `UserRepository`, `LoginScreen`
- **Variables/Functions**: `lowerCamelCase` → `currentUser`, `fetchUserData()`
- **Constants**: `lowerCamelCase` → `maxRetryCount`, `defaultTimeout`
- **Private members**: Prefix with `_` → `_userRepository`, `_handleLogin()`

---

## Examples

### Adding a New Feature

1. Create feature directory: `lib/features/settings/`
2. Create layer directories: `data/`, `domain/`, `presentation/`
3. Start from domain layer (entities, repository interfaces)
4. Implement data layer (models, data sources, repository impl)
5. Build presentation layer (providers, screens, widgets)

### Shared Widgets Location

- **Feature-specific** → `lib/features/<feature>/presentation/widgets/`
- **Shared across features** → `lib/core/widgets/`
