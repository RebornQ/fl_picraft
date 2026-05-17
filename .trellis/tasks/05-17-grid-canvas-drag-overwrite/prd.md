# Grid Canvas: drag-to-select crop + overwrite import + square chrome

> **Umbrella task.** Implementation is split across three child subtasks
> (see "Subtasks" below). This document is the single source of truth for
> the cross-cutting requirements, decisions, and acceptance criteria.

## Goal

Improve the grid-split editor's source-image workflow so users can:

1. **Drag + pinch-zoom** the canvas to explicitly select which square region of a non-square screenshot becomes the active source for grid slicing.
2. **Overwrite-import** the current source with a confirmation dialog when an image already exists.
3. See a flat, **square-cornered** canvas (chrome `borderRadius` drops from 16 dp → 0).

## Subtasks

| # | Slug | Scope | LoC est. |
|---|------|-------|----------|
| ST-A | `05-17-grid-canvas-square-chrome` | Drop `BorderRadius.circular(16)` to `BorderRadius.zero` on `GridPreviewCanvas` chrome. Update any snapshot fixtures. | ~5 |
| ST-B | `05-17-grid-overwrite-import-confirm` | AppBar import action prompts "Replace existing image?" when source exists; on confirm, clears the grid-kind import session before launching the picker so the new image overwrites. Cancel preserves current state. | ~80 |
| ST-C | `05-17-grid-canvas-drag-crop` | Pan + pinch-zoom gesture on the canvas → new `sourceOffset`/`sourceScale` state → `GridRenderRequest` carries the user-selected square crop → renderer slices from the chosen region. Includes clamp, reset button, grid-line hide-on-drag, and isolation from `CenterCellOverlay` gesture. | ~250+ |

Land in order: ST-A → ST-B → ST-C (each is independently shippable; ST-C is the architectural change).

## Decisions (ADR-lite)

* **D1 — Interaction model: pan + pinch-zoom.** Two new state fields (`sourceOffset: Offset` in normalized [0,1], `sourceScale: double`). Reuse the `ScaleGestureRecognizer` idiom already proven by `CenterCellOverlay`.
  * Context: drag-only would not let the user pick a tighter region than the cover-fit square; pan + zoom mirrors Instagram-style crop and is the most flexible while remaining one gesture stream.
  * Consequences: gesture stream multiplexes pan and zoom — clamping must consider both axes; pure-Dart conversion math lives under `domain/usecases/`.
* **D2 — Crop is always a 1:1 square.** The canvas viewport is `AspectRatio(1)`, so the user-selected region is always square. This **replaces** the implicit centre-cover crop in social mode AND the "slice the full non-square source" path in non-social mode.
  * Context: simplest mental model; eliminates the silent "preview vs export" mismatch on non-square sources today.
  * Consequences: **breaking behaviour change** — a 600×300 panorama exported through 3×3 non-social today produces 200×100 rectangular cells; after this change it produces 100×100 squares from a 300×300 region of the user's choosing. Tests pinned to the old behaviour need to be updated.
* **D3 — Overwrite import: confirm-then-replace.** When `state.hasSource` is true, tapping the AppBar import action shows an `AlertDialog` ("替换现有图片？取消 / 替换"); on confirm, the grid-kind import session is cleared before the picker opens, so the new image flows in as a fresh `next.first`. Drag offset / scale reset to defaults.
* **D4 — Edge-case enhancements baked into MVP** (all selected by user):
  * Drag clamp: offset bounded so source never letterboxes; `sourceScale` clamped to `[1.0, 4.0]` (1.0 = cover-fit).
  * "重置裁剪" button in the controls panel — sets `(offset=center, scale=1.0)` in one tap.
  * Grid lines hide during active drag/zoom and fade back in on gesture end.
  * Center-cell overlay (social mode) retains gesture priority over background drag.

## Requirements

* **R-CHROME-01** [ST-A] `GridPreviewCanvas` container uses `BorderRadius.zero` in all size classes.
* **R-IMPORT-01** [ST-B] Re-importing prompts the user when a source already exists; confirmed overwrite replaces the source atomically (clear session → pick → new image populates `state.source`).
* **R-IMPORT-02** [ST-B] Cancelling the confirm dialog leaves the current source, offset, and scale untouched (no picker is launched).
* **R-DRAG-01** [ST-C] Canvas accepts a one-finger pan + two-finger pinch-zoom gesture; both translate into `sourceOffset` / `sourceScale` mutations on the controller.
* **R-DRAG-02** [ST-C] `sourceOffset` is clamped so the canvas viewport never reveals area outside the source bounds; `sourceScale` is clamped to `[1.0, 4.0]`.
* **R-DRAG-03** [ST-C] `sourceOffset` / `sourceScale` survive grid-type, spacing, and corner-radius changes; they reset to defaults on new import (covered by R-IMPORT-01) and on tapping the "重置裁剪" button.
* **R-DRAG-04** [ST-C] Grid overlay (cell strokes + corner radius) is invisible during an active gesture; fades back in within 150 ms after gesture end.
* **R-DRAG-05** [ST-C] In social mode (3×3 + nine-grid-social toggle), the center cell `CenterCellOverlay` gesture takes priority over the background canvas drag.
* **R-RENDER-01** [ST-C] `GridRenderRequest` carries `sourceOffset` and `sourceScale`. The renderer crops the decoded source to the user-selected square **first**, then runs `computeGridLayout` against that square. Social mode's previous `_centerCropToSquare` becomes a degenerate path (offset=0.5/0.5, scale=1.0).

## Acceptance Criteria

* [ ] **AC1** [ST-A] `GridPreviewCanvas` chrome shows no rounded corners on compact, medium, expanded, and large layouts.
* [ ] **AC2** [ST-B] Importing when source exists shows a confirm dialog; confirm replaces, cancel preserves.
* [ ] **AC3** [ST-C] A 9:16 portrait screenshot can be panned vertically to pick which square region becomes the active source.
* [ ] **AC4** [ST-C] Pinch-zoom expands `sourceScale` up to 4.0 and never below 1.0; offset auto-clamps as scale changes.
* [ ] **AC5** [ST-C] Grid overlay hides during active gestures and re-appears within 150 ms after gesture end.
* [ ] **AC6** [ST-C] Controls panel includes a "重置裁剪" button that restores `offset=(0.5, 0.5), scale=1.0` and re-shows the grid.
* [ ] **AC7** [ST-C] Changing grid type, spacing, or corner radius does not alter the user's `sourceOffset` / `sourceScale`.
* [ ] **AC8** [ST-C] Exported cells are square (1:1) and slice from the chosen square region, byte-matching the on-screen preview at common scales (1.0, 2.0).
* [ ] **AC9** [ST-C] In social-mode 3×3, tapping/dragging within the center cell's bounds drives the `CenterCellOverlay` (not the canvas drag).
* [ ] **AC10** [all] `flutter analyze`, `dart format .`, `flutter test` all clean on every PR.

## Definition of Done

* Each subtask ships with unit + widget tests covering its surface area.
* ST-C adds renderer-level integration tests asserting exported cells match the chosen crop (on at least one non-square source + non-default offset/scale combination).
* Pre-existing tests that asserted non-square cell shapes (e.g. `landscapeSource()` → 200×100 cells) are migrated to reflect D2 (the new contract is "all cells are square").
* Specs updated if a new convention emerges (e.g. canvas viewport state pattern → consider documenting in `state-management.md`).

## Out of Scope

* Persisting `sourceOffset` / `sourceScale` across app restarts.
* Non-1:1 crop aspect ratios.
* `sourceScale > 4.0` or rotation / mirror gestures.
* Changes to the stitch editor's canvas (stitch lives in its own feature, untouched here).
* Modifying `CenterCellOverlay` internals; only its gesture priority is tightened.

## Technical Notes

### State surface (`GridEditorState`)
Add two fields:
```
final Offset sourceOffset;      // default (0.5, 0.5), normalized
final double sourceScale;       // default 1.0, range [1.0, 4.0]
```
Plus `copyWith` parameters. `kDefaultSourceOffset = Offset(0.5, 0.5)` and `kDefaultSourceScale = 1.0` constants alongside the existing center-cell defaults.

### Render request contract
`GridRenderRequest` gains the same two fields. `fromState` wires them through. The renderer's `_renderInIsolate` cuts the source square **before** calling `computeGridLayout`. The existing `_centerCropToSquare` is generalized into a `_cropToSelectedSquare(decoded, offset, scale)` helper.

### Pure-Dart conversion math
A new `domain/usecases/compute_source_crop.dart` mirrors `compute_center_transform.dart`'s structure:
* `computeSourceSquareRect({sourceWidth, sourceHeight, offset, scale}) → SourceRect`
* `clampSourceOffset({offset, scale, sourceAspect}) → Offset`
* Pure functions only — no Flutter imports → isolate-safe + unit-testable.

### Canvas widget gesture surface
Wrap the existing `Stack` in a `GestureDetector` (or `RawGestureDetector` for finer control) handling `onScaleStart/Update/End`. Use a `Listener` or `behavior: deferToChild` so the `CenterCellOverlay`'s own scale recognizer wins inside its hit area (R-DRAG-05). The grid-overlay `IgnorePointer` already prevents the overlay from competing for hits.

### Hide grid on gesture
Local widget state (`bool _isGesturing`) toggles an `AnimatedOpacity` (150 ms) around the `_GridOverlayPainter`. Lives in `_PreviewSurface` so it doesn't leak into the controller.

### Overwrite-import flow (ST-B)
Sequence in `addFromGallery()` (or a new `replaceFromGallery()` sibling):
1. If `state.hasSource`, surface an `AlertDialog` via the `gridEditorControllerProvider`'s caller widget (controller stays UI-free).
2. On confirm, call `imageImportControllerProvider(.grid).notifier.clear()` and reset `sourceOffset`/`sourceScale`.
3. Then call existing `pickFromGallery()` — the session sync will install the new image cleanly.

### Test surface
* `test/features/grid/domain/compute_source_crop_test.dart` — new unit tests for the crop math.
* `test/features/grid/data/grid_image_renderer_social_test.dart` — existing file; migrate the "preserves non-square cells" tests to assert square cells after D2 + add a "drags the crop" test on a 600×300 source.
* `test/features/grid/presentation/grid_preview_canvas_drag_test.dart` — new widget test for gesture → state mutation.
* `test/features/grid/presentation/grid_editor_screen_overwrite_import_test.dart` — new test for ST-B's dialog flow.

## Research References

(none — all decisions resolved via direct codebase inspection + user preference.)
