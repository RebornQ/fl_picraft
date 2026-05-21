# ADR-0001: Immersive page scroll physics for the fullscreen preview gallery

**Date**: 2026-05-22
**Status**: Accepted
**Context task**: `.trellis/tasks/05-22-export-preview-fullscreen-immersive/`

---

## Context

The export-screen fullscreen preview (`PreviewFullScreenDialog`) needs to behave like a mainstream photo gallery — iOS Photos / Google Photos / Twitter image viewer:

* Pinch zoom + double-tap zoom + free pan when zoomed
* Multiple images browsable via horizontal swipe
* **When zoomed, horizontal pan that reaches the image edge should naturally bleed into a page swipe** — the next image's edge slides in from off-screen while the current image is still partially in view

Flutter ships `PageView` and `InteractiveViewer` as orthogonal building blocks. Neither composes naturally with the other for the gallery use case:

* If `PageView` always claims horizontal drags → `InteractiveViewer` can't pan a zoomed image
* If `InteractiveViewer` always claims horizontal drags when zoomed → `PageView` can't page-swipe after the image hits its pan edge

The third-party `photo_view_gallery` package solves this by shipping a custom `ScrollPhysics`. We don't want to take that dependency for one screen.

## Decision

Implement a private `_ImmersivePageScrollPhysics extends PageScrollPhysics` inside `preview_full_screen_dialog.dart`. The physics consults a parent-owned **horizontal edge state** for the currently-visible page and decides per-drag whether to accept the user offset:

```
                            ┌────────────────────────────────┐
                            │  current page scale ≈ 1.0      │
                            │  → behave like PageScrollPhysics
                            └────────────────────────────────┘
                                       OR
                            ┌────────────────────────────────┐
                            │  current page scale > 1.0      │
                            │  AND not horizontally clamped  │
                            │  → reject user offset (let     │
                            │    InteractiveViewer pan)      │
                            └────────────────────────────────┘
                                       OR
                            ┌────────────────────────────────┐
                            │  current page scale > 1.0      │
                            │  AND horizontally clamped      │
                            │  AND drag direction "outward"  │
                            │  → accept user offset, drag    │
                            │    delta flows naturally into  │
                            │    a page change               │
                            └────────────────────────────────┘
```

Communication path:

1. Each `_PreviewPage` (StatefulWidget) holds its own `TransformationController` and registers an `addListener` that recomputes its zoom + edge state
2. The page reports `{ zoomed: bool, edge: EdgeState }` to the parent (`_PreviewFullScreenDialogState`) via a callback — **only when it is the current page** (the parent ignores reports from off-screen pages)
3. The parent stores the current page's state in a `ValueNotifier<PageState>` so `_ImmersivePageScrollPhysics` can read it during gesture arbitration without rebuilding the PageView

Edge detection algorithm:

```
imageRenderedWidth = imageDisplayWidth * scale
// imageDisplayWidth is the rect produced by BoxFit.contain inside the page viewport
tx = currentMatrix.translation.x
maxTx = (imageRenderedWidth - imageDisplayWidth) / 2

// Left edge clamped: image cannot pan further to the right
atLeft  = tx >= maxTx - 0.5
// Right edge clamped: image cannot pan further to the left
atRight = tx <= -maxTx + 0.5
```

`scale ≈ 1.0` (`<= 1.01`) is treated as "always free" — both edges considered un-clamped so PageView always accepts.

## Alternatives considered

### A. Hard switch via `NeverScrollableScrollPhysics` when zoomed

The first PRD draft had this: PageView physics flips to `NeverScrollableScrollPhysics` whenever any page is zoomed. Simple, but user must explicitly double-tap to reset before swiping to the next image. **Rejected** — degrades from mainstream gallery UX.

### B. `photo_view_gallery` dependency

Mature, battle-tested, ~10 KB. **Rejected** — project-wide policy of "no new dependency for one screen UX", per task scope. Re-evaluate if more screens later need the same primitive.

### C. Release-then-jump (B-α earlier in brainstorm)

Listen to `InteractiveViewer.onInteractionEnd`; if image is clamped + fling direction is outward, call `PageController.animateToPage`. **Rejected** — during the drag the image visibly "sticks" against the edge until the user releases, breaking the continuous gesture feel.

### D. External `GestureDetector` interception (B-γ)

Wrap `InteractiveViewer` in an outer `GestureDetector(onHorizontalDrag*)`; when image is clamped + drag direction outward, manually accumulate `PageController.position.jumpTo(offset + delta)`. **Rejected** for this task — the custom-physics path keeps the gesture arena clean (one PageView, one ScrollPhysics, one source of truth) and reuses Flutter's existing fling / clamp / momentum behavior. The interception path has to re-implement those.

## Consequences

### Positive

* Mainstream photo gallery feel without a new package
* Single source of truth (`ValueNotifier<PageState>`) for gesture arbitration, easy to reason about
* `_ImmersivePageScrollPhysics` is self-contained and private — can be deleted / replaced wholesale if Flutter ever ships a first-party solution

### Negative

* ScrollPhysics is one of Flutter's more obscure APIs. The `shouldAcceptUserOffset` / `applyBoundaryConditions` / `createBallisticSimulation` triad is **inheritance-with-side-effects** — overriding the wrong method silently breaks momentum / overscroll
* The edge-detection algorithm uses `BoxFit.contain` geometry — if the parent ever changes `BoxFit` mode (e.g. `cover`), `imageDisplayWidth` derivation must be updated. **Mitigation**: hard-code `fit: BoxFit.contain` as part of `_PreviewPage`'s contract (locked in PRD R3)
* Widget tests for the edge-bleed flow are gesture-sequence-heavy (need `WidgetTester.dragFrom + dragBy + pumpFrames`); not trivial to author, but no different than testing any other PhotoView-style UI

### Neutral

* `ValueNotifier` (not Riverpod) is correct here per `.trellis/spec/frontend/state-management.md` — physics state is **gesture-arbitration internal**, not application state

## Validation criteria

* At `scale == 1.0`: horizontal swipe pages just like default `PageScrollPhysics`
* At `scale > 1.0` mid-pan: horizontal drag pans the image without any PageView movement
* At `scale > 1.0` + clamped + outward drag: drag continues smoothly into a page change; on release with sufficient fling velocity, the new page settles in
* At `scale > 1.0` + clamped + drag back toward image: physics rejects user offset, image stays clamped (no PageView jitter)
* After page change settles, new page's transformation is identity (re-created `_PreviewPage` per PageView.builder default)

## References

* PRD: `.trellis/tasks/05-22-export-preview-fullscreen-immersive/prd.md` (Requirements R4)
* Inspiration: `photo_view_gallery` package internals (https://pub.dev/packages/photo_view)
* Flutter ScrollPhysics docs: https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html
