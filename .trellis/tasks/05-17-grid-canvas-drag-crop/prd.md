# ST-C · Grid canvas drag-select crop (pan + zoom)

> Parent: [`05-17-grid-canvas-drag-overwrite`](../05-17-grid-canvas-drag-overwrite/prd.md)

## Goal

Let users **drag and pinch-zoom** the grid editor's canvas to explicitly pick which square region of a non-square source becomes the active grid source. Every export honors that selection.

This is the largest of the three subtasks: it extends state, gestures, the render request contract, the renderer's crop step, and the controls panel UI (reset button).

## Scope (touchpoints)

* **Domain** — `lib/features/grid/domain/`
  * `entities/grid_editor_state.dart` — add `sourceOffset: Offset`, `sourceScale: double` (and matching `copyWith` params + defaults).
  * `usecases/compute_source_crop.dart` (NEW) — pure-Dart conversion math.
  * `usecases/grid_render_request.dart` — extend fields + `fromState` wiring.
* **Data** — `lib/features/grid/data/`
  * `renderers/grid_image_renderer.dart` — generalize `_centerCropToSquare` into `_cropToSelectedSquare(offset, scale)`. Layout runs against the cropped square in both social and non-social modes.
* **Presentation** — `lib/features/grid/presentation/`
  * `providers/grid_editor_provider.dart` — add `setSourceOffset`, `setSourceScale`, `resetCrop`; wire reset into `addFromGallery(replace: true)` (works with ST-B).
  * `widgets/grid_preview_canvas.dart` — wrap `Stack` with a `RawGestureDetector` handling `onScaleStart/Update/End`; add local `_isGesturing` + `AnimatedOpacity` around the grid overlay; ensure `CenterCellOverlay` keeps gesture priority.
  * `widgets/grid_controls_panel.dart` — append "重置裁剪" button (only visible / enabled when crop is non-default).
* **Tests** — `test/features/grid/`
  * `domain/compute_source_crop_test.dart` (NEW) — unit tests for crop math + clamp.
  * `data/grid_image_renderer_social_test.dart` (MIGRATE) — migrate the `landscapeSource()` "preserves 200×100 cells" assertion to expect 100×100 squares (per D2 from parent PRD). Add a "drag changes the slice" test.
  * `presentation/grid_preview_canvas_drag_test.dart` (NEW) — widget test: scale gesture → controller state mutation.
  * `presentation/grid_editor_drag_isolation_test.dart` (NEW) — social mode: gesture inside center cell hits overlay, not canvas drag.

## Requirements

* **R-DRAG-01** Canvas accepts one-finger pan + two-finger pinch-zoom via a single `ScaleGestureRecognizer` stream.
* **R-DRAG-02** `sourceOffset` clamped so the canvas viewport never exposes area outside the source bounds; `sourceScale ∈ [1.0, 4.0]`.
* **R-DRAG-03** `sourceOffset` / `sourceScale` survive grid-type, spacing, corner-radius edits; reset on new import (in concert with ST-B) and on "重置裁剪" button.
* **R-DRAG-04** Grid overlay (cell strokes + corner radius) fades out within 100 ms on gesture start; fades back in within 150 ms after gesture end.
* **R-DRAG-05** In social mode, `CenterCellOverlay`'s gesture recognizer wins inside its hit bounds; the background canvas drag fires elsewhere.
* **R-RENDER-01** `GridRenderRequest` carries `sourceOffset` / `sourceScale`; renderer crops to the chosen square **first**, then runs `computeGridLayout`. Social mode becomes a degenerate path where the renderer no longer needs `_centerCropToSquare` (the new crop helper handles it).

## Acceptance Criteria

* [ ] **AC3** A 9:16 portrait screenshot can be panned vertically to pick which square region becomes the active source.
* [ ] **AC4** Pinch-zoom expands `sourceScale` up to 4.0 and never below 1.0; offset auto-clamps as scale changes.
* [ ] **AC5** Grid overlay hides during active gestures, re-appears within 150 ms after end.
* [ ] **AC6** Controls panel shows a "重置裁剪" button that restores defaults and re-shows the grid; button is hidden / disabled when crop is already default.
* [ ] **AC7** Changing grid type / spacing / corner radius does not alter `sourceOffset` / `sourceScale`.
* [ ] **AC8** Exported cells are square (1:1) and slice from the chosen square region — byte-match the on-screen preview at scale 1.0 and 2.0 (allowing 1 px integer rounding).
* [ ] **AC9** Social mode 3×3: tapping/dragging inside center cell drives `CenterCellOverlay`, not the canvas drag.
* [ ] **AC10** `flutter analyze`, `dart format .`, `flutter test` clean.

## Definition of Done

* New unit tests for `compute_source_crop.dart` cover: cover-fit (scale=1, offset=0.5/0.5), edge clamp, scale clamp, degenerate inputs.
* Migrated renderer tests reflect D2 (all cells square).
* New widget tests cover gesture → state and overlay-vs-canvas gesture isolation.
* Renderer integration test: 600×300 source + `sourceOffset=(0.0, 0.5)` (top-aligned) → 3×3 output is 9 squares carved from the source's left 300×300, NOT the centered crop.
* Brief addition to `state-management.md` if the viewport-state pattern is novel enough to warrant a spec entry (judgement during impl).

## Out of Scope

* Persisting crop across app restarts.
* Non-square crop aspect ratios.
* `sourceScale > 4.0`; rotation; mirror.
* Inertial / fling on gesture end.
* Replacing `CenterCellOverlay`'s gesture surface — only its priority is honored.

## Technical Notes

### State defaults

```dart
// grid_editor_state.dart
const kDefaultSourceOffset = Offset(0.5, 0.5);
const kDefaultSourceScale = 1.0;
const kMinSourceScale = 1.0;
const kMaxSourceScale = 4.0;
```

### Crop math contract

```dart
// compute_source_crop.dart
class SourceSquareRect {
  final int x;
  final int y;
  final int side;
}

SourceSquareRect? computeSourceSquareRect({
  required int sourceWidth,
  required int sourceHeight,
  required Offset offset,   // normalized [0,1]
  required double scale,    // [1.0, 4.0]
});

Offset clampSourceOffset({
  required Offset offset,
  required double scale,
  required double sourceAspect,  // w / h
});
```

### Gesture handling

Use `RawGestureDetector` with a single `ScaleGestureRecognizer` to avoid arena disambiguation with `CenterCellOverlay`'s own recognizer — the overlay sits as a `Positioned` child higher in the stack, so its `GestureDetector(behavior: HitTestBehavior.opaque)` will win inside its bounds without us needing custom arena work.

Pattern (mirrors `center_cell_overlay.dart:103–115`):
```dart
GestureDetector(
  behavior: HitTestBehavior.deferToChild,
  onScaleStart: (d) {
    _gestureStartOffset = state.sourceOffset;
    _gestureStartScale = state.sourceScale;
    _gestureStartFocal = d.localFocalPoint;
    setState(() => _isGesturing = true);
  },
  onScaleUpdate: (d) => _applyScaleUpdate(d),
  onScaleEnd: (_) => setState(() => _isGesturing = false),
  child: ..., // existing Stack
)
```

### Grid-overlay fade

```dart
AnimatedOpacity(
  opacity: _isGesturing ? 0.0 : 1.0,
  duration: const Duration(milliseconds: 150),
  child: IgnorePointer(child: CustomPaint(painter: _GridOverlayPainter(...))),
)
```

### Renderer change

Generalize `_centerCropToSquare` (lines 163–175):
```dart
img.Image _cropToSelectedSquare(
  img.Image src, {
  required Offset offset,
  required double scale,
}) {
  final rect = computeSourceSquareRect(
    sourceWidth: src.width,
    sourceHeight: src.height,
    offset: offset,
    scale: scale,
  );
  if (rect == null) return src; // degenerate fallback
  return img.copyCrop(src, x: rect.x, y: rect.y, width: rect.side, height: rect.side);
}
```

Call site (replacing the conditional `request.nineGridSocialMode ? _centerCropToSquare(decoded) : decoded`):
```dart
final source = _cropToSelectedSquare(
  decoded,
  offset: request.sourceOffset,
  scale: request.sourceScale,
);
```

Social mode no longer needs a special crop branch — the unified crop handles it.

### Migration impact on existing tests

* `grid_image_renderer_social_test.dart` line 247–267 asserts non-social on `landscapeSource()` (600×300) produces 200×100 cells. After this change the source is cropped to 300×300 first, then 3×3 yields 100×100 cells. Update the assertion. Add a sibling test using a custom `sourceOffset` to prove drag-select propagates through.
* No other tests reference `landscapeSource()` for sizing.

### Reset button placement

Controls panel already groups grid type, spacing, radius. Add the reset button as a trailing icon-button in the panel header (next to the social toggle if room) OR as a small `OutlinedButton.icon` row above the parameter cards. Final placement decided during impl by reading `grid_controls_panel.dart` layout — keep within the existing 16 dp gutter.
