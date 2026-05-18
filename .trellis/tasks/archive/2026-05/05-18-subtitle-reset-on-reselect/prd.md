# subtitle-mode: reset band height when first image is re-picked

## Goal

In the long-stitch movie-subtitle mode, the user-tuned subtitle-band-height
percent should auto-reset to its default whenever the editor transitions
from "no images" → "first image picked again". A new batch of images can
have very different dimensions, so the previous percent (tuned against the
prior first image's scaled height) no longer corresponds to the visual
subtitle band — keeping it sticky degrades UX.

## What I already know

- `StitchEditorState.subtitleBandHeightPercent` defaults to
  `kDefaultSubtitleBandHeightPercent = 0.12` (range 0.05–0.50).
  (`lib/features/long_stitch/domain/entities/stitch_editor_state.dart:9-22`)
- The percent is stored sticky across image-list edits — see comment in
  `setSubtitleOnlyMode` (provider:79-80) describing intentional
  stickiness for the on/off toggle.
- The editor mirrors `importedImagesProvider(.stitch)` via
  `ref.listen` in `stitch_editor_provider.dart:36-40`. This is the
  natural place to detect the `prev.isEmpty && next.isNotEmpty` edge.
- The percent feeds two consumers (preview + render request):
  - `stitch_preview_canvas.dart:104-111`
  - `stitch_render_request.dart:63-70`
  Both multiply by `state.images.first.height` (scaled), so the band
  pixels are derived from the *current* first image — meaning the
  percent itself is the only "stale" state.

## Assumptions (temporary, to validate)

- Reset target = `kDefaultSubtitleBandHeightPercent` (0.12), not the
  user's previous value.
- Reset trigger = strictly the "all empty → first image added" edge.
  Removing arbitrary mid-list images, or swapping the first image when
  the list is still non-empty, does **not** reset.
- `subtitleOnlyMode` toggle stays sticky (NOT reset). User had to
  deliberately turn it on; we don't take that away.
- `autoTrimBlackBars` stays sticky (NOT reset). Same reasoning.

## Open Questions

- (none — Q1 resolved: unconditional reset)

## Requirements (evolving)

- When the editor's image list transitions from empty to non-empty
  (i.e. user picks an image after previously clearing all), the
  `subtitleBandHeightPercent` is reset to
  `kDefaultSubtitleBandHeightPercent`.
- The reset must NOT fire on:
  - regular append (list was already non-empty)
  - removing a non-first image
  - reordering
  - editor first-mount with a pre-existing list (avoid clobbering
    persisted user state, if any)

## Acceptance Criteria (evolving)

- [ ] Editor starts empty, user picks first image → percent equals
  default (0.12) regardless of any value previously held.
- [ ] User had list of N>0 images, picks more → percent unchanged.
- [ ] User removes images one by one until empty, then picks again →
  percent reset to default.
- [ ] User clears all via `clear()` then picks again → percent reset
  to default.
- [ ] Reorder / single non-first removal → percent unchanged.
- [ ] Unit test on `StitchEditorController` covers the edge transitions
  above using a fake import provider override.

## Definition of Done

- `dart format .`, `flutter analyze`, `flutter test` all green.
- Behavior change documented in PRD §3.3 (movie-subtitle) of the
  feature spec.

## Out of Scope (explicit)

- Persisting `subtitleBandHeightPercent` across app launches (not
  currently persisted — outside this task).
- Smart heuristics that pick a "best" percent from the new first
  image's dimensions. Plain default reset only.
- Resetting `subtitleOnlyMode` or `autoTrimBlackBars`.
- Horizontal mode (the subtitle path only activates on vertical mode
  with ≥2 images anyway).

## Technical Approach

In `StitchEditorController.build()`'s `ref.listen` callback for
`importedImagesProvider(.stitch)`:

```dart
ref.listen<List<ImportedImage>>(importedImagesProvider(kind), (prev, next) {
  final wasEmpty = prev == null || prev.isEmpty;
  final nowNonEmpty = next.isNotEmpty;
  final shouldResetSubtitle = wasEmpty && nowNonEmpty && state.images.isEmpty;
  // ^ guard with state.images.isEmpty so the very first mount doesn't
  //   reset (build() seeds `images: initial`, and prev is null on the
  //   first listener invocation, but state.images already matches
  //   `initial`).
  state = state.copyWith(
    images: next,
    subtitleBandHeightPercent: shouldResetSubtitle
        ? kDefaultSubtitleBandHeightPercent
        : state.subtitleBandHeightPercent,
  );
});
```

Critical: the `state.images.isEmpty` guard prevents the listener's
first-fire (when `prev` is null) from clobbering the percent if the
editor mounts with a non-empty `initial`.

## Decision (ADR-lite)

**Context**: `subtitleBandHeightPercent` is a sticky percent (default
0.12) tied to *the current first image's scaled height*. After the user
clears all images and picks a fresh batch, the previous percent —
tuned to the prior first image's letterbox geometry — no longer matches
the visual subtitle band of the new images. Whether to also gate this
on `subtitleOnlyMode == true` was the open question.

**Decision**: Unconditional reset on the `empty → non-empty` edge.
Subtitle-mode toggle and `autoTrimBlackBars` stay sticky; only the
percent is reset (and only on that edge).

**Consequences**:
- Pro: single, deterministic rule; no hidden coupling between two
  sticky fields; same behavior whether the user toggles subtitle mode
  before or after the new batch is in.
- Pro: `percent` stays semantically "fresh-default per batch", which
  matches user mental model better than "leftover from last batch".
- Con: a user who clears + reimports the *same* batch loses their
  custom percent — accepted, the slider is cheap to re-adjust and the
  alternative requires fingerprinting image bytes.

## Technical Notes

- Files to edit:
  - `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
    (single listener change)
- Files to add tests in:
  - `test/features/long_stitch/presentation/providers/stitch_editor_provider_test.dart`
    (new — currently no provider-level test for stitch editor)
