# Grid Split Feature

> **Parent task**: combines regular grid split and the nine-grid social mode into a single editor.

## Goal

Implement the Grid Split editor where a single source image is split into multiple sub-images. Two operating modes: regular grid (11 layouts from 1x2 to 4x4) and nine-grid social mode (3x3 with optional center cell replacement).

## Subtasks

| Subtask | What it covers |
|---------|---------------|
| [`05-08-regular-grid`](../05-08-regular-grid/prd.md) | 11 grid types: 1x2 / 2x1 / 1x3 / 3x1 / 1x4 / 4x1 / 2x2 / 2x3 / 3x2 / 3x3 / 4x4 |
| [`05-08-nine-grid-social`](../05-08-nine-grid-social/prd.md) | 3x3 split with center cell replaceable by a separate avatar/badge image |

## Shared editor surface

UI reference: [`docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_3_宫格切图/code.html`](../../../docs/UI%20Design/Fl_PiCraft_stitch_prd_ui_generator/_3_%E5%AE%AB%E6%A0%BC%E5%88%87%E5%9B%BE/code.html)

Layout:

- **Top bar**: back, title (宫格切图编辑), export button
- **Square preview canvas (aspect-square)** with grid overlay (white 40%-opacity lines) and an interactive center cell when nine-grid mode is active
- **Mode toggle card**: 九宫格朋友圈模式 with a switch
- **Grid type selector (horizontal scroll)**: 11 grid options as 80x80 cards with material symbol previews
- **Bento parameter cards**: 宫格间距 (tertiary container), 圆角大小 (secondary container)
- **Bottom action bar**: BottomNav + floating export FAB

## Acceptance Criteria (parent-level)

- [ ] Editor opens from Home → "宫格切图" card or BottomNav → 宫格切图
- [ ] Selecting a grid type updates the preview overlay live
- [ ] Toggling nine-grid mode reveals center cell replacement UI
- [ ] Spacing / radius cards adjust the rendered cells
- [ ] All children completed

## Out of Scope

- Free-form rectangular crops (only fixed grid types)
- Per-cell text or stickers

## Dependencies

- Requires: `05-08-foundation`, `05-08-image-import`
- Blocks: `05-08-export-watermark`

## References

- Total PRD §4 宫格切图
- Spec: `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/state-management.md`
