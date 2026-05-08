# Movie Subtitle Mode

> Subtask of [`05-08-long-stitch`](../05-08-long-stitch/prd.md)

## Goal

Implement the signature feature of Fl PiCraft: the "movie subtitle mode" (电影台词模式) that simulates Bilibili-style long screenshots where the first image renders fully and subsequent images contribute only their bottom subtitle band — letting users keep dialogue continuity without ballooning the total height.

## Algorithm (Total PRD §3.3)

```
let H_full = first image's height (after width-normalization to first image's width)
let H_band = subtitleHeight slider value (50–500 px, default 120)

canvasWidth  = first image's width  (all images scaled to this width)
canvasHeight = H_full + (n - 1) * H_band

paint(image[0]) at (0, 0)
for i in 1..n-1:
    crop bottom H_band of image[i] (after width-normalization)
    paint at (0, H_full + (i - 1) * H_band)
```

This is conceptually a layered overlay: each subsequent image's "picture area" is naturally hidden by the layout, with only the bottom band exposed.

## UI surface

UI ref: `_2_长图拼接/code.html` lines 170–225

- **Preview canvas** shows: full first frame with subtitle text, then 120px-high bands of subsequent frames each carrying their own subtitle (lines 174–192 simulate this)
- **仅保留字幕 toggle** (lines 205–211): when **off**, falls back to `vertical-horizontal` vertical mode; when **on**, this subtask's algorithm runs
- **字幕高度 slider** (lines 213–223): label `字幕高度`, value display `120 px`, range `min=50 max=500 value=120`

## State integration

Reuses the `StitchEditor` Riverpod notifier from the sibling subtask. Adds:

```dart
final bool subtitleOnlyMode;     // toggle state
final double subtitleBandHeight; // 50..500
```

Render dispatch:

```dart
if (mode == StitchMode.vertical && subtitleOnlyMode && images.length > 1) {
  return _renderMovieSubtitle(...);
}
return _renderPlainVertical(...);  // from sibling subtask
```

## Edge cases

| Case | Behavior |
|------|----------|
| Only 1 image | Subtitle mode degrades to plain vertical (no bands to add) |
| Image height < band height | Use min(imgHeight, bandHeight) for that image; warn via snackbar |
| User toggles mid-edit | Recompute preview without resetting image list |
| Horizontal mode active | Toggle is hidden (subtitle mode only applies vertically) |

## Acceptance Criteria

- [ ] Toggling 仅保留字幕 ON with ≥2 images shows: first full + bands of others
- [ ] Slider changes band height in preview within 100ms
- [ ] Final export height = `H_full + (n-1) * bandHeight`
- [ ] Toggle OFF behaves identically to plain vertical stitch
- [ ] When images < 2 or mode is horizontal, the slider+toggle are hidden or disabled
- [ ] No black bars or transparent gaps in the output

## Definition of Done

- Unit tests for the band-cropping math (image height < band, image height ≥ band)
- Widget test for the toggle + slider interaction
- Visual regression: render a 3-image example and snapshot-compare

## Out of Scope

- OCR / auto-detection of subtitle region (manual height adjustment is good enough for MVP)
- Variable band height per image
- Top-of-frame band (only bottom)

## Dependencies

- Requires: `05-08-vertical-horizontal` (shares the editor state)

## References

- Total PRD §3.3 电影台词模式 (visual diagram + parameter spec)
- UI: `_2_长图拼接/code.html`
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/quality-guidelines.md`
