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

## Data-Layer Patterns

These two patterns govern how the `data/datasources/` and
`data/repositories/` layers stay clean of third-party / platform leakage.
Triggered every time you wrap a Flutter / Dart plugin (image_picker,
super_clipboard, file_picker, http clients, native channels…).

### Pattern: Data-source DTO isolation

**Problem**: Plugin SDKs return their own concrete types — `XFile` from
`image_picker`, `ClipboardDataReader` from `super_clipboard`,
`PerformDropEvent` from `super_drag_and_drop`. If a `*_datasource.dart`
exposes those types in its public API, the repository (and any future
caller) ends up importing the plugin just to name the parameter — the
abstraction leak that `cross-layer-thinking-guide.md` calls "Mistake 3:
Leaky Abstractions".

**Solution**: Define a small, library-agnostic DTO in
`domain/entities/` (e.g. `RawImageBytes`). Each datasource accepts /
returns the DTO and keeps the plugin types confined to its own file.
Repository methods compose datasources via the DTO.

**Wrong**:
```dart
// data/repositories/image_import_repository_impl.dart
import 'package:image_picker/image_picker.dart';   // ← plugin leaks into repo
import 'package:super_clipboard/super_clipboard.dart';

Future<List<ImportedImage>> normalize(List<XFile> files) { ... }
Future<List<ImportedImage>> normalize(ClipboardDataReader reader) { ... }
```

**Correct**:
```dart
// domain/entities/raw_image_bytes.dart      ← zero plugin imports
class RawImageBytes {
  const RawImageBytes({
    required this.bytes,
    this.sourcePath,
    this.suggestedName,
    this.declaredMimeType,
  });
  final Uint8List bytes;
  final String? sourcePath;
  final String? suggestedName;
  final String? declaredMimeType;
}

// data/datasources/gallery_picker_datasource.dart
import 'package:image_picker/image_picker.dart';
Future<List<RawImageBytes>> pick({int limit = 20}) async {
  final files = await ImagePicker().pickMultiImage(limit: limit);
  return [for (final f in files) RawImageBytes(bytes: await f.readAsBytes(), ...)];
}

// data/repositories/image_import_repository_impl.dart
// ↑ has zero plugin imports; only knows RawImageBytes
Future<ImportResult> importRawBytes(List<RawImageBytes> raw) { ... }
```

**Why it works**: The repository is testable with plain `RawImageBytes`
fixtures — no need to mock `XFile` or `ClipboardDataReader`. Adding a
fifth import source (e.g. cloud) means writing one new datasource that
emits `RawImageBytes`; the repository signature does not change.

### Pattern: Platform-aware datasource dispatch

**Problem**: A single Flutter app must run on six platforms but most
plugins only cover a subset. `image_picker` doesn't expose multi-select
on desktop; `file_picker` doesn't expose camera capture on mobile. If
the dispatch lives in the presentation layer (e.g. an `if (kIsWeb)`
inside a widget's `onTap`), every consumer reimplements the same
platform check — and the plugin import leaks into the widget tree.

**Solution**: Hide the platform branching inside the datasource. The
public method is a single signature; the body switches on
`defaultTargetPlatform` / `kIsWeb` and delegates to the appropriate
plugin. Presentation widgets call one method and never know which plugin
runs.

**Correct**:
```dart
// data/datasources/gallery_picker_datasource.dart
class GalleryPickerDataSource {
  Future<List<RawImageBytes>> pickMulti({required int limit}) {
    if (_isDesktop) return _pickViaFilePicker(limit);     // file_picker
    return _pickViaImagePicker(limit);                    // image_picker (mobile/web)
  }

  bool get _isDesktop =>
      !kIsWeb && {TargetPlatform.macOS, TargetPlatform.windows,
                  TargetPlatform.linux}.contains(defaultTargetPlatform);
}
```

For datasources where an entire source is **unavailable** on a platform
(e.g. camera on desktop), apply **three-layer defense**:
1. Static `isSupported` getter on the datasource — UI reads this to
   hide the entry-point button.
2. Repository short-circuits with a typed failure (e.g.
   `UnsupportedSource('camera')`) before calling the datasource — so
   misbehaving callers fail loudly with a domain-shape error, not a
   stack trace.
3. Datasource itself throws `UnsupportedError` — last-line guarantee
   that we never invoke the wrong plugin on the wrong platform.

```dart
class CameraCaptureDataSource {
  static bool get isSupported =>
      !kIsWeb && {TargetPlatform.android, TargetPlatform.iOS}
          .contains(defaultTargetPlatform);

  Future<RawImageBytes?> capture() {
    if (!isSupported) {
      throw UnsupportedError('Camera capture unavailable on this platform.');
    }
    // ...
  }
}
```

**Why three layers**: UI defense alone breaks if a future feature
forgets the check. Repository defense alone leaks plugin types into the
error path. Datasource defense alone surfaces an opaque crash to the
user. All three together let UI hide the button, give the repository a
typed failure for snackbar UX, and still crash loudly during dev if a
new caller is added that doesn't check `isSupported`.

### Pattern: Isolate-safe rasterizer in `data/`

**Problem**: Image composition steps in the export pipeline (watermark
overlay, format encode, thumbnail downscale) are CPU-heavy and must run
off the main isolate via `compute()` to keep the UI responsive. But
`dart:ui` text/canvas APIs (`TextPainter`, `Canvas.drawParagraph`,
`PictureRecorder`) only function on the main isolate — calling them from
`compute()` either throws or returns blank output.

**Solution**: Keep any `data/` function that is callable from `compute()`
**free of `dart:ui` imports**. Use pure-Dart libraries (the `image`
package's `Image` + `drawString` + `encodePng`/`encodeJpg`) so the same
function runs on either isolate.

| Layer | Allowed image APIs | Forbidden when isolate-callable |
|-------|--------------------|----------------------------------|
| `domain/` | None (pure logic only — geometry, config) | Everything `dart:ui`-shaped |
| `data/` (isolate-callable) | `package:image` (pure Dart), raw `Uint8List` | `dart:ui` `TextPainter`, `Canvas`, `PictureRecorder`, `MediaQuery`-derived sizes |
| `presentation/` | Anything (`CustomPainter`, `RepaintBoundary`, `dart:ui`) | — (main isolate by definition) |

**Wrong**:
```dart
// data/watermark_renderer.dart — looks fine, blows up under compute()
import 'dart:ui' as ui;

Future<Uint8List> applyWatermark(Uint8List src, WatermarkConfig cfg) async {
  final image = await decodeImageFromList(src);          // dart:ui
  final recorder = ui.PictureRecorder();                 // dart:ui
  final canvas = ui.Canvas(recorder);
  final tp = TextPainter(text: TextSpan(text: cfg.text))..layout();
  tp.paint(canvas, computeAnchor(cfg.anchor, ...));      // throws in isolate
  // ...
}

// caller
final bytes = await compute(applyWatermark, request);    // hangs / errors
```

**Correct**:
```dart
// data/watermark_renderer.dart — pure Dart, isolate-safe
import 'package:image/image.dart' as img;

Future<Uint8List> applyWatermark(Uint8List src, WatermarkConfig cfg) async {
  if (!cfg.hasVisibleWatermark) return src;              // short-circuit
  final decoded = img.decodeImage(src);                  // pure Dart
  if (decoded == null) return src;

  final font = _pickFont(cfg.fontSize);                  // bitmap font
  final (x, y) = computeAnchor(
    cfg.anchor,
    canvas: (decoded.width, decoded.height),
    text: img.measureString(font, cfg.text),
  );
  img.drawString(decoded, cfg.text, font: font, x: x, y: y,
                 color: img.ColorRgba8(255, 255, 255, (cfg.opacity * 255).round()));
  return Uint8List.fromList(
    _preservesFormat(src) == ImageFormat.png ? img.encodePng(decoded) : img.encodeJpg(decoded),
  );
}

// caller
final bytes = await compute(_applyWatermarkEntry, request);  // works
```

**Trade-off — bitmap font glyph coverage**: The `image` package ships
`arial14` / `arial24` / `arial48` which are **ASCII-only**. Non-ASCII
(CJK, emoji) characters silently fall through to blank space. Three
mitigations, in order of cost:

1. **Document the limitation** at the public-API doc comment (current
   approach for watermark — see `lib/features/export/data/watermark_renderer.dart`).
2. **Pre-compile a custom bitmap font** with Unicode coverage via
   `image`'s `BitmapFont.fromZip` and ship it as an asset.
3. **Split the path**: keep an isolate-safe pure-Dart implementation
   for ASCII and route Unicode inputs through a main-isolate `dart:ui`
   renderer (slower, but full coverage). Only worth it when Unicode
   watermarks are a product requirement, not a nice-to-have.

**Validation**: For any new `data/` rasterizer,
1. `grep -n "package:flutter\|dart:ui" lib/features/<f>/data/` returns
   no hits in files marked `// isolate-callable`.
2. Add a test that calls the function via `await compute(fn, input)` —
   not just `await fn(input)`. Many `dart:ui` failures only surface on
   the isolate path.

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
