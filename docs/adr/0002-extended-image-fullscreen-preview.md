# ADR-0002: Adopt `extended_image` for the fullscreen preview gallery

**Date**: 2026-05-23
**Status**: Accepted
**Context task**: `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/`
(will be archived under `.trellis/tasks/archive/2026-05/` once ST4 wraps)

---

## Context

ADR-0001 (2026-05-22) committed to a self-rolled `_ImmersivePageScrollPhysics extends
PageScrollPhysics` for the fullscreen preview gallery. The decision explicitly rejected
`photo_view_gallery` on the basis of "no new dependency for one screen UX".

Real-world maintenance after that decision exposed two problems:

1. **Reproducible UX bug**. The custom physics tracked horizontal "edge reached" flags
   from each page's `TransformationController` listener, then consulted them in
   `shouldAcceptUserOffset` to decide whether to bleed a zoomed-pan into a page change.
   The `{atLeftEdge, atRightEdge}` triggers used a `0.5`-px floating-point tolerance that,
   under specific gesture sequences (zoomed pan → release → near-edge re-pan → fling),
   left the gallery in a state where the user's drag continued mid-flight but the
   PageView did not commit. The bug was reproducible on iOS by real users.
2. **Maintenance tax**. The self-rolled implementation accumulated to ~884 lines of
   widget code + ~783 lines of widget tests. Every subsequent task that touched the
   fullscreen preview (drag-to-dismiss in `05-22-export-preview-fullscreen-immersive`,
   pan limits in `05-22-limit-fullscreen-preview-pan-bounds`, AppBar chrome auto-hide)
   had to thread state through the same `ValueNotifier<PageState>` plumbing. The cost
   exceeded the original "for one screen" estimate.

The brainstorm task `05-22-brainstorm-fullscreen-preview-extended-image` re-evaluated
the "no third-party gallery package" stance under the maintenance-cost lens. Three
candidate approaches were considered (see "Alternatives considered" below). The
risk-gate PoC under `05-22-extimage-dep-and-poc` (ST1) verified that
`extended_image: ^10.0.1` was free of the three highest-risk open issues
(GitHub #736 drag-to-dismiss + PageView fragility, #761 iOS .memory + BoxFit.contain
regression, desktop mouse drag through ScrollConfiguration).

## Decision

Adopt `extended_image: ^10.0.1` for the fullscreen preview gallery and the export-screen
preview thumbnail. The new widget tree is a **three-piece kit**:

```
ExtendedImageSlidePage              // outer (drag-to-dismiss state machine)
  └ ScrollConfiguration             // dragDevices include mouse + trackpad
      └ ExtendedImageGesturePageView.builder  // multi-image gallery
          └ ExtendedImage.memory(mode: ExtendedImageMode.gesture, inPageView: true,
                                 enableSlideOutPage: true)
```

Per-page double-tap zoom (toggling between identity and `kDoubleTapZoomScale = 2.0`) is
driven by a caller-owned `AnimationController` whose listener calls
`ExtendedImageGestureState.handleDoubleTap(scale, doubleTapPosition)` repeatedly to
animate scale changes between the two endpoints. The package's built-in double-tap
behaviour resets to `initialScale` only, so the toggle requires a caller animation.

`PreviewThumbnail` is migrated to `ExtendedImage.memory(mode: ExtendedImageMode.none)` —
the thumbnail does not need the gesture stack but consolidates the image-display pathway
on a single package, which keeps future Hero-animation work simple.

### Deletion list (~500 lines net reduction)

The following self-rolled symbols were removed from
`lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`:

- `_ImmersivePageScrollPhysics` (the custom `PageScrollPhysics` subclass)
- `_PageGestureState` (per-page edge / zoom state record)
- `_currentZoomed` (`ValueNotifier<bool>` that controlled whether the outer vertical-drag
  recognizer attached to the gesture arena)
- `_imageDisplayRect` + `_resolveImageSize` (intrinsic-size-aware geometry helpers)
- M-α `SizedBox.fromSize(renderedSize)` workaround inside `InteractiveViewer` (the
  centre-of-viewport child needed to keep `BoxFit.contain` clamping correct)
- Outer `GestureDetector(onVerticalDrag*)` that owned drag-to-dismiss
- `AnimationController` for `easeOutCubic` drag-snap-back

### Preserved list

The following self-rolled mechanisms remain in the dialog because they are not in
`extended_image`'s scope or because the package's defaults differ from the desired UX:

- Chrome auto-hide state machine (3 s timer + tap-to-toggle + `AnimatedOpacity` +
  `AnimatedSlide` + `IgnorePointer(!visible)`)
- `_ImmersiveScrollBehavior` (extends `MaterialScrollBehavior` to include
  `PointerDeviceKind.mouse` + `trackpad` in `dragDevices`)
- Caller-owned `AnimationController` driving double-tap zoom via
  `state.handleDoubleTap(scale, doubleTapPosition)`
- `_FloatingCloseButton` (always-on translucent black circle with white X)
- `Dialog.fullscreen(backgroundColor: Colors.transparent)` outer shell (see Post-ST2
  Revision below for the reverse-decision history)

### Accepted UX trade-offs (R3-exception)

1. Drag-to-dismiss spring-back curve degrades from `easeOutCubic 250 ms` to
   `linear 500 ms` (the package's `_backAnimationController` is a raw
   `AnimationController` with no exposed `CurvedAnimation`). Visually observable but
   considered acceptable for a non-primary interaction.
2. Letterbox double-tap focal fallback is no longer needed and was removed. The package
   clamps `doubleTapPosition` against the gesture boundary internally.
3. Pan-edge clamping shifts from "image-pixel edge" (M-α layout) to "viewport edge"
   (package default). Visually equivalent because the dialog backdrop is `Colors.black`
   and the letterbox bands are indistinguishable from the surrounding black.
4. `_currentZoomed`-based gating of drag-to-dismiss is gone; the package gates internally
   on `totalScale <= 1` in `gesture.dart:347-389`. The behaviour is identical.
5. `_ImmersivePageScrollPhysics`-based edge-bleed page switching is gone; the package
   handles it via `gesture.dart:396-431` (`movePage()` predicate) and
   `gesture_page_view.dart:550-556` (`canHorizontalOrVerticalDrag` gate).

## Consequences

### Positive

- Self-maintained code in the dialog drops from ~884 lines to ~429 lines (~52%
  reduction). Test file drops from ~783 lines to ~759 lines after the rewrite +
  consolidation in ST4.
- The "zoom ↔ page change" edge-bleed coordination is fully delegated to upstream —
  the original UX bug that motivated this ADR is fixed by adoption alone.
- The letterbox double-tap focal fallback problem disappears (the package clamps the
  focal internally on every zoom call).
- Future extensions (Hero transitions, in-place cropping, image-filter previews) align
  with `extended_image`'s extension surface: `ExtendedImageMode.editor`,
  `loadStateChanged`, `heroBuilderForSlidingPage`. Minimal scaffolding required.
- Two related conventions were codified into project specs as part of ST1 / ST2:
  - `.trellis/spec/frontend/dependencies-and-platforms.md` — "PoC gate for risky
    third-party packages" (ST1 sediment).
  - `.trellis/spec/frontend/component-guidelines.md` — "Pattern + Gotcha:
    `extended_image` 三件套多图沉浸式画廊" (ST2 sediment, including the two
    must-set flags `enableSlideOutPage: true` and `inPageView: true`).

### Negative

- The spring-back animation curve trade-off (item 1 in R3-exception above) is the most
  visible UX regression. Mitigation: it is recorded in the PRD and the dialog's
  Dart-doc; future "polish" tasks can re-evaluate if the trade-off becomes a problem.
- The project now depends on `extended_image`'s maintenance cadence. Research confirms
  the maintainer has not posted a major release in the last ~13 months (as of
  2026-05-22), so PR / issue triage is slow. Mitigation: the spec file
  `.trellis/spec/frontend/dependencies-and-platforms.md` records a "fork-preparedness"
  note. If a Flutter SDK bump breaks the package and upstream is unresponsive, the
  project can fork.
- Open GitHub issues #736 (drag-to-dismiss + GesturePageView fragility) and #761
  (iOS `.memory` + `BoxFit.contain` regression) were red flags. The ST1 PoC
  exercised the same widget tree we ship in production and verified neither issue
  reproduces. The bug-tracker links remain in the issue tracker for future regression
  surveillance.
- **Post-ST2 Revision (2026-05-23)** — the brainstorm originally specified migrating
  the caller `PreviewThumbnail._openFullScreen` from `showDialog<void>(...)` to
  `Navigator.push(PageRouteBuilder(opaque: false, ...))` so the
  `ExtendedImageSlidePage` backdrop alpha ramp could surface directly. After ST2 was
  implemented and manually smoke-tested, the user reported that `showDialog`'s default
  Material open / close transition was visibly smoother than the transparent
  `PageRoute` switch (which had a perceptible pixel-reflow flash). The decision
  reversed: `_openFullScreen` keeps `showDialog<void>(Dialog.fullscreen(transparent))`.
  This does NOT affect the three-piece kit inside the dialog — it only changes the
  outermost wrapper. See the parent PRD's "Post-ST2 Revision (2026-05-23)" section for
  the full reasoning. Lesson: **main decision (three-piece kit) held but sub-decision
  (caller route type) reversed** — keeping the main and sub decisions layered made the
  reversal cheap (one section's worth of writing, no implementation rework because ST2
  had preserved `Dialog.fullscreen` as a forward-looking safety).

### Neutral

- `photo_view_gallery` (the alternative considered in ADR-0001) remains unused. The
  decision lens this time was "adopt the package whose API surfaces are most
  current + best fit"; `extended_image`'s coverage of six platforms + Wasm-ready
  status + active gallery / editor / cropping / network-image scope made it the
  better fit than `photo_view_gallery`'s narrow "photo viewer only" scope.

## Alternatives considered

### Approach B (rejected): gallery-only `extended_image` + keep self-rolled drag-to-dismiss

Use `ExtendedImageGesturePageView` for the multi-image swiping + per-page gesture
stack, but **retain** the outer `Dialog.fullscreen` + outer
`GestureDetector(onVerticalDrag*)` + `_currentZoomed` machinery for drag-to-dismiss.

- Pros: avoids open-issue #736 risk (drag-to-dismiss + PageView fragility). Smaller
  diff vs the self-rolled implementation. Caller code unchanged.
- Cons: still maintains ~150 lines of self-rolled gesture-arena coordination
  (`_currentZoomed` flips the outer recognizer's callback in/out of the arena). The
  Approach B win on maintenance is modest. The reverse-decision optionality (B can
  always be re-adopted if A turns out badly) is the main reason it was kept as a
  fallback.
- **Why rejected**: the ST1 PoC verified that #736 does NOT reproduce with our
  three-piece kit configuration. With the risk gone, Approach A's larger
  maintenance win wins.

### Approach C (de-facto adopted as the risk-gate path): PoC first, then choose A or B

Run a minimal PoC (`05-22-extimage-dep-and-poc`, ST1 of the brainstorm) that
exercises the three highest-risk red flags before committing the migration plan.
PoC pass → proceed with Approach A. PoC fail on any red flag → re-converge to
Approach B.

- This is precisely what ST1 did. The PoC passed, so the umbrella decision is
  Approach A. Approach C exists in the PRD as a process pattern, not as a separate
  end-state from A.

### `photo_view_gallery` (re-evaluated, still rejected)

The same package considered + rejected in ADR-0001. Mature, battle-tested, but
narrower scope (only a photo viewer; no editor / cropping / loadStateChanged
hooks). Re-evaluating the decision now (with maintenance-cost weight) did not
flip the choice because `extended_image`'s broader extension surface aligns with
the project's likely future direction.

## Validation criteria

- Tests: the full `flutter test` suite stays green after the ST4 test rewrite.
  9 surviving tests preserve their assertions (chrome / close button / titles /
  AppBar leading slot); 16 rewritten tests cover the new `ExtendedImage` /
  `ExtendedImageGesturePageView` / `ExtendedImageSlidePage` tree. The legacy 2
  M-α specific assertions are removed (`boundaryMargin: zero` constraint and the
  `constrained: true + Center + SizedBox(renderedSize)` widget-tree pin); the
  `_ImmersivePageScrollPhysics` physics-class assertion is removed; the letterbox
  double-tap focal-fallback assertion is removed.
- Lint: `flutter analyze` returns 0 issues.
- Format: `dart format --set-exit-if-changed .` returns 0 changed files.
- PoC: ST1's `poc-report.md` records 3/3 red flags PASS (manual smoke by Reborn
  2026-05-22 on one mobile + one desktop). Long-term: the maintenance cadence of
  `extended_image` (PR / issue triage frequency) is tracked once per quarter; if
  upstream becomes unresponsive AND a real regression hits, the
  fork-preparedness note in `dependencies-and-platforms.md` is the escape hatch.
- Manual verification matrix (at least 1 mobile + 1 desktop + 1 web):
  - Single-image: pinch zoom + double-tap toggle + drag-to-dismiss.
  - Multi-image: horizontal fling page change + zoomed edge-bleed page change +
    desktop mouse-drag page change.
  - Chrome auto-hide + tap-to-toggle + close button always interactive.

## References

- Parent brainstorm PRD:
  `.trellis/tasks/05-22-brainstorm-fullscreen-preview-extended-image/prd.md`
- Subtask archives (post-ST4 archive paths under `.trellis/tasks/archive/2026-05/`):
  - ST1: `05-22-extimage-dep-and-poc/` (PoC + `poc-report.md`)
  - ST2: `05-22-migrate-fullscreen-dialog/` (dialog rewrite + ST4 hand-off
    `failing-tests.md`)
  - ST3: `05-22-migrate-preview-thumbnail/` (thumbnail rewrite)
  - ST4: `05-22-rewrite-tests-and-adrs/` (test rewrite + this ADR + cleanup)
- Superseded ADR: [ADR-0001](./0001-immersive-page-scroll-physics.md)
- Project specs codified during the migration:
  - `.trellis/spec/frontend/dependencies-and-platforms.md` — "PoC gate for risky
    third-party packages" convention
  - `.trellis/spec/frontend/component-guidelines.md` — "Pattern + Gotcha:
    `extended_image` 三件套多图沉浸式画廊"
- Package: `extended_image: ^10.0.1`
  - pub.dev: <https://pub.dev/packages/extended_image>
  - GitHub: <https://github.com/fluttercandies/extended_image>
- Tracked GitHub issues (regression surveillance):
  - #736 — swipe-to-dismiss + page view fragility (Android, 16 comments): <https://github.com/fluttercandies/extended_image/issues/736>
  - #761 — iOS `.memory + BoxFit.contain` (open, 0 comments at time of ADR): <https://github.com/fluttercandies/extended_image/issues/761>
  - #752 — `allowImplicitScrolling` preload gap: <https://github.com/fluttercandies/extended_image/issues/752>
  - #686 — minScale rebound stuck: <https://github.com/fluttercandies/extended_image/issues/686>
  - #648 — rapid horizontal swipe stutter: <https://github.com/fluttercandies/extended_image/issues/648>
- Implementation reference:
  `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
