# Vertical & Horizontal Stitch

> Subtask of [`05-08-long-stitch`](../05-08-long-stitch/prd.md)

## Goal

Implement the two non-overlay stitch modes: vertical (equal width) and horizontal (equal height). Includes spacing, border, and corner radius parameters. This is the "easy" mode pair — pure concatenation, no layering.

## Algorithm

### Vertical mode

1. `targetWidth = images.first.width` (or user-overridden value)
2. For each image: scale to `targetWidth` preserving aspect ratio → `scaledHeight = origHeight * targetWidth / origWidth`
3. `canvasHeight = sum(scaledHeights) + spacing * (n - 1) + 2 * borderWidth`
4. Paint each scaled image into the canvas at `y = cumulative + borderWidth`
5. Apply outer border + outer radius if configured

### Horizontal mode

Same but transposed: target height = first image's height, lay images side by side.

## UI controls

UI ref: `_2_长图拼接/code.html`

- **Mode segmented control** (lines 200–203): "竖向" / "横向" with primary fill on active
- **Subtitle toggle** (lines 205–211): visible but **off** in this mode (delegates to movie-subtitle subtask)
- **Parameter sheet** (sticky bottom): spacing slider 0–50px, border width 0–10px + color picker, radius 0–48px

## Riverpod state

```dart
@riverpod
class StitchEditor extends _$StitchEditor {
  @override
  StitchEditorState build() => StitchEditorState.initial();

  void setMode(StitchMode mode) { ... }
  void setSpacing(double px) { ... }
  void reorder(int from, int to) { ... }
  Future<Uint8List> render() async { ... }  // off-isolate
}
```

State is the single source of truth for: image list order, mode, spacing, border, radius. Subtitle-mode-only fields live in the same state class but are unused in this subtask.

## Performance

- Renders happen via `compute()` (isolate) for ≥5 images or any image >2MP
- Preview uses a downscaled cached snapshot to keep slider response under 100ms
- Final export uses full resolution

## Acceptance Criteria

- [ ] Vertical stitch with 3 different-aspect images produces a single image at first image's width
- [ ] Horizontal stitch with 3 different-aspect images produces a single image at first image's height
- [ ] Spacing slider visibly changes gap in preview
- [ ] Border width + color render around the outer rect
- [ ] Outer radius clips the result correctly
- [ ] 20 images vertical stitch completes in <5s on a mid-tier device (perf budget)

## Definition of Done

- Unit tests for the canvas-size and per-image-rect math
- Widget test for the mode segmented control
- `flutter analyze` clean

## Out of Scope

- Movie subtitle mode (separate subtask)
- Per-image cropping / rotation
- Background color other than white (post-MVP)

## Dependencies

- Requires: `05-08-image-import`, `05-08-base-architecture`
- Sibling: `05-08-movie-subtitle` (shares the editor state class)

## References

- Total PRD §3.1 竖向拼图, §3.2 横向拼图, §5.3 输出调整
- UI: `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_2_长图拼接/code.html`
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/type-safety.md`
