# Multi-Platform Export

> Subtask of [`05-08-export-watermark`](../05-08-export-watermark/prd.md)

## Goal

Take the final composite (stitched image OR list of grid cells) and persist it to the right destination on each platform: Photos library on mobile, save dialog on desktop, blob download on web. Format selection (PNG / JPG) and quality control happen here.

## UI surface

UI ref: `_4_导出页面/code.html`

- **Format toggle** (lines 145–156): JPG (active) / PNG segmented buttons; PNG hides the quality slider
- **Quality slider** (lines 157–167): range 1–100, label endpoints "最小体积" / "最高质量", default 85%
- **Save button** (line 207): full-width primary CTA "保存至相册"; on desktop reads "保存到本地"
- **Disclaimer** (lines 210–215): privacy note about no upload

## Save targets per platform

| Platform | Target | Library | Notes |
|----------|--------|---------|-------|
| iOS | Photos library | `gal` or `image_gallery_saver_plus` | Album: "Fl PiCraft" if API allows |
| Android | Photos / DCIM | `gal` | Scoped storage on API 29+ |
| macOS | NSSavePanel via file_picker | `file_picker` | Default name: `flpicraft_<timestamp>.<ext>` |
| Windows | Save dialog | `file_picker` | Same naming |
| Linux | Save dialog | `file_picker` | Same naming |
| Web | Blob download | Built-in `web/url_launcher` or `dart:html` `AnchorElement` | Triggers browser download |

Platform check via `defaultTargetPlatform` and `kIsWeb`.

## Algorithm

```dart
Future<SaveResult> exportAndSave(ExportRequest req) async {
  // 1. Compose
  final composite = req.source is StitchSource
      ? await renderStitch(req.source)
      : await renderGridCells(req.source); // List<Uint8List>

  // 2. Apply watermark (delegates to 05-08-watermark)
  final watermarked = await applyWatermark(composite, req.watermark);

  // 3. Encode
  final bytes = req.format == ExportFormat.png
      ? encodePng(watermarked)
      : encodeJpg(watermarked, quality: req.quality);

  // 4. Persist
  return await saveToPlatform(bytes, suggestedName(req));
}
```

For grid cells: loop step 2–4 per cell, returning a list of save results (or zip them on web).

## Permissions

- iOS: relies on `NSPhotoLibraryAddUsageDescription` (added in `project-init`)
- Android: `WRITE_EXTERNAL_STORAGE` (≤28) or scoped storage MediaStore (29+)
- Desktop / Web: no special permissions; user picks file via dialog

## Acceptance Criteria

- [ ] PNG export is lossless (decode → re-encode → byte-equal)
- [ ] JPG export with quality=100 is visually indistinguishable; quality=20 is visibly lossy
- [ ] Saved file appears in the platform Photos app on iOS / Android
- [ ] macOS / Windows / Linux save dialog prompts for filename + location
- [ ] Web save triggers a browser download with the correct filename
- [ ] Save success surfaces a toast/snackbar with location info
- [ ] Save failure surfaces a non-fatal error toast (no crash)

## Definition of Done

- Unit tests for `suggestedName` and platform-routing
- Integration test: round-trip a small known image through PNG and JPG encoders
- Manual checklist: save once on each platform CI matrix

## Out of Scope

- Cloud save (Drive / iCloud)
- Custom album organization
- Burst export (single click → multiple sizes / formats)

## Dependencies

- Requires: `05-08-watermark` (called before encode)
- Consumes: stitch result from `05-08-long-stitch` and grid cells from `05-08-grid-split`

## References

- Total PRD §5.4 导出
- UI: `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`
- Spec: `.trellis/spec/frontend/quality-guidelines.md`, `.trellis/spec/frontend/type-safety.md`
