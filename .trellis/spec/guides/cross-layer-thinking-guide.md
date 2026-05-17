# Cross-Layer Thinking Guide

> **Purpose**: Think through data flow across layers before implementing.

---

## The Problem

**Most bugs happen at layer boundaries**, not within layers.

Common cross-layer bugs:
- API returns format A, frontend expects format B
- Database stores X, service transforms to Y, but loses data
- Multiple layers implement the same logic differently

---

## Before Implementing Cross-Layer Features

### Step 1: Map the Data Flow

Draw out how data moves:

```
Source → Transform → Store → Retrieve → Transform → Display
```

For each arrow, ask:
- What format is the data in?
- What could go wrong?
- Who is responsible for validation?

### Step 2: Identify Boundaries

| Boundary | Common Issues |
|----------|---------------|
| API ↔ Service | Type mismatches, missing fields |
| Service ↔ Database | Format conversions, null handling |
| Backend ↔ Frontend | Serialization, date formats |
| Component ↔ Component | Props shape changes |

### Step 3: Define Contracts

For each boundary:
- What is the exact input format?
- What is the exact output format?
- What errors can occur?

---

## Common Cross-Layer Mistakes

### Mistake 1: Implicit Format Assumptions

**Bad**: Assuming date format without checking

**Good**: Explicit format conversion at boundaries

### Mistake 2: Scattered Validation

**Bad**: Validating the same thing in multiple layers

**Good**: Validate once at the entry point

### Mistake 3: Leaky Abstractions

**Bad**: Component knows about database schema

**Good**: Each layer only knows its neighbors

### Mistake 4: Implicit unit semantics for shared numeric values

**Bad**: A shared field like `centerOffset` is treated as **source-image
pixels** in the renderer / controller but as **widget pixels** in the
preview overlay and gesture detector. When the preview canvas size ≠
source image size (the typical case), the preview shows one offset and
the export produces another — preview ≠ export bug, even though every
layer "looks correct" in isolation.

**Symptoms**: Pinch-and-drag tracks the finger in preview but the
exported PNG is offset by a different amount; a "1px" preview adjustment
shifts the export by N pixels; reproducing in tests works only if you
happen to size the preview surface identically to the source.

**Good**: Pick **one canonical unit** at the domain layer (typically
source pixels, or a normalized `0..1` value). Convert at every boundary
that crosses a coordinate system, and document the unit in the field's
doc-comment. The renderer's coordinate space is usually canonical for
WYSIWYG previews — make every other layer convert to it.

```dart
/// User-controlled pan of the replacement image, in **source-image
/// pixels**. The preview overlay must convert this to widget pixels via
/// (sourceCellSize / widgetCellSize) before applying it to Positioned;
/// the gesture detector must convert widget-pixel focal-point deltas
/// back to source pixels before storing.
final CenterOffset centerOffset;
```

**Prevention**: When the same value flows through both a rasterizer and
a Flutter widget, ask "is the widget rendering area the same size as
the source pixels this value describes?" If no — and it usually isn't —
add a conversion at the widget boundary, not at every read site.

### Mistake 5: Reflexively forbidding `core/` from importing plugins

**Bad** (strict layering, but worse outcome): "`core/` must not import any platform plugin because plugin types belong in `data/datasources/`." So every datasource that throws a typed plugin exception (`GalException`, `PlatformException`, `FileSystemException`) embeds its own zh-CN translation strings, duplicating the same five sentences across six datasources. Updating the wording becomes a multi-file edit; consistency drifts.

**Good** (layered trade-off): `core/errors/user_facing_messages.dart` may import a plugin package **only when** it provides a typed error → zh-CN translation helper that all datasources of that plugin should use uniformly. Example:

```dart
// lib/core/errors/user_facing_messages.dart
import 'package:gal/gal.dart';  // ✅ acceptable layer breach

String gallerySaveFailureMessage(GalException e) {
  return switch (e.type) {
    GalExceptionType.accessDenied => '保存失败：需要相册权限，请在设置中开启',
    GalExceptionType.notEnoughSpace => '保存失败：存储空间不足',
    GalExceptionType.notSupportedFormat => '保存失败：不支持的图片格式',
    GalExceptionType.unexpected => '保存失败：${describeCause(e)}',
  };
}
```

**Why this is the right trade-off**: a single translation table is dramatically more maintainable than scattering plugin-specific strings across datasources. The cost (one `core/` file knows about `gal`) is contained: the import is in **one** file, all consumers route through it, and replacing the plugin later means updating one file.

**Where the strict rule still applies**: domain entities, repository interfaces, presentation widgets — these must remain plugin-free. The relaxation is **only** for `core/errors/user_facing_messages.dart` (or similarly-purposed translation tables) where the plugin's typed error enum is the input.

**See also**: `frontend/error-handling.md` → "Pattern: Plugin-specific translation tables" for the full pattern.

### Mistake 6: Shape-proxy anti-pattern in clamp / transform APIs

**Bad**: A clamp / transform / projection helper takes geometry from the
**wrong-typed object** as a "shape proxy" because the caller doesn't
know the real geometry. Typical justification (always wrong): "we'll
clamp again at the widget side."

```dart
// In a Riverpod notifier:
final clamped = clampCellOffset(
  offset: offset,
  imageWidth: current.image.width,
  imageHeight: current.image.height,
  cellWidth: current.image.width,   // ❌ image used as cell-shape proxy
  cellHeight: current.image.height,
  userScale: current.scale,
);
```

**Symptoms**: At default `userScale = 1.0`, `coverScaleFactor` becomes
`max(imageW/imageW, imageH/imageH) = 1.0`, so `maxDx = (imageW × 1.0 -
imageW) / 2 = 0` (and same for Y). **Any** offset clamps back to zero;
gesture-driven pan looks broken to the user ("I drag, nothing moves").
The bug is **hidden at non-default scales** (e.g. `scale=2.0` produces
plausible-looking maxD values), so unit tests that only cover
`scale=2.0` pass while the production path is dead.

**Good**: Make the real geometry an **explicit required parameter** of
the API. The caller that knows the real geometry (typically the widget
reading `layout.rects[i].width/height`, or the layout pass that owns the
target rectangles) supplies it:

```dart
void setCellOffset(int cellIndex, CellOffset offset, {
  required int cellWidth,   // ✅ source-pixel cell dimensions,
  required int cellHeight,  //    matching renderer's layout.rects[i]
}) {
  final clamped = clampCellOffset(
    offset: offset,
    imageWidth: current.image.width,
    imageHeight: current.image.height,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    userScale: current.scale,
  );
  ...
}
```

**Why proxies fail**: The image and the cell are **two different
rectangles**. Cover-fit math (`coverScaleFactor = max(cellW/imageW,
cellH/imageH)`) is meaningful only when the cell is the **target**
geometry; substituting the image makes the formula compute "the image
cover-fitting itself", which is always `1.0` and degenerates `maxD` to
zero.

**Prevention**: When writing or reviewing a clamp / transform /
projection API, ask:
- Does the formula consume **two** rectangles (source + target)?
- Are both rectangles passed in **explicitly**, or is one defaulted to
  "use the other rectangle's dimensions"?
- If yes to the second — STOP. That default is the bug.

Test guardrail: always cover the **`scale=1.0` + same-aspect** branch
in unit tests. Most pan / offset bugs hide there because higher scales
or non-square aspects mask the proxy.

---

## Checklist for Cross-Layer Features

Before implementation:
- [ ] Mapped the complete data flow
- [ ] Identified all layer boundaries
- [ ] Defined format at each boundary
- [ ] Decided where validation happens
- [ ] If wrapping a Flutter / Dart plugin: planned a library-agnostic DTO so plugin types stay in `data/datasources/` (see `frontend/directory-structure.md` → "Pattern: Data-source DTO isolation")
- [ ] If a feature is unavailable on some platforms: planned the **three-layer defense** (UI hide + repository typed failure + datasource throw — see `frontend/directory-structure.md` → "Pattern: Platform-aware datasource dispatch")
- [ ] If writing a CPU-heavy image / encode function in `data/` that callers will run via `compute()`: confirmed the function imports **no `dart:ui`** (see `frontend/directory-structure.md` → "Pattern: Isolate-safe rasterizer in `data/`")
- [ ] If exposing UI helpers (`IconData`, `Color`, `TextStyle`, ...) for a `domain/` entity or enum: planned a **`presentation/`-side extension** so `domain/` stays framework-free (see `frontend/directory-structure.md` → "Pattern: Framework-free domain entities and enums")
- [ ] If a shared numeric value (offset, size, scale) flows through a rasterizer **and** a Flutter widget: documented the canonical unit (source pixels / widget pixels / normalized) in the field's doc-comment, and identified every boundary that must convert. The preview overlay and the renderer must agree, or preview ≠ export.
- [ ] If writing / changing a clamp / transform / projection API that takes geometry (cell size, viewport size, target rect): every geometric input is an **explicit required parameter** — no "use the other rectangle's dimensions as a proxy" defaults. Pair this with a unit test at `scale=1.0` + same-aspect to catch the cover-fit degenerate case (see "Mistake 6: Shape-proxy anti-pattern" above).

After implementation:
- [ ] Tested with edge cases (null, empty, invalid)
- [ ] Verified error handling at each boundary
- [ ] Checked data survives round-trip
- [ ] Verified no plugin imports leak past `data/datasources/` (grep the repository / domain / presentation files for plugin package names)

---

## When to Create Flow Documentation

Create detailed flow docs when:
- Feature spans 3+ layers
- Multiple teams are involved
- Data format is complex
- Feature has caused bugs before
