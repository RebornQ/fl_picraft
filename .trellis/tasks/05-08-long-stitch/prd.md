# Long Stitch Feature

> **Parent task**: combines vertical/horizontal/movie-subtitle stitching modes into a single editor screen.

## Goal

Implement the Long Stitch editor where users add up to 20 images, reorder them, choose a stitching mode, tweak parameters, and preview the result in real time. Three modes share the same editor shell; the controls panel swaps based on the selected mode.

## Subtasks

| Subtask | What it covers |
|---------|---------------|
| [`05-08-vertical-horizontal`](../05-08-vertical-horizontal/prd.md) | Vertical (equal width) and horizontal (equal height) stitching with spacing/border/radius |
| [`05-08-movie-subtitle`](../05-08-movie-subtitle/prd.md) | Layered overlay where each subsequent image only contributes its bottom subtitle band |

## Shared editor surface

UI reference: [`docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_2_长图拼接/code.html`](../../../docs/UI%20Design/Fl_PiCraft_stitch_prd_ui_generator/_2_%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/code.html)

Layout:

- **Top bar**: back, title (Fl PiCraft), export button
- **Image list (horizontal scroll)**: 32-w cards with thumbnail + filename + dimensions + remove button; supports drag reorder via `reorderables`
- **Preview canvas**: dotted radial background (`stitch-canvas` style), centered preview with `max-w-sm` constraint, white shadow background
- **Bottom controls (sticky above bottom nav)**:
  - Mode segmented control (竖向 / 横向) + 仅保留字幕 toggle
  - Mode-specific settings (subtitle height slider when movie-subtitle is on)

## Acceptance Criteria (parent-level)

- [ ] Editor opens from Home → "长图拼接" card or BottomNav → 长图拼接
- [ ] Image reorder via drag persists order in Riverpod state
- [ ] Switching modes preserves the image list
- [ ] Preview updates within 100ms of parameter change
- [ ] All children completed

## Out of Scope

- Per-image rotation / cropping (parking lot for v2)
- Undo / redo history
- Saving stitch sessions to disk for later editing

## Dependencies

- Requires: `05-08-foundation`, `05-08-image-import`
- Blocks: `05-08-export-watermark` (export needs a finalized stitched image)

## References

- Total PRD §3 长图拼接
- Spec: `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/component-guidelines.md`
