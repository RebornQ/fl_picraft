# ST-A · Grid canvas square chrome (borderRadius → 0)

> Parent: [`05-17-grid-canvas-drag-overwrite`](../05-17-grid-canvas-drag-overwrite/prd.md)

## Goal

Drop the 16 dp rounded corners on `GridPreviewCanvas` chrome down to a flat 0 dp radius. Smallest, isolated PR that ships first to de-risk the larger drag-crop work that follows.

## Scope

* **Single file change** (`lib/features/grid/presentation/widgets/grid_preview_canvas.dart`):
  * Line 63: `borderRadius: BorderRadius.circular(16)` → `borderRadius: BorderRadius.zero`.
  * `clipBehavior: Clip.antiAlias` stays — non-functional with zero radius, but keeps the call site idiomatic.

## Requirements

* **R-CHROME-01** `GridPreviewCanvas` outer `Container` uses `BorderRadius.zero` in every layout (compact / medium / expanded / large).

## Acceptance Criteria

* [ ] **AC1** Visual: chrome shows no rounded corners on a compact (portrait phone), expanded (tablet landscape), and large (desktop) window size.
* [ ] **AC2** Existing widget tests around the canvas chrome still pass; any snapshot or pixel assertion that pinned the rounded radius is updated.
* [ ] **AC10** `flutter analyze`, `dart format .`, `flutter test` clean.

## Definition of Done

* No new tests required (visual chrome change).
* Verify no other widget tests rely on the 16 dp radius via golden / pixel comparison.
* No spec update needed — chrome radius is a per-component decision, not a design-token rule.

## Out of Scope

* Drop shadow, border colour, surface tint — all stay as-is.
* Any other chrome on the editor screen (controls panel chrome keeps its 12 dp radius).

## Technical Notes

* The `Container(decoration: BoxDecoration(...))` block at `grid_preview_canvas.dart:60-72` is the only touchpoint.
* `Clip.antiAlias` with zero radius is a no-op but harmless; leave it for consistency.
