# Type Safety

> Type safety patterns in this project (Dart).

---

## Overview

Dart has a sound type system with null safety. This project leverages:
- **Null safety** (`?` for nullable types)
- **Type inference** (`var`, `final`, `const`)
- **Generics** for type-safe collections
- **Sealed classes** for exhaustive pattern matching (Dart 3)

---

## Type Organization

### Where Types Live

| Type | Location |
|------|----------|
| Entities | `features/<feature>/domain/entities/` |
| DTOs/Models | `features/<feature>/data/models/` |
| State classes | `features/<feature>/presentation/providers/` |
| Shared types | `core/types/` or `core/models/` |
| Failures/Errors | `core/error/` |

### Type File Naming

```dart
// domain/entities/user.dart
class User { ... }

// data/models/user_model.dart
class UserModel extends User { ... }

// presentation/providers/auth_state.dart
@freezed
class AuthState with _$AuthState { ... }
```

---

## Null Safety

### Nullable vs Non-Nullable

```dart
// Non-nullable (always has a value)
String name;           // Must be initialized
final int count = 0;   // Can't be null

// Nullable (can be null)
String? nickname;      // Can be null
int? optionalValue;    // Use ?. for access
```

### Null Assertion vs Null Check

```dart
// ❌ Avoid null assertion (throws if null)
final name = user!.name;

// ✅ Use null check with default
final name = user?.name ?? 'Unknown';

// ✅ Use pattern matching
if (user case User(:final name)) {
  print(name);
}
```

### Late Initialization

```dart
// Use late for deferred initialization
class _MyState extends State<MyWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }
}
```

---

## Validation

### Form Validation

```dart
// Use validators in TextFormField
TextFormField(
  validator: (value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a value';
    }
    if (value.length < 3) {
      return 'Minimum 3 characters';
    }
    return null;  // Valid
  },
)
```

### Model Validation

```dart
class User {
  const User({
    required this.email,
    required this.name,
  });

  final String email;
  final String name;

  // Factory with validation
  static User? fromJson(Map<String, dynamic> json) {
    final email = json['email'] as String?;
    final name = json['name'] as String?;

    if (email == null || name == null) return null;
    if (!_isValidEmail(email)) return null;

    return User(email: email, name: name);
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}
```

---

## Common Patterns

### Sealed Classes (Dart 3)

Use sealed classes for exhaustive pattern matching:

```dart
// core/error/failure.dart
sealed class Failure {}

class NetworkFailure extends Failure {
  final String message;
  NetworkFailure(this.message);
}

class CacheFailure extends Failure {
  final String message;
  CacheFailure(this.message);
}

class ValidationFailure extends Failure {
  final Map<String, String> errors;
  ValidationFailure(this.errors);
}

// Usage with exhaustive matching
String getErrorMessage(Failure failure) {
  return switch (failure) {
    NetworkFailure(:final message) => 'Network error: $message',
    CacheFailure(:final message) => 'Cache error: $message',
    ValidationFailure(:final errors) => 'Validation failed',
  };
}
```

### Records (Dart 3)

```dart
// Named records for structured data
typedef GeoLocation = ({double lat, double lng});

final GeoLocation location = (lat: 37.7749, lng: -122.4194);
print('Lat: ${location.lat}, Lng: ${location.lng}');

// Positional records
typedef Point = (double x, double y);
final Point point = (10.0, 20.0);
```

### Generics

```dart
// Generic repository interface
abstract class Repository<T> {
  Future<T> getById(String id);
  Future<List<T>> getAll();
  Future<void> save(T entity);
  Future<void> delete(String id);
}

// Generic result type
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final String message;
  const Failure(this.message);
}
```

---

## Design Decisions

### Decision: Flag-on-existing-variant vs new enum variant

**Context**: An enum already models a finite set of modes/states (e.g.
`StitchMode { vertical, horizontal }`). A new feature (e.g. "movie subtitle"
overlay) needs to alter the rendering pipeline. Two ways to model it:

- **Option A — Add a third variant**: `StitchMode { vertical, horizontal,
  movieSubtitle }`. Every exhaustive switch on `StitchMode` compile-errors
  at every site that needs an update — strong compile-time safety.
- **Option B — Add a flag on the existing state class**: keep
  `StitchMode { vertical, horizontal }`, add `bool subtitleOnlyMode` +
  `double subtitleBandHeight` to the state class, gate behavior with
  `mode == vertical && subtitleOnlyMode && images.length > 1`.

**Decision**: Pick Option A (new variant) when the new behavior is a
peer mode the user picks alongside the others; pick Option B (flag) when
the new behavior is a **modifier** layered on top of an existing mode.

**Concrete signals that point to flag-overlay (Option B)**:
1. The PRD / UI mock represents the new behavior as a separate switch /
   toggle, not a new segment on the mode picker
2. The new behavior depends on another mode being active (e.g. "only
   makes sense when in vertical mode")
3. The new behavior should be **sticky** across mode changes (toggle
   position persists when the user swaps modes and returns)
4. There are simple edge-case rules that disable the behavior
   (e.g. "hide when image count < 2", "ignore in horizontal mode")
5. The state class already reserved fields for the future behavior,
   indicating the original designer intended a flag

**Concrete signals that point to new variant (Option A)**:
1. The new mode is mutually exclusive with all existing modes at the
   user's mental level (a third radio button, not a toggle)
2. Every site that switches on the enum needs different behavior for
   the new mode (no "one site dispatches all" simplification possible)
3. You want compile-time guarantees that no future site accidentally
   silently treats the new mode as one of the old ones

**How to mitigate Option B's loss of compile-time safety**: route every
mode-dependent dispatch through a single domain function (e.g.
`computeStitchLayout`) that bakes the flag check in **before** the
`switch (mode)`. Then every consumer (preview widget, isolate renderer,
exporter) reads from that one dispatch point — there's no risk of a
caller forgetting to check the flag because they never see it.

**Example**:

```dart
// Option B done well: single dispatch site
StitchLayout computeStitchLayout({
  required List<Size> sizes,
  required StitchMode mode,
  required double spacing,
  required StitchBorder border,
  bool subtitleOnlyMode = false,
  double subtitleBandHeight = kDefaultSubtitleBandHeight,
}) {
  if (mode == StitchMode.vertical &&
      subtitleOnlyMode &&
      sizes.length >= 2) {
    return _layoutMovieSubtitle(sizes, subtitleBandHeight, border);
  }
  return switch (mode) {
    StitchMode.vertical => _layoutVertical(sizes, spacing, border),
    StitchMode.horizontal => _layoutHorizontal(sizes, spacing, border),
  };
}
```

All consumers (`StitchImageRenderer`, `_PreviewSurface`, future export)
call `computeStitchLayout` — there is no second site that switches on
mode without the flag check.

**Anti-pattern**: scattering `if (subtitleOnlyMode) { ... }` checks at
multiple call sites. That is the situation Option B is rightfully
criticised for, and where Option A's compile-time safety wins.

### Pattern: Sealed payload + enum kind for multi-source dispatch

**Problem**: A controller has to handle multiple sources of the same operation. Example: the export pipeline accepts input from the **stitch** editor (a single composed image) or the **grid** editor (a list of cells with per-cell metadata). Naive solutions:

- One controller per source → screen UI duplicated; settings (watermark / format / quality) live in two places
- One controller with `bool isGrid` + `T? stitchPayload` + `U? gridPayload` → field validity becomes a runtime convention nobody enforces

**Solution**: split the model into **two co-variants**:

1. A `sealed class` data load (`ExportSource`) — each variant carries its own typed payload (no nullable fields)
2. An `enum` kind (`ExportSourceKind { stitch, grid }`) — pure router discriminator, used to keep the upstream UI / button label / `canExportProvider` source-aware **without** forcing every consumer to hold the full payload

Dispatch sites switch on **the enum**, then resolve the payload from the source-of-truth provider:

```dart
sealed class ExportSource {
  const ExportSource();
}
final class ExportStitchSource extends ExportSource {
  const ExportStitchSource(this.request);
  final StitchRenderRequest request;
}
final class ExportGridSource extends ExportSource {
  const ExportGridSource(this.request);
  final GridRenderRequest request;
}

enum ExportSourceKind { stitch, grid }

class ExportController extends Notifier<ExportState> {
  Future<SaveResult> save() async {
    final source = _buildSource();
    if (source == null) return const SaveFailure(message: '没有可导出的图片');
    return ref.read(exportRepositoryProvider).exportAndSave(source);
  }

  ExportSource? _buildSource() {
    final kind = ref.read(currentExportSourceKindProvider);
    return switch (kind) {
      ExportSourceKind.stitch => _buildStitchSource(),
      ExportSourceKind.grid => _buildGridSource(),
    };
  }
}
```

**Why two types and not one**:

- The **enum** is cheap to expose globally (a single `StateProvider<ExportSourceKind>` survives across screens and is web-refresh-safe). It tells the export screen which editor it came from without holding the heavy payload.
- The **sealed payload** is only built at dispatch time from the live editor state. It carries all the type-safe data the renderer needs and forces every dispatch site to handle every variant.

**Exhaustive switches everywhere**: every consumer of the enum (controller dispatch, save-button label provider, `canExportProvider`, back-navigation handler) uses `switch` on the enum without a `default`. Adding a third kind (e.g. `movieSubtitle`) compile-errors every site that needs an update — same compile-time safety as Option A in the previous decision.

**Where this lives** (current implementations):
- `lib/features/export/domain/entities/export_source.dart` — sealed payload
- `lib/features/export/presentation/providers/export_dispatch.dart` — enum + derived providers
- `lib/features/export/presentation/providers/export_controller.dart:106-121` — dispatch site

**Required tests**: assert every enum variant's branch in `_buildSource()` and `canExportProvider` / `exportSaveButtonLabelProvider`; assert the sealed payload's `exportAndSave` dispatches to the right renderer. Compiler enforces exhaustiveness — tests guard the runtime wiring.

---

### Pattern: Parallel enum domains with explicit bridge function

**Problem**: Two modules each need an enum that **happens to have the same value set today** but represents different domain concepts. Example: the **export** module has `ExportSourceKind { stitch, grid }` ("which editor invoked the export") and the **image_import** module has `ImageImportSessionKind { stitch, grid }` ("which editor owns this import session"). Tempting naive solutions:

- **Reuse one enum across both modules** → forces `image_import` to import from `export` (reverse layer dependency: a `domain/entities/` enum now depends on a sibling feature's `presentation/providers/`) and entangles the two evolution timelines. The day `export` adds `ExportSourceKind.pdfMerge` (a future PDF-combine source that has **no** import session), every `image_import` site silently inherits a value it can't satisfy.
- **Parameterize a single enum with a discriminator string** → over-engineered for two values and erodes the compile-time exhaustiveness that makes enums useful in the first place.

**Solution**: define both enums independently in each module's own layer. Provide a single explicit **bridge function** living on the side that *consumes* the mapping, not on either domain enum:

```dart
// lib/features/image_import/domain/entities/image_import_session_kind.dart
enum ImageImportSessionKind { stitch, grid }

// lib/features/export/presentation/providers/export_dispatch.dart
enum ExportSourceKind { stitch, grid }

ImageImportSessionKind sessionKindFor(ExportSourceKind kind) {
  return switch (kind) {
    ExportSourceKind.stitch => ImageImportSessionKind.stitch,
    ExportSourceKind.grid => ImageImportSessionKind.grid,
  };
}
```

**Why two types and not one**:

- **No reverse layer dependency**: the import enum lives in `domain/entities/` and knows nothing about export's `presentation/providers/`. Each module is closed under its own dependency arrows.
- **Independent evolution**: if export grows a value with no import counterpart (`pdfMerge`), the bridge is the single place that compile-errors. You can't accidentally route a PDF-merge export through a per-editor import session.
- **Exhaustive switch on the bridge**: adding a value to either enum forces the bridge to be updated (or kept divergent by design). The compiler enforces the contract.

**When NOT to use**: if two modules genuinely model the **same** domain concept (e.g. both `auth` and `profile` use `UserRole { admin, member, guest }`) — there is one underlying truth and the enum belongs in `core/` or a shared `domain/`. Use this pattern only when the values happen to coincide today but the **concepts** are independent (which is most cases at module boundaries).

**Don't write a generic `Map` instead of a `switch`**:

```dart
// ❌ Don't — loses exhaustiveness; silently goes stale when either enum changes
const _kindBridge = <ExportSourceKind, ImageImportSessionKind>{
  ExportSourceKind.stitch: ImageImportSessionKind.stitch,
  ExportSourceKind.grid: ImageImportSessionKind.grid,
};
```

A `Map` literal won't compile-error when either enum gains a value; a `switch` will. Always prefer the `switch`.

**Where this lives** (current implementations):
- `lib/features/image_import/domain/entities/image_import_session_kind.dart` — independent enum + stability dartdoc (enum value names are Riverpod family cache keys; rename = break test overrides)
- `lib/features/export/presentation/providers/export_dispatch.dart::sessionKindFor` — the bridge

**Related**: `state-management.md` → "Pattern: Per-mode session isolation via `.family`" — `ImageImportSessionKind` is the family key.

---

## Forbidden Patterns

### ❌ Don't

```dart
// Using dynamic
dynamic value = getData();  // ❌

// Ignoring null safety
String name = null;  // ❌ Compile error

// Type casting without checks
final user = data as User;  // ❌ Can throw

// Raw Map types
Map data = {};  // ❌
```

### ✅ Do

```dart
// Explicit types
User? value = getData();  // ✅

// Null safety
String? name = null;  // ✅

// Type checking
if (data is User) {
  final user = data;  // ✅ Smart cast
}

// Typed Map
Map<String, dynamic> data = {};  // ✅
```

---

## Type Utilities

### Extension Methods

```dart
// core/extensions/string_extensions.dart
extension StringExtensions on String {
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }

  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

// Usage
final email = 'test@example.com';
if (email.isValidEmail) {
  print(email.capitalize);  // 'Test@example.com'
}
```

### Type Guards

```dart
// Using pattern matching
Object processValue(Object value) {
  return switch (value) {
    String s => 'String: $s',
    int i => 'Int: $i',
    List l => 'List with ${l.length} items',
    _ => 'Unknown type',
  };
}
```

---

## Best Practices

1. **Prefer non-nullable types** - Use `?` only when necessary
2. **Use type inference** - `final` and `var` reduce boilerplate
3. **Sealed classes for states** - Exhaustive pattern matching
4. **Validate at boundaries** - Check input from external sources
5. **Avoid `dynamic`** - Use `Object` or specific types
6. **Use `is` for type checks** - Avoid `as` without checking
