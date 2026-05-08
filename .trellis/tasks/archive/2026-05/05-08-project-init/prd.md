# Project Init & Dependencies

> Subtask of [`05-08-foundation`](../05-08-foundation/prd.md)

## Goal

Bring the Flutter project's `pubspec.yaml`, lints, and platform manifests up to the level needed by every downstream feature. Pure plumbing — no `lib/` code beyond formatting fixes.

## Required dependencies

| Package | Version (latest stable target) | Why |
|---------|--------------------------------|-----|
| `flutter_riverpod` | ^2.5.x | State management (chosen in CLAUDE.md target architecture) |
| `riverpod_annotation` + `riverpod_generator` (dev) | ^2.x | Code-gen providers; optional but recommended |
| `go_router` | ^14.x | Declarative routing |
| `image` | ^4.x | Pure-Dart image processing for stitch/grid |
| `image_picker` | ^1.x | Gallery + camera on mobile/web |
| `file_picker` | ^8.x | Desktop / web fallback for picking images and save dialog |
| `super_drag_and_drop` | ^0.9.x | Cross-platform drag-drop (preferred over `desktop_drop`) |
| `super_clipboard` | ^0.9.x | Clipboard image paste on all platforms |
| `reorderables` | ^0.6.x | Drag-reorder for the image list |
| `path_provider` | ^2.x | Temp dirs for processing |
| `gal` (or `image_gallery_saver_plus`) | latest | Save to mobile gallery; `image_gallery_saver` is unmaintained |
| `share_plus` | ^10.x | Optional share sheet on save success |

> The exact version pinning is the implementer's call — match what's currently green on `pub.dev` and document choices in `pubspec.yaml` comments.

## Required dev dependencies

- `flutter_lints: ^6.0.0` (already present)
- `build_runner` (if using Riverpod code-gen)
- `mocktail` ^1.x for tests

## Platform manifests

| Platform | Edits needed |
|----------|--------------|
| iOS | `Info.plist`: `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription` |
| Android | `AndroidManifest.xml`: `READ_MEDIA_IMAGES` (API 33+), `READ_EXTERNAL_STORAGE` (≤32), `CAMERA`; `targetSdkVersion 34` |
| macOS | Entitlements: `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.downloads.read-write` |
| Windows / Linux | No special manifest beyond default; verify drag-drop works |
| Web | `web/index.html` Inter font preload optional |

## Acceptance Criteria

- [ ] `flutter pub get` succeeds with no version conflicts
- [ ] `flutter analyze` is clean
- [ ] `dart format .` applied
- [ ] App boots (still default Counter UI is fine — base-architecture replaces it) on iOS / Android / macOS / Web at minimum
- [ ] All required usage strings present in iOS `Info.plist`
- [ ] Permission strings present in Android `AndroidManifest.xml`

## Out of Scope

- Replacing `lib/main.dart` content (handled by `05-08-base-architecture`)
- Theme tokens / routing (handled by `05-08-base-architecture`)
- App icons / splash screens (post-MVP polish)

## Dependencies

- Blocks: `05-08-base-architecture` (which imports added packages)

## References

- CLAUDE.md → "Target Architecture" section
- Existing `pubspec.yaml`, `analysis_options.yaml`
- Spec: `.trellis/spec/frontend/quality-guidelines.md`
