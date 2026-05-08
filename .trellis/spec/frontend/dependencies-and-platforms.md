# Dependencies & Platform Manifests

> Conventions for `pubspec.yaml` deps and per-platform manifests / entitlements.
> Captured from the `05-08-project-init` task — keeps downstream features from
> re-discovering the same gotchas.

---

## Scope / Trigger

Apply this spec when you:
- Add or upgrade a runtime dependency in `pubspec.yaml`
- Touch `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`
- Touch `macos/Runner/*.entitlements` (Debug or Release)
- Modify `android/app/build.gradle.kts` SDK targets

---

## Dependency Selection

### Convention: Approved package choices

The project has settled on the following packages for cross-platform image
work. Do not silently swap to alternatives.

| Domain | Use | Avoid | Why |
|---|---|---|---|
| Save to mobile gallery | `gal` | `image_gallery_saver` | `image_gallery_saver` is unmaintained; `gal` ships current null-safety and Android 14 scoped storage support |
| Drag-and-drop (desktop + mobile + web) | `super_drag_and_drop` | `desktop_drop` | `super_drag_and_drop` covers all six platforms with one API; `desktop_drop` only handles desktop |
| Clipboard image paste | `super_clipboard` | `clipboard` (string-only) | Paste flow needs binary image read; pairs cleanly with `super_drag_and_drop` (shared native side) |
| State management | `flutter_riverpod` ^2.x | `riverpod` 3.x | 3.x is published but transitive constraints in `share_plus` / `super_clipboard` keep us on 2.x — see "Lock Riverpod to 2.x" below |
| File pick / save dialog (desktop + web) | `file_picker` | `file_selector` | `file_picker` exposes the save dialog on macOS / Windows / Linux which `file_selector` lacks |
| Routing | `go_router` ^14.x | `auto_route`, hand-rolled `Navigator` | Declarative + deep-link-friendly per CLAUDE.md target architecture |
| Typography (Inter) | `google_fonts` ^8.x | Manual `pubspec.yaml` font assets | Same Inter face on every platform with no per-platform asset shipping; `google_fonts.interTextTheme` integrates directly with `ThemeData.textTheme` |

> When `pub outdated` reports a newer-major version, **read the transitive
> graph first**. Upgrading one major often forces a cascade — leave the
> resolved set alone unless every co-dependent package has aligned.

### Convention: `riverpod_annotation` belongs in `dependencies:`, not `dev_dependencies:`

**What**: `riverpod_annotation` (the `@riverpod` annotation) must live under
`dependencies:`. Only `riverpod_generator` + `build_runner` are dev-only.

**Why**: Generated `*.g.dart` files reference symbols from
`riverpod_annotation` at compile time of the *application*, not just at
codegen time. If you put it under `dev_dependencies:`, generated code in
release builds breaks with "package not found".

**Wrong**:
```yaml
dev_dependencies:
  riverpod_annotation: ^2.6.1     # BAD — generated app code can't see it
  riverpod_generator: ^2.6.3
  build_runner: ^2.4.13
```

**Correct**:
```yaml
dependencies:
  riverpod_annotation: ^2.6.1     # OK — referenced from app's generated *.g.dart

dev_dependencies:
  riverpod_generator: ^2.6.3      # OK — runs at codegen time only
  build_runner: ^2.4.13           # OK — runs at codegen time only
```

### Convention: Lock Riverpod to 2.x for now

**What**: Keep `flutter_riverpod` and `riverpod_annotation` on `^2.6.x` until
the rest of the dependency graph (notably `share_plus`, `super_clipboard`,
`super_drag_and_drop`) supports Riverpod 3.x.

**Why**: Mixed 2.x / 3.x in the same graph causes provider-identity
mismatches (a 2.x `Ref` is not assignable to a 3.x `Ref`). The error surfaces
as opaque "type 'X' is not a subtype of 'Y'" at runtime.

**How to apply**: When `pub outdated` shows Riverpod 3.x available, do **not**
upgrade in isolation. Wait until every transitive consumer aligns; revisit
quarterly.

---

## Platform Manifests

### Android: API-versioned permission split

**Required**: Image-picking on Android 13+ uses `READ_MEDIA_IMAGES`. Older
devices (API ≤ 32) need the legacy `READ_EXTERNAL_STORAGE` — but constrained
with `android:maxSdkVersion="32"` so Play Store install audits don't flag it.

**Wrong**:
```xml
<!-- Either of these alone is insufficient OR over-broad -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<!-- ↑ unconstrained = Play Store warning + 13+ device prompts the wrong scope -->
```

**Correct**:
```xml
<!-- Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<!-- Android 12 and below (API ≤ 32) -->
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<!-- Camera capture (independent of API) -->
<uses-permission android:name="android.permission.CAMERA" />
```

**Validation**:
- `READ_MEDIA_IMAGES` declared **without** `maxSdkVersion`.
- `READ_EXTERNAL_STORAGE` declared **with** `android:maxSdkVersion="32"`.
- `CAMERA` declared if any flow uses `image_picker.pickImage(source: ImageSource.camera)`.

### Android: Use Flutter's targetSdkVersion default

**Convention**: `android/app/build.gradle.kts` uses `flutter.targetSdkVersion`
— do not pin a literal number unless you have a specific reason.

```kotlin
defaultConfig {
    minSdk = flutter.minSdkVersion        // Flutter ships sane defaults
    targetSdk = flutter.targetSdkVersion  // Currently 36 on Flutter 3.38.9
    compileSdk = flutter.compileSdkVersion
}
```

**Why**: Pinning a literal makes Flutter SDK upgrades painful. The default
floats with the Flutter SDK and is bumped by the Flutter team alongside the
target API rollout. Override only if you must stay below a Play Store
deadline (rare).

### iOS: Photo library three-key requirement

**Required keys** in `ios/Runner/Info.plist` for any flow that touches
`image_picker` or `gal`:

| Key | When iOS prompts | What happens if missing |
|-----|------------------|-------------------------|
| `NSPhotoLibraryUsageDescription` | Reading from Photos | App crashes with `TCC` violation |
| `NSCameraUsageDescription` | Taking a photo | `image_picker` returns null silently |
| `NSPhotoLibraryAddUsageDescription` | Saving to Photos via `gal` | App crashes on save |

**Common Mistake**: Adding the first two but forgetting the *Add* key. The
read/camera flow works in dev, then the save flow crashes the first time a
beta user exports an image.

**Required structure**:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Fl PiCraft needs access to your photo library to import images for editing.</string>
<key>NSCameraUsageDescription</key>
<string>Fl PiCraft uses the camera to capture photos for editing.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Fl PiCraft saves edited images to your photo library.</string>
```

**Validation**: All three keys present, each with a descriptive string that
mentions the app name and purpose (Apple App Store reviewers reject vague
copy like "We need access to your photos").

### macOS: Edit BOTH entitlements files

**Critical Gotcha**: macOS sandbox entitlements live in two files —
`macos/Runner/DebugProfile.entitlements` AND
`macos/Runner/Release.entitlements`. Adding to only one breaks the other
build configuration.

**Required entitlements** for any flow that uses `file_picker`, `gal`, or
`share_plus`:

```xml
<!-- BOTH DebugProfile.entitlements AND Release.entitlements -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

**Common Mistake**: Editing only `DebugProfile.entitlements`. `flutter run`
on macOS works fine, then `flutter build macos --release` quietly fails to
write to disk and the user sees an empty save dialog.

**Validation**: After editing, diff the two `.entitlements` files — the keys
added for sandbox file access should be byte-identical between Debug and
Release.

### macOS: Deployment-target floor

**Required**: The project's macOS deployment target is **11.0** (Big Sur).
Some plugins ship with a hard minimum; the highest currently in our graph
is `gal` (≥ 11.0), so 11.0 is the floor we must keep until something forces
it higher.

**Files that MUST be edited together** when changing the floor:

| File | What to edit |
|------|--------------|
| `macos/Podfile` | `platform :osx, '11.0'` (top of file) |
| `macos/Runner.xcodeproj/project.pbxproj` | Every `MACOSX_DEPLOYMENT_TARGET = ...;` (Debug + Release + Profile, both Runner-target and project-level — usually 3+ occurrences) |
| `macos/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion` key, **only if the file exists** (modern Flutter macOS templates don't ship it; the iOS template does) |

Use `grep` first to enumerate every spot before editing:

```bash
grep -RIn "MACOSX_DEPLOYMENT_TARGET" macos/
grep -RIn "platform :osx" macos/
grep -RIn "MinimumOSVersion" macos/
```

**Common Mistake**: Editing only `macos/Podfile` and leaving
`project.pbxproj` at `10.15`. `pod install` then succeeds, but the build
still fails with `The plugin "gal" requires a higher minimum macOS
deployment version than your application is targeting` — Xcode's per-target
`MACOSX_DEPLOYMENT_TARGET` overrides the Podfile's `platform :osx` whenever
they differ. Both must move together.

**Validation**:
- `cd macos && pod install` succeeds (no "deployment version" error).
- All three `MACOSX_DEPLOYMENT_TARGET` occurrences in `project.pbxproj`
  match the Podfile value.
- `flutter build macos --debug` reaches link without the gal-deployment
  error.

### Desktop / Web: Verification only

| Platform | Manifest edits | Verification |
|----------|----------------|--------------|
| Windows | None | `flutter build windows` succeeds; `super_drag_and_drop` plugin appears in `windows/flutter/generated_plugins.cmake` |
| Linux | None | `flutter build linux` succeeds; same plugin check |
| Web | Optional Inter font preload in `web/index.html` | `flutter build web` succeeds; `image_picker` web fallback works |

---

## Validation & Error Matrix

| Misstep | Symptom | Fix |
|---------|---------|-----|
| `READ_EXTERNAL_STORAGE` unconstrained | Play Store warns; Android 13 grants wrong scope | Add `android:maxSdkVersion="32"` |
| Missing `NSPhotoLibraryAddUsageDescription` | App crashes on first save in TestFlight | Add the third Photo Library key |
| Entitlement only in `DebugProfile.entitlements` | Release build's save dialog returns nothing | Mirror the entry in `Release.entitlements` |
| `riverpod_annotation` in `dev_dependencies:` | "Package not found" in release build | Move to `dependencies:` |
| Unconstrained Riverpod 3.x upgrade | Runtime "type X is not a subtype of Y" from any provider | Pin back to `^2.6.x` |
| Hand-pinned `targetSdk = 34` | Flutter SDK bump silently regresses to 34, blocking new APIs | Restore `flutter.targetSdkVersion` |
| `MACOSX_DEPLOYMENT_TARGET` lower than a plugin's floor (e.g. `gal` ≥ 11.0) | `pod install` or `flutter build macos` errors with `The plugin "X" requires a higher minimum macOS deployment version` | Bump Podfile **and** every `MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj` to the plugin floor |

---

## Tests Required

Platform-config changes are usually verified manually, but include these
checks before merging anything that touches a manifest:

1. **`flutter pub get`** — must resolve cleanly with the locked dependency graph.
2. **`flutter analyze`** — must report zero issues.
3. **`dart format --set-exit-if-changed .`** — must report zero unformatted files.
4. **Smoke test on each affected platform**:
   - iOS simulator: import flow prompts permission, save flow prompts add permission.
   - Android emulator (API 33 + API 30): import flow uses the right permission per OS version.
   - macOS release build: file save dialog actually writes.

A future task should add CI matrix builds; for now, run the three pubspec /
analyze / format checks before every commit.

---

## Wrong vs Correct: Adding a new image-saving plugin

Suppose you want to add a watermark plugin that writes its own files to the
gallery.

### Wrong

```yaml
# pubspec.yaml — no comment, no version pin policy
dependencies:
  watermark_plugin: any
```
```xml
<!-- Add only to AndroidManifest.xml; ignore iOS and macOS -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

Outcome: Play Store warns about deprecated `WRITE_EXTERNAL_STORAGE`,
iOS app crashes on first save, macOS Release build silently fails.

### Correct

```yaml
# pubspec.yaml
dependencies:
  # Watermark export — chosen because it streams via path_provider tmp dir
  # rather than copying to memory. Lock to ^x.y.z; see directory-structure.md.
  watermark_plugin: ^1.2.3
```

Then verify whether the plugin needs **any** of:
- `NSPhotoLibraryAddUsageDescription` (already present from project-init — no edit needed).
- macOS `com.apple.security.files.user-selected.read-write` (already present).
- Android — only `READ_MEDIA_IMAGES` if it reads existing photos (already present); writing to gallery on Android 10+ uses scoped storage and needs no permission.

Run `flutter pub get && flutter analyze && dart format .` and a smoke test on
each platform before opening a PR.

---

## References

- `pubspec.yaml` — current dependency list with inline rationale comments
- `android/app/src/main/AndroidManifest.xml` — permission template
- `ios/Runner/Info.plist` — usage description template
- `macos/Runner/DebugProfile.entitlements` + `macos/Runner/Release.entitlements`
- CLAUDE.md → "Target Architecture" — high-level tech stack constraints
- `.trellis/tasks/05-08-project-init/prd.md` — original requirement source
