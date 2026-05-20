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
- Add, rename, or remove a native source file under `macos/Runner/`,
  `windows/runner/`, or `linux/runner/`
- Implement custom `NSWindow` / `Win32Window` / GTK window lifecycle logic
  in a platform runner (e.g. `MainFlutterWindow.swift`, `win32_window.cpp`,
  `my_application.cc`)

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
| File pick + desktop save dialog | `file_picker` (desktop only for save) | `file_selector` | `file_picker` exposes `saveFile()` on macOS / Windows / Linux. **Web is NOT supported** — see "Web blob download" below |
| Web file download | `package:web` Blob + anchor (conditional import) | `file_picker.saveFile()` on web | `file_picker` 8.3.x lacks a web `saveFile` impl — calling it on web silently returns null. Use a `package:web` adapter behind a conditional import. |
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

### Android: `INTERNET` belongs in `main/` manifest, not just `debug/` + `profile/`

> Captured from `05-19-fix-google-fonts-macos-network-client`.

**Critical Gotcha**: Flutter's Android template **auto-injects**
`<uses-permission android:name="android.permission.INTERNET" />` into
`android/app/src/debug/AndroidManifest.xml` and
`android/app/src/profile/AndroidManifest.xml` (so hot-reload, observatory,
and DDS work). It does **NOT** inject it into
`android/app/src/main/AndroidManifest.xml`.

**Why this is dangerous**: Manifest merging picks the build-variant flavor
that matches the active build type. `debug` and `profile` get their own
manifest merged in; **release** builds merge `main/` **only**. So:

| Build type | Manifest sources | `INTERNET` present? |
|---|---|---|
| debug | `main/` + `debug/` | ✅ (from debug/) |
| profile | `main/` + `profile/` | ✅ (from profile/) |
| **release** | **`main/` only** | **❌** if `main/` doesn't declare it |

Any package that does runtime network fetches (`google_fonts`,
`NetworkImage`, `dio`, `http`, analytics SDKs, remote config) **silently
works in debug** and **silently fails in a release apk** — there's no
`flutter analyze` warning, no compile error, no log on debug. The bug
surfaces only after the release apk is on a real device or in the Play
Store track.

**Required**: If the app does **any** outbound HTTPS at runtime, declare
`INTERNET` in `main/AndroidManifest.xml`:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
```

**Common Mistake**: Testing only with `flutter run` (debug variant) and
assuming network access works in production. Always run at least one
`flutter build apk --release` install on a device — or grep `main/` —
before shipping anything that does network I/O.

**Validation**:
- `grep -l "android.permission.INTERNET" android/app/src/main/AndroidManifest.xml`
  returns the file.
- After `flutter build apk --release` install, the network-dependent feature
  (e.g. font fetch) succeeds on first launch with connectivity.

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

### `gal`: Album-name and filename conventions

Two conventions when calling `gal.putImageBytes(...)`:

1. **Empty-string album ≠ null album**. Passing `album: ''` creates a real
   album with an empty name in Photos / Gallery. Always normalize empty
   strings to `null` before the call:
   ```dart
   final normalizedAlbum =
       (album == null || album.isEmpty) ? null : album;
   await Gal.putImageBytes(bytes, album: normalizedAlbum, name: filename);
   ```
2. **Strip the file extension from `name`**. `gal` infers the format from
   the bytes and appends its own extension; passing `name: 'foo.jpg'`
   produces `foo.jpg.jpg` on Android. Pass the base name only:
   ```dart
   final base = filename.replaceAll(RegExp(r'\.(png|jpg|jpeg)$'), '');
   await Gal.putImageBytes(bytes, album: normalizedAlbum, name: base);
   ```

**Why it matters**: The first creates user-visible junk in Photos; the
second produces double-extension filenames that show up in the file picker
the next time the user imports.

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

### macOS: Runtime network fetch requires `network.client` entitlement

> Captured from `05-19-fix-google-fonts-macos-network-client`.

**Critical Gotcha**: The macOS sandbox blocks *outbound* network connections
by default. `com.apple.security.network.server` (often pre-seeded by the
Flutter template in `DebugProfile.entitlements`) only allows *inbound*
sockets — it does **NOT** authorize a Dart `HttpClient` / `package:http` /
`dio` / `NetworkImage` / `google_fonts` request from ever leaving the
sandbox.

**Symptom**: An outbound HTTPS call from any Dart isolate dies with
`SocketException: Connection failed (OS Error: Operation not permitted,
errno = 1)`. The error is **not** wrapped by anything sandbox-shaped — it
looks like a network failure, not a permission failure, which makes it
easy to misdiagnose.

**Required entitlement** (BOTH Debug and Release):

```xml
<!-- BOTH DebugProfile.entitlements AND Release.entitlements -->
<key>com.apple.security.network.client</key>
<true/>
```

Triggering packages currently in the graph (or likely to land soon):

| Package | Why it needs outbound network |
|---|---|
| `google_fonts` | Fetches `Inter-*.ttf` from `fonts.gstatic.com` at first use, caches via `path_provider` |
| `NetworkImage` (in `flutter/material`) | Any remote `Image.network(...)` URL |
| `dio` / `http` (when introduced) | API calls |
| `share_plus` (rare) | Some share targets fetch metadata over the network |

**Common Mistake**: Adding `network.server` thinking it covers all
networking. It doesn't — `server` and `client` are independent capabilities
in the macOS sandbox model.

**Failure mode (acceptable degradation)**: Even with `network.client`
granted, the **first** cold start with no network connectivity will fail to
fetch fonts. `google_fonts` then **falls back to the platform's default
font face** — the app does not crash and continues to render text. This is
an accepted degradation; subsequent launches hit the on-disk cache populated
by the first successful fetch. **Do not** treat fallback-during-offline as
a bug.

**Future-note (App Store / Mac App Store submission)**: Sandboxed builds
that ship with `network.client` enabled trigger a privacy-questionnaire
prompt at submission time — you'll need to write a one-line "App reaches
out to fonts.gstatic.com (or whichever endpoints apply) to download the
Inter typeface and cache it locally" justification. Out of scope for any
current task; revisit when packaging for store distribution.

**Validation**:
- `grep "network.client" macos/Runner/*.entitlements` returns hits in
  **both** `DebugProfile.entitlements` and `Release.entitlements`.
- After `flutter run -d macos`, the console no longer shows
  `Failed to load font with url https://fonts.gstatic.com/...`.

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

### macOS: `NSWindow.setFrameAutosaveName` MUST come after `setFrame`

> Captured from `05-20-macos-window-strategy` (Subtask 2 of
> `05-20-desktop-window-mgmt-and-menu`).

**Critical Gotcha**: When using `NSWindow.setFrameAutosaveName(_:)` for
window-frame persistence, AppKit reads `UserDefaults["NSWindow Frame <name>"]`
at the **exact moment** that call runs:

- If a saved value exists → AppKit immediately overrides the current frame
  with the saved value (= restore behavior).
- If no saved value exists → AppKit leaves the current frame untouched
  (= first-launch behavior).

This means `setFrame(default, display: true)` MUST precede
`setFrameAutosaveName(name)` inside `awakeFromNib`. Reversing the order
silently breaks both intended behaviors — there is no compiler warning, no
runtime exception, and `flutter analyze` cannot catch it.

**Wrong** (first launch ignores the computed default; subsequent launches
never visibly restore user resizes):

```swift
override func awakeFromNib() {
  // ...
  _ = self.setFrameAutosaveName("fl_picraft.main")   // ← too early
  self.setFrame(myDefault, display: true)            // overrides anything
                                                     // autosave restored
}
```

On first launch the explicit `setFrame` wins over the xib frame, fine in
isolation. But on subsequent launches the explicit `setFrame` ALSO wins
over the restored frame — user resizes never come back.

**Correct** (first launch = default; subsequent = restore):

```swift
override func awakeFromNib() {
  let flutterViewController = FlutterViewController()
  self.contentViewController = flutterViewController

  // 1. Min size first so any subsequent setter respects it. Use
  //    `contentMinSize` (excludes title bar) so 1280×800 reads as
  //    "1280×800 usable canvas" — Apple docs say contentMinSize takes
  //    precedence over minSize.
  self.contentMinSize = NSSize(width: 1280, height: 800)

  // 2. Compute the default frame (e.g. 80% × visibleFrame, centered)
  //    and set it via setFrame(_:display:) — the one setter explicitly
  //    documented as NOT clamped by minSize, so explicit values land
  //    untouched. visibleFrame already excludes dock / menu bar / notch.
  if let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first {
    let v = screen.visibleFrame
    let w = max(floor(v.width  * 0.80), 1280)
    let h = max(floor(v.height * 0.80), 800)
    let x = v.minX + (v.width  - w) / 2
    let y = v.minY + (v.height - h) / 2
    self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
  }

  // 3. Autosave name LAST. AppKit either keeps our default (no saved
  //    value yet = first launch) or overrides it with the saved frame
  //    (subsequent launches). Multi-screen unplug is handled by AppKit's
  //    built-in constrainFrameRect:to: at restore time — no manual
  //    "is-rect-visible" guard required.
  _ = self.setFrameAutosaveName("fl_picraft.main")

  RegisterGeneratedPlugins(registry: flutterViewController)

  // (… other awakeFromNib work …)

  super.awakeFromNib()
}
```

**Why it's easy to break**: A maintainer alphabetizing setters or grouping
"setup" calls at the top of `awakeFromNib` would naturally put
`setFrameAutosaveName` before `setFrame`. The Apple docs describe the
restore semantics but do not call out the ordering hazard explicitly.

**Validation** (manual smoke — automatable parts already covered by
`flutter analyze` + `flutter build macos`):

- `defaults delete <bundle-id>` (or `rm ~/Library/Preferences/<bundle-id>.plist`).
- Launch → window appears at default (e.g. 80% centered on primary
  monitor's `visibleFrame`).
- Resize → quit → relaunch → window appears at resized position (restore
  worked).
- If both behaviors don't hold simultaneously, the order is reversed.

**Related**:
- `NSWindow.contentMinSize` vs `minSize` — content-area vs frame-including-titlebar (use `contentMinSize` for "minimum usable canvas" semantics).
- `setFrame(_:display:)` vs `setFrame(_:display:animate:)` — only the
  no-animate variant is documented as NOT clamped by `minSize`; use it
  when restoring or setting explicit defaults.

### Desktop runners: register new native source files with the build system

> Captured from `05-20-macos-settings-menu-bridge` (Subtask 1 of
> `05-20-desktop-window-mgmt-and-menu`).

**Critical Gotcha**: Dropping a new native source file on disk under
`macos/Runner/`, `windows/runner/`, or `linux/runner/` is **not** enough.
Each platform's build system maintains its own source-file index that does
NOT auto-discover newly-created files. The Swift / C++ / C compiler fails
at build time, and `flutter analyze` cannot catch it because analyze only
walks the Dart source graph.

**Required**: When adding a new native source file, edit the corresponding
platform's project / build file in the same change.

| Platform | File to edit | What to add |
|----------|--------------|-------------|
| **macOS** | `macos/Runner.xcodeproj/project.pbxproj` | 4 entries — see "macOS: 4-section pbxproj edit" below |
| **Windows** | `windows/runner/CMakeLists.txt` | Filename appended to `RUNNER_SOURCES` list |
| **Linux** | `linux/runner/CMakeLists.txt` | Filename appended to the executable target's source list |

#### macOS: 4-section pbxproj edit

Adding e.g. `macos/Runner/Foo.swift` requires generating two fresh 24-char
hex UUIDs (uppercase, matching the existing convention) and editing **all
four** of these `Runner.xcodeproj/project.pbxproj` sections:

```
PBXBuildFile         — build-instance UUID, references the file UUID
PBXFileReference     — file UUID, points at physical path "Foo.swift"
PBXGroup             — Runner group's children list (sourceTree visibility)
PBXSourcesBuildPhase — Runner target's compile-sources list
```

**Generate UUIDs** that don't collide with existing IDs:

```bash
python3 -c "import secrets; print(secrets.token_hex(12).upper())"
# run twice — once for the BuildFile UUID, once for the FileReference UUID
```

**Mirror an existing entry**: grep the pbxproj for `AppDelegate.swift` and
you will see it referenced exactly 4 times (once per section). Add the same
4 entries for the new file with the two new UUIDs:

```diff
 /* Begin PBXBuildFile section */
 ...
 33CC10F12044A3C60003C045 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 33CC10F02044A3C60003C045 /* AppDelegate.swift */; };
+<NEW_BUILD_UUID> /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = <NEW_REF_UUID> /* Foo.swift */; };
 ...
 /* End PBXBuildFile section */

 /* Begin PBXFileReference section */
 ...
 33CC10F02044A3C60003C045 /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
+<NEW_REF_UUID> /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };
 ...
 /* End PBXFileReference section */

 /* Begin PBXGroup section */ ... Runner group children ...
   33CC10F02044A3C60003C045 /* AppDelegate.swift */,
+  <NEW_REF_UUID> /* Foo.swift */,
 ...

 /* Begin PBXSourcesBuildPhase section */ ... Runner target Sources ...
   33CC10F12044A3C60003C045 /* AppDelegate.swift in Sources */,
+  <NEW_BUILD_UUID> /* Foo.swift in Sources */,
 ...
```

**Sanity-check before committing the pbxproj edit**:

- The new BUILD UUID appears exactly **2** times (PBXBuildFile + PBXSourcesBuildPhase).
- The new REF UUID appears exactly **3** times (PBXBuildFile.fileRef + PBXFileReference + PBXGroup children).
- The literal filename (`Foo.swift`) appears exactly **4** times — one Xcode comment per section.

#### Windows: append to `RUNNER_SOURCES`

```cmake
# windows/runner/CMakeLists.txt
set(RUNNER_SOURCES
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "foo.cpp"   # ← new
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
```

Header files (`foo.h`) do **not** belong in `RUNNER_SOURCES` — they reach
the compiler via `#include` from the listed translation units. Only `.cpp`
files belong here. If the new code uses a system library outside the
default link set (e.g. `shcore.lib`, `shell32.lib`), also append it to the
existing `target_link_libraries(${BINARY_NAME} PRIVATE ...)` call.

#### Linux: append to the executable's source list

```cmake
# linux/runner/CMakeLists.txt — inside add_executable(...)
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "foo.cc"   # ← new
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
```

GTK / GLib / GDK are already linked via `PkgConfig::GTK` — no new
`pkg_check_modules` is needed unless the code uses a library outside the
GTK 3 + GLib graph (e.g. `pkg-config --libs xkbcommon`).

#### Symptoms when this is forgotten

| Platform | Build command | What you see |
|---|---|---|
| macOS | `flutter build macos --debug` | Swift frontend: `error: cannot find type 'Foo' in scope` at the call site (NOT the new file itself — Xcode never even tried to compile it) |
| Windows | `flutter build windows --debug` | MSVC: `LNK2019: unresolved external symbol "...Foo..."` or `error C2065: 'Foo': undeclared identifier` |
| Linux | `flutter build linux --debug` | ld: `undefined reference to '...foo...'` |

`flutter analyze` is silent in all three cases because it only inspects
Dart sources. **Therefore**: always run a `flutter build <platform>` for
the platform whose native runner you touched, before declaring the task
done. CI should also cover this — until CI matrix builds exist, the
implementing engineer is the last line of defence.

**Common Mistake**: An implementing agent uses the `Write` tool to create
the new file, sees `flutter analyze` clean, runs the Dart-side tests
(green), and ships the change. The first user to actually run the desktop
build hits the compile error days later. **Always** add a `flutter build
<platform>` step to the verification list when the change touches any
runner directory.

**Validation**:

- macOS: `flutter build macos --debug` finishes with "✓ Built …app". After
  the fact, `grep -c "Foo.swift" macos/Runner.xcodeproj/project.pbxproj`
  returns `4` (one Xcode comment per section).
- Windows: `flutter build windows --debug` finishes; `grep "foo.cpp"
  windows/runner/CMakeLists.txt` returns one hit inside the
  `RUNNER_SOURCES` list.
- Linux: `flutter build linux --debug` finishes; `grep "foo.cc"
  linux/runner/CMakeLists.txt` returns one hit inside the `add_executable`
  argument list.

### Desktop / Web: Verification only

| Platform | Manifest edits | Verification |
|----------|----------------|--------------|
| Windows | None for manifests; for new native sources see "Desktop runners" above | `flutter build windows` succeeds; `super_drag_and_drop` plugin appears in `windows/flutter/generated_plugins.cmake` |
| Linux | None for manifests; for new native sources see "Desktop runners" above | `flutter build linux` succeeds; same plugin check |
| Web | Optional Inter font preload in `web/index.html` | `flutter build web` succeeds; `image_picker` web fallback works |

### Web: File save uses `package:web` Blob — NOT `file_picker.saveFile()`

**Required**: To trigger a browser download of in-memory bytes on the web
platform, use a `package:web` adapter (Blob + object URL + `<a>.click()`)
behind a **conditional import**. Do **not** call `file_picker.saveFile()` on
web — its web implementation does not exist as of 8.3.x and silently returns
`null`, surfacing to the user as "save did nothing".

**Required dependency** (declared in `pubspec.yaml`):
```yaml
dependencies:
  web: ^1.1.0   # only needed because data/datasources/*_web.dart imports it directly
```

**Required structure**: conditional import so non-web builds get a stub
that throws `UnsupportedError`, while web builds get the real `package:web`
implementation. This keeps `dart:js_interop` / `package:web` out of every
non-web compile graph.

```dart
// data/datasources/web_blob_download_datasource.dart   ← public entry
import 'web_blob_download_stub.dart'
    if (dart.library.js_interop) 'web_blob_download_web.dart';

// data/datasources/web_blob_download_stub.dart         ← non-web build
Future<void> downloadBlob(Uint8List bytes, String filename, String mime) {
  throw UnsupportedError('Web blob download unavailable on this platform.');
}

// data/datasources/web_blob_download_web.dart          ← web build only
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> downloadBlob(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);   // ← MUST revoke or the blob leaks
}
```

**Common Mistake**: Forgetting `URL.revokeObjectURL(url)` after `.click()`.
The browser holds the blob in memory until either the URL is revoked or the
tab is closed. Large exports (e.g. 20-image grid) compound quickly.

**Validation**:
- `grep -RIn "file_picker" lib/features/<feature>/data/datasources/` shows
  no `saveFile()` call (file_picker is fine for desktop save dialog, but
  the web path must NOT route through it).
- `URL.revokeObjectURL` is paired with every `URL.createObjectURL` in any
  `*_web.dart` datasource.
- The non-web stub throws `UnsupportedError` — never returns a fake
  success.

---

## Validation & Error Matrix

| Misstep | Symptom | Fix |
|---------|---------|-----|
| `READ_EXTERNAL_STORAGE` unconstrained | Play Store warns; Android 13 grants wrong scope | Add `android:maxSdkVersion="32"` |
| Missing `NSPhotoLibraryAddUsageDescription` | App crashes on first save in TestFlight | Add the third Photo Library key |
| Entitlement only in `DebugProfile.entitlements` | Release build's save dialog returns nothing | Mirror the entry in `Release.entitlements` |
| Missing `com.apple.security.network.client` in macOS entitlements | `google_fonts` / `NetworkImage` / `dio` errors with `SocketException: Operation not permitted, errno = 1`; looks like a network failure, not a permission failure | Add `network.client` to BOTH `DebugProfile.entitlements` and `Release.entitlements` (see "macOS: Runtime network fetch requires `network.client`") |
| `INTERNET` only in Flutter's auto-injected `debug/` + `profile/` manifests | Network fetches work in `flutter run`, **silently fail** in `flutter build apk --release` (no debug log, no analyzer warning) | Declare `INTERNET` in `android/app/src/main/AndroidManifest.xml` |
| `riverpod_annotation` in `dev_dependencies:` | "Package not found" in release build | Move to `dependencies:` |
| Unconstrained Riverpod 3.x upgrade | Runtime "type X is not a subtype of Y" from any provider | Pin back to `^2.6.x` |
| Hand-pinned `targetSdk = 34` | Flutter SDK bump silently regresses to 34, blocking new APIs | Restore `flutter.targetSdkVersion` |
| `MACOSX_DEPLOYMENT_TARGET` lower than a plugin's floor (e.g. `gal` ≥ 11.0) | `pod install` or `flutter build macos` errors with `The plugin "X" requires a higher minimum macOS deployment version` | Bump Podfile **and** every `MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj` to the plugin floor |
| New native source file dropped on disk without registering it in `Runner.xcodeproj/project.pbxproj` (macOS) / `windows/runner/CMakeLists.txt` (Windows) / `linux/runner/CMakeLists.txt` (Linux) | macOS: Swift compile error `cannot find type 'X' in scope` at the call site (the new file itself was never compiled). Windows: MSVC `LNK2019: unresolved external symbol` or `C2065: undeclared identifier`. Linux: ld `undefined reference`. **`flutter analyze` is silent** in all three cases because it only walks Dart. | Mirror an existing entry (e.g. `AppDelegate.swift`) in all 4 pbxproj sections with two fresh UUIDs; for Windows / Linux append the filename to `RUNNER_SOURCES` / `add_executable`. See "Desktop runners: register new native source files". Always run `flutter build <platform>` before declaring done. |
| `NSWindow.setFrameAutosaveName` called BEFORE `setFrame(default, display: true)` in `awakeFromNib` | First-launch window uses the xib frame (NOT the computed 80% default); user resizes never visibly restore on subsequent launches. **No compile warning, no runtime exception** — `flutter analyze` cannot catch it. | Reorder: `contentMinSize` → compute and `setFrame(default, display: true)` → `setFrameAutosaveName(name)` **LAST**. See "macOS: `NSWindow.setFrameAutosaveName` MUST come after `setFrame`". Smoke-verify by `defaults delete <bundle-id>` + launch + resize + relaunch. |
| `file_picker.saveFile()` called on web | Returns `null` silently; user sees "save did nothing" with no error | Route web through a `package:web` Blob adapter (conditional import) |
| `URL.createObjectURL` without matching `revokeObjectURL` | Blob bytes leak in browser memory until tab closes; large exports compound | Revoke immediately after `<a>.click()` |
| `gal.putImageBytes(..., album: '')` | Creates a real album named "" in Photos / Gallery | Normalize empty strings to `null` before the call |
| `gal.putImageBytes(..., name: 'foo.jpg')` | Saves file as `foo.jpg.jpg` on Android (gal appends extension itself) | Strip the file extension before passing `name` |

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
