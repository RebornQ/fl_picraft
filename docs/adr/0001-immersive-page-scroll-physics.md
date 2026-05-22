# ADR-0001: Immersive page scroll physics for the fullscreen preview gallery

**Date**: 2026-05-22
**Status**: Superseded by [ADR-0002](./0002-extended-image-fullscreen-preview.md) (2026-05-23)
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

## Compatibility Note (2026-05-22, task `05-22-limit-fullscreen-preview-pan-bounds`)

From `05-22-limit-fullscreen-preview-pan-bounds` onwards, the `InteractiveViewer` inside `_PreviewPage` uses default `constrained: true` + a `Center(SizedBox.fromSize(size: renderedSize, child: Image(fit: BoxFit.fill)))` child + `boundaryMargin: EdgeInsets.zero`, where `renderedSize = applyBoxFit(BoxFit.contain, imageSize, viewport).destination`. Under `constrained: true`, the InteractiveViewer's direct child is forced to viewport size; the inner `Center + SizedBox` then renders the image rect at viewport centre. `boundaryMargin: zero` clamps the pan to the child's (viewport-sized) edges — the user cannot pan the child past the viewport border (was: unbounded `EdgeInsets.all(double.infinity)`, which let the image be dragged completely out of the viewport).

**Visual equivalence with strict image-edge clamping**: the dialog's outer `ColoredBox` background is `Colors.black`, so the letterbox black bands sit between the image rect and the viewport edge but are visually indistinguishable from the surrounding background. The user perceives the pan limit at the image-pixel edge — the same UX as iOS Photos / Google Photos.

The edge-detection formula consumed by `_ImmersivePageScrollPhysics` is unchanged:

```
maxTx = (renderedW * scale - renderedW) / 2
atLeftEdge  = tx >= maxTx - 0.5
atRightEdge = tx <= -maxTx + 0.5
```

`renderedW` is still derived from `_imageDisplayRect` (the `BoxFit.contain` rect inside the viewport), which is the same geometry that drives the new `SizedBox.fromSize(size: renderedSize)` child. The formula is based on image-pixel geometry, not on the InteractiveViewer's child structure, so it remains correct under either of the two layouts considered for this task. **Note**: under the M-α layout the InteractiveViewer's physical max translation is `(viewport.w * scale - viewport.w) / 2` (based on viewport-sized child) which is greater than the `maxTx` derived from image-pixel rect — meaning `atLeftEdge / atRightEdge` triggers **as soon as the image-pixel rect reaches the viewport edge**, exactly when the user perceives "the image hit the edge".

Before-image-resolve fallback: `renderedSize` falls back to `viewport` until `_imageSize` arrives from the `ImageStreamListener`. The `Center > SizedBox > Image(fit: fill)` structure is identical across the pre-resolve and post-resolve builds, so the `InteractiveViewer` widget identity and the `TransformationController` state are never dropped mid-build. The fallback window is the duration of the first `MemoryImage` decode (~1 frame in practice).

### Why M-α and not L-β (constrained: false + alignment: center)

An initial implementation of this task tried `constrained: false + alignment: Alignment.center + SizedBox(renderedSize) + boundaryMargin: zero` (the L-β path) to clamp the pan strictly at the image-pixel edges (no letterbox panning at all). The result regressed centring — the image was being anchored at the viewport's top-left corner. Root cause confirmed against Flutter's source `interactive_viewer.dart:1123-1141`:

* `InteractiveViewer.alignment` is passed to the **internal `Transform.alignment`** (the matrix's transform anchor), NOT the child's alignment inside the viewport.
* When `constrained: false`, Flutter hard-codes the child wrapper as `OverflowBox(alignment: Alignment.topLeft)` with **no API** to override that alignment to centre.

Therefore there is no `constrained: false` configuration that keeps the image centred inside the viewport under the current Flutter SDK. The M-α layout side-steps the hard-coded `topLeft` path entirely by staying on `constrained: true` and providing centring via a plain `Center` widget inside the child subtree — the same way every other Flutter centring is achieved.

## References

* PRD: `.trellis/tasks/05-22-export-preview-fullscreen-immersive/prd.md` (Requirements R4)
* Pan-limit follow-up: `.trellis/tasks/05-22-limit-fullscreen-preview-pan-bounds/prd.md`
* Inspiration: `photo_view_gallery` package internals (https://pub.dev/packages/photo_view)
* Flutter ScrollPhysics docs: https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html

## Superseded by ADR-0002 (2026-05-23)

Real-world maintenance of the self-rolled `_ImmersivePageScrollPhysics` exposed two issues that
the original ADR-0001 "for one screen" estimate did not anticipate:

1. The `{atLeftEdge, atRightEdge}` edge-detection plus floating-point tolerance left a
   reproducible "drag continues mid-flight but page does not commit" gap under specific
   gesture sequences (real users noticed; a fully-loaded reviewer could reproduce it on iOS).
2. The implementation accumulated to ~884 lines of widget code + ~783 lines of widget tests,
   plus a per-page `TransformationController` listener that fed a `ValueNotifier<PageState>`
   that the custom `ScrollPhysics` then read from. The plumbing was a maintenance tax on
   every subsequent task that touched the fullscreen preview (drag-to-dismiss + AppBar
   chrome + limit-pan-bounds all had to thread state through the same notifier).

The brainstorm task `05-22-brainstorm-fullscreen-preview-extended-image` re-evaluated the
"no third-party gallery package" stance under the maintenance-cost lens and adopted
`extended_image: ^10.0.1`'s three-piece kit
(`ExtendedImageSlidePage` + `ExtendedImageGesturePageView.builder` + `ExtendedImage.memory(mode:
gesture)`) instead. The decision is recorded in
[ADR-0002](./0002-extended-image-fullscreen-preview.md).

This ADR-0001 is retained as historical record of the constraints that drove the
self-rolled approach. Future work that touches the fullscreen preview should consult
ADR-0002 first.
