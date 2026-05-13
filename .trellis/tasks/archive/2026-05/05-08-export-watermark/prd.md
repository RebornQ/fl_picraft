# Export & Watermark

> **Parent task**: export pipeline and the optional watermark overlay layered before encoding.

## Goal

Provide a unified export screen reachable from both the Long Stitch and Grid Split editors. Users pick PNG or JPG, adjust JPG quality, optionally enable a text watermark, and save the result(s) to the platform-appropriate destination.

## Subtasks

| Subtask | What it covers |
|---------|---------------|
| [`05-08-watermark`](../05-08-watermark/prd.md) | Text watermark composition (content / position / opacity / size) |
| [`05-08-export-multiplatform`](../05-08-export-multiplatform/prd.md) | Format / quality / multi-platform save (gallery, file dialog, web download) |

## Shared export surface

UI reference: [`docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`](../../../docs/UI%20Design/Fl_PiCraft_stitch_prd_ui_generator/_4_%E5%AF%BC%E5%87%BA%E9%A1%B5%E9%9D%A2/code.html)

Layout:

- **Two-column on lg**: large preview + settings aside
- **Preview area**: scrollable container (for long stitches) with hover-revealed zoom controls
- **Settings card**: Format (JPG/PNG segmented buttons), Quality slider (1-100%, JPG only)
- **Watermark card**: master toggle, text input, 3x3 position picker, opacity slider
- **Save button**: full-width primary CTA "保存至相册"
- **Disclaimer card**: "我们不会上传任何数据到服务器"

## Acceptance Criteria (parent-level)

- [ ] Export screen accepts an `ExportSource` (stitch result or grid cells) from upstream features
- [ ] Watermark composition happens once before encoding (no double-apply)
- [ ] Save success surfaces a toast with the saved location
- [ ] Both children completed

## Out of Scope

- Image watermarks (only text in MVP)
- Batch export presets (single export per session)
- Re-encoding existing images outside the editor

## Dependencies

- Requires: `05-08-long-stitch` and `05-08-grid-split` (consumes their outputs)
- Blocks: `05-08-polish-platform-test`

## References

- Total PRD §5.4 Export, §5.5 Watermark
- Spec: `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/type-safety.md`
