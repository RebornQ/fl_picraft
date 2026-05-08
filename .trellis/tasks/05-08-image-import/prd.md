# Image Import Module

## Goal

Provide a unified image import surface usable by both Long Stitch and Grid Split features. Four sources must be supported with platform-aware fallbacks; output is normalized to a single in-memory model so downstream features don't care where the bytes came from.

## Requirements

### Import sources

| Source | Platforms | Library |
|--------|-----------|---------|
| Gallery (multi-select) | All | `image_picker` (mobile/web) + `file_picker` (desktop) |
| Camera capture | iOS / Android | `image_picker` |
| Clipboard paste | All | `super_clipboard` or `pasteboard` |
| Drag-drop file | macOS / Windows / Linux / Web | `super_drag_and_drop` or `desktop_drop` |

### Internal model

```dart
class ImportedImage {
  final String? sourcePath;     // null for clipboard / web blobs
  final Uint8List bytes;        // always populated for processing
  final int width;
  final int height;
  final String mimeType;
  final DateTime importedAt;
}
```

### Constraints

- Hard cap: 20 images per import session (PRD §5.2)
- Decode happens off the UI isolate for files >2MB
- Reject non-image MIME types with a snackbar

## Acceptance Criteria

- [ ] Gallery multi-select returns ≤20 `ImportedImage` objects
- [ ] Camera capture works on iOS 12+ and Android 6+
- [ ] Clipboard paste handles PNG and JPEG
- [ ] Drag-drop accepts files on macOS / Windows / Linux / Web
- [ ] Camera button hidden on desktop/web (graceful platform check)
- [ ] All paths produce identical `ImportedImage` shape

## Definition of Done

- Unit tests for the import normalizer
- Integration test for at least one source per platform CI matrix
- `flutter analyze` clean
- Riverpod provider exposes `AsyncValue<List<ImportedImage>>`

## Out of Scope

- Image editing (rotate / crop) before stitching — features handle their own crops
- Cloud import (Google Photos / iCloud) — not in MVP

## Dependencies

- Requires: `05-08-foundation` (Riverpod + DI must exist)
- Blocks: `05-08-long-stitch`, `05-08-grid-split`

## References

- Total PRD §5.1 Image Import
- UI: image picker triggered from Home cards (`_1_首页/code.html` lines 117–134) and from feature edit screens
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/directory-structure.md`
