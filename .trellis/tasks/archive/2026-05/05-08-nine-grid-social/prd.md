# Nine Grid Social Mode

> Subtask of [`05-08-grid-split`](../05-08-grid-split/prd.md)

## Goal

Implement the social-media-tailored 3x3 grid mode: split the source image into 9 squares, optionally replace the center cell (5th, index 4) with a different image (avatar / brand badge), and let users scale + pan the replacement image to fit the square cell.

## Algorithm

1. Crop source to square (longest side = min(srcW, srcH); center crop)
2. Split into 3x3 = 9 equal squares (reuse logic from `regular-grid` for type `3x3`)
3. If center replacement enabled:
   - Take user-selected `centerImage`
   - Apply transform `Matrix4(scale, translation)` controlled by user
   - Composite centerImage over cell[4], clipped to cell bounds
4. Output 9 PNGs in row-major order (cell[0] through cell[8])

## UI surface

UI ref: `_3_宫格切图/code.html` lines 132–135 (interactive center cell):

```html
<div class="border-r border-b border-white/40 bg-black/20 backdrop-blur-sm
            flex flex-col items-center justify-center pointer-events-auto cursor-pointer
            hover:bg-black/30 transition-all">
  <span class="material-symbols-outlined text-white text-3xl">add_a_photo</span>
  <span class="text-white text-xs mt-2 font-medium">替换图片</span>
</div>
```

When the social mode toggle (lines 144–153) is **on**:

- 3x3 is locked (other grid types in the selector are dimmed)
- Center cell shows the "替换图片" CTA with `add_a_photo` icon
- Tapping center cell opens an `image-import` picker for a single image
- After replacement: pinch-to-zoom + pan gesture overlay appears on the center cell
- Scale range: 0.5x – 2x; pan constrained so the cell never shows transparent area

## State

Extends `GridEditor` notifier:

```dart
final bool socialMode;            // toggle
final ImportedImage? centerImage; // null until user picks
final double centerScale;         // 1.0
final Offset centerOffset;        // (0, 0) = centered
```

Render branching:

```dart
if (socialMode) {
  state = state.copyWith(gridType: GridType.x3_3); // lock
  final cells = baseGridSplit(...); // 9 cells from source
  if (centerImage != null) cells[4] = composeCenter(cells[4], centerImage, scale, offset);
  return cells;
}
```

## Edge cases

| Case | Behavior |
|------|----------|
| Toggle ON without picking center image | Center cell shows "替换图片" CTA; export still produces 9 cells (center is the original 5th piece) |
| Center image with wrong aspect | Allow scale > 1 to crop overflow; warn if too small |
| Scale at 0.5x exposes transparent area | Disallow — clamp scale lower bound to fit |
| User toggles social mode OFF | Keep 9 cells, restore original center, discard centerImage state |

## Acceptance Criteria

- [ ] Toggle ON locks grid type to 3x3
- [ ] Center cell becomes interactive (CTA + later picker)
- [ ] Picker invokes `05-08-image-import` for a single-image selection
- [ ] Pinch + drag adjusts center image without leaving cell bounds
- [ ] Export produces 9 PNGs in order; cell[4] is the composed result when toggle is on
- [ ] Toggling OFF restores normal 3x3 split

## Definition of Done

- Unit tests for `composeCenter` clamping math
- Gesture detector test for scale/offset bounds
- Visual regression: capture cell[4] at default and at scale=1.5

## Out of Scope

- Replacing other cells (only center)
- Image-watermark for the center image
- Auto-detection of "good" center crops

## Dependencies

- Requires: `05-08-regular-grid` (reuses 3x3 split logic), `05-08-image-import`

## References

- Total PRD §4.2 九宫格朋友圈切图
- UI: `_3_宫格切图/code.html`
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/component-guidelines.md`
