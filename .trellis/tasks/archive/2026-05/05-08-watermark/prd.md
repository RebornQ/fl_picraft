# Watermark Feature

> Subtask of [`05-08-export-watermark`](../05-08-export-watermark/prd.md)

## Goal

Compose an optional text watermark over the export source before encoding. Users control content, position, opacity, and font size. The watermark is applied **once** to the final composite — never to source images individually.

## Properties

| Property | Range / values | Default |
|----------|----------------|---------|
| Text | Any UTF-8 string, 1–40 chars | "Fl PiCraft" |
| Position | 9 anchors (TL/TC/TR/ML/MC/MR/BL/BC/BR) | BR |
| Opacity | 10% – 100% | 50% |
| Font size | small (12px) / medium (18px) / large (28px) — or numeric 8–48 | medium |
| Color | white with auto-shadow contrast (no picker in MVP) | white |
| Font family | Inter (project default) | Inter |

## UI surface

UI ref: `_4_导出页面/code.html` lines 170–205

- **Section header** with master toggle (lines 171–177): when off, the watermark card is collapsed/dimmed
- **Text input** (lines 179–183): label "文字内容", default "Fl PiCraft"
- **Position picker** (lines 184–197): 3x3 grid of small square buttons, the chosen one highlighted with `bg-primary border-primary`. Default selection in mockup = bottom-right (last button)
- **Opacity slider** (lines 198–202): label "透明度", range 10–100, value display "50%"

## Rendering

Use `dart:ui` `Canvas.drawParagraph` (or `image` package's text utilities) to overlay text on the source `Uint8List`. Margin = 16px from the chosen edge anchor. Render inside the same isolate that produces the final image.

```dart
Future<Uint8List> applyWatermark(
  Uint8List source,
  WatermarkConfig config,
) async {
  final image = await decodeImage(source);
  final canvas = createCanvas(image.width, image.height);
  canvas.drawImage(image, Offset.zero);

  final tp = TextPainter(
    text: TextSpan(text: config.text, style: TextStyle(
      color: Colors.white.withOpacity(config.opacity),
      fontSize: config.fontSize,
      fontFamily: 'Inter',
      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
    )),
  )..layout();

  final pos = computeAnchor(config.anchor, image.size, tp.size, margin: 16);
  tp.paint(canvas, pos);
  return await canvasToBytes();
}
```

## Edge cases

| Case | Behavior |
|------|----------|
| Empty text | Treat as "watermark disabled" even if toggle is on |
| Text wider than image | Auto-shrink font to fit (min 8px), then truncate with ellipsis |
| Source has alpha edges (PNG) | Compose against transparent — let downstream encode handle |
| Very dark backgrounds | Always render with white + black shadow for contrast |

## Acceptance Criteria

- [ ] Toggle ON shows the watermark in preview; OFF removes it
- [ ] Picking a different position anchor moves the text live
- [ ] Opacity slider adjusts text alpha live
- [ ] Font size choice (or numeric value) reflects in output
- [ ] Watermark appears on the saved file at the chosen position
- [ ] Watermark is applied exactly once (no double-stacking)

## Definition of Done

- Unit tests for `computeAnchor` math at all 9 positions
- Widget test for the toggle + position picker
- Snapshot test: render a known image with a known watermark config and compare bytes

## Out of Scope

- Image watermarks (logo / sticker)
- Multiple watermarks on a single export
- Custom font upload
- Color picker (white + shadow only in MVP)

## Dependencies

- Requires: `05-08-base-architecture` (theme + Riverpod scaffolding)
- Pairs with: `05-08-export-multiplatform` (export pipeline calls `applyWatermark` before encoding)

## References

- Total PRD §5.5 水印功能
- UI: `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`
- Spec: `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/type-safety.md`
