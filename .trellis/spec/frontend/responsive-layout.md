# Responsive Layout

> How screens adapt to phone / tablet / desktop window sizes.

---

## Overview

This project targets six platforms with very different window sizes (iOS / Android phones, macOS / Windows / Linux desktops, Web). Layouts that hard-code a phone-portrait assumption stretch awkwardly on a 27-inch monitor and feel cramped on a phone landscape. Responsive layout is non-optional.

Anchor: **Material 3 Window Size Class** (compact / medium / expanded / large).

Authoritative source: `lib/core/constants/breakpoints.dart`.

---

## Convention: All breakpoint logic goes through `WindowSizeClass`

**What**: Every responsive branch reads `windowSizeClassOf(context)` (or `windowSizeClassFromWidth(width)` in tests) and switches on the `WindowSizeClass` enum. Never read `MediaQuery.sizeOf(context).width` directly inside `build()` and compare against magic numbers.

**Why**: A naked `width < 600` check fragments the breakpoint convention — different widgets pick different thresholds, regressions are silent, and there is no compiler help when a new size class is added. The enum forces every site to handle every bucket (or use `||` to group them) and keeps the breakpoint table in one file.

**How to apply**:

```dart
// ✅ Correct — enum dispatch
final crossAxisCount = switch (windowSizeClassOf(context)) {
  WindowSizeClass.compact || WindowSizeClass.medium => 3,
  WindowSizeClass.expanded || WindowSizeClass.large => 4,
};

// ❌ Wrong — magic number, drifts from convention
final width = MediaQuery.sizeOf(context).width;
final crossAxisCount = width < 840 ? 3 : 4;
```

**Tests use `windowSizeClassFromWidth`** so they don't need a `BuildContext`:

```dart
expect(windowSizeClassFromWidth(599), WindowSizeClass.compact);
expect(windowSizeClassFromWidth(600), WindowSizeClass.medium);
expect(windowSizeClassFromWidth(1200), WindowSizeClass.large);
```

---

## Convention: Top-level screens fill the available width

**What**: Top-level screens (home / stitch editor / grid editor / export) **do not** cap their body width. The screen body mounts directly on `SafeArea` and tracks the container width on every size class. There is no `Breakpoints.maxContentWidth` constant; the legacy `Center + ConstrainedBox` wrapper is **removed**.

**Why**: Earlier we capped every screen at 1200 dp so cards wouldn't stretch absurdly on a 4K monitor. In practice the cap made the opposite problem worse: when a user dragged the window wider (1600 / 1920 / 2560 dp), the content **stopped tracking the window** and parked itself in a 1200 dp island with growing whitespace on either side. That looks like the app is broken, especially in the editor screens where the user expects more canvas room when they give the app more space.

The cap was solving for "cards look weird if too wide" — but feature cards already self-balance via `Expanded(flex: 1)` inside a `Row`, and editor canvases visibly benefit from extra width. The cap was over-cautious; removing it lets the layout actually use the surface the user provides.

**How to apply**:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: SafeArea(child: _body()), // no Center + ConstrainedBox wrapper
  );
}
```

If a *specific* component (e.g. a Save CTA on the export screen) feels too wide on ultra-wide windows, cap **that component** with a local `ConstrainedBox` — don't bring back the global cap.

---

## Pattern: Sheet → Panel dual-form extraction

**Problem**: A screen needs a control surface (sliders, switches, swatches). On **phone**, the surface lives in a bottom modal sheet (slides up from below, dismissible). On **tablet / desktop**, the same controls need to dock to the right side of the canvas as a persistent panel — no Material elevation, no rounded corners, just a column.

**Naive bad solutions**:
1. Duplicate the controls in two files (sheet + panel) — drift in 6 months
2. Pass a `bool isSidePanel` flag into the sheet — `Material(elevation: isSidePanel ? 0 : 8)` everywhere; readability rots fast

**Correct pattern**:

1. **Extract** the control Column into `XxxControlsPanel` — **no chrome**: no `Material`, no rounded corners, no outer padding. Caller decorates.
2. **Keep** the existing `XxxControlsSheet` as a **thin wrapper** that adds the Material chrome and delegates to the panel. Existing tests + callers don't break.
3. In the screen, switch on `WindowSizeClass`:
   - compact / medium → use `XxxControlsSheet` (with Material chrome)
   - expanded / large → use `Row(Expanded(canvas), SizedBox(width: panelWidth, XxxControlsPanel))` where `panelWidth = clamp(380, container * 0.25, 480)` (see the panel-width convention below)

### Example

```dart
// lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart
class StitchControlsPanel extends ConsumerWidget {
  const StitchControlsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // pure controls — no Material, no padding, no rounded corners
    return Column(children: [/* sliders / swatches / segmented */]);
  }
}

// lib/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart
class StitchControlsSheet extends StatelessWidget {
  const StitchControlsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Material chrome wraps the panel
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: const StitchControlsPanel(),
      ),
    );
  }
}

// lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart
@override
Widget build(BuildContext context) {
  final sizeClass = windowSizeClassOf(context);
  final isSideDocked = sizeClass == WindowSizeClass.expanded ||
                       sizeClass == WindowSizeClass.large;

  return Scaffold(
    body: isSideDocked
        ? LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = (constraints.maxWidth * 0.25)
                  .clamp(380.0, 480.0);
              return Row(children: [
                Expanded(child: _canvas()),
                SizedBox(
                  width: panelWidth,
                  child: const SingleChildScrollView(
                    child: StitchControlsPanel(),
                  ),
                ),
              ]);
            },
          )
        : Column(children: [
            Expanded(child: _canvas()),
            const StitchControlsSheet(),
          ]),
  );
}
```

### Convention: side panel width is fluid in `[380, 480]` dp

Both editor screens compute the docked panel width as `clamp(380, container * 0.25, 480)` — a quarter of the available row width, clamped to a 380 dp lower bound (readability of the longest slider row) and a 480 dp upper bound (preserves visual primacy for the canvas on ultra-wide windows). The compact / medium layouts still use the bottom `XxxControlsSheet`; this convention only applies to expanded / large.

**How to apply**:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final panelWidth = (constraints.maxWidth * 0.25).clamp(380.0, 480.0);
    return Row(
      children: [
        const Expanded(
          child: SingleChildScrollView(child: XxxCanvas()),
        ),
        SizedBox(
          width: panelWidth,
          child: const SingleChildScrollView(child: XxxControlsPanel()),
        ),
      ],
    );
  },
)
```

**Why `LayoutBuilder` + `SizedBox` instead of `Flexible`-based heuristics**: when a `Row` mixes `Expanded(canvas)` and `Flexible(panel, minWidth, maxWidth)`, the panel gets squeezed by the `Expanded` competing for the same axis — the panel often collapses to its minimum even when there is room. Computing the panel width up front from the row's `maxWidth` sidesteps that fight entirely, makes the math easy to test, and keeps the panel reusable across editors (`stitch_editor_screen.dart`, `grid_editor_screen.dart`).

### Convention: panel has **no** outer padding

The panel widget is bare; the **caller** wraps with appropriate padding (compact: via `ListView.padding`; expanded: via `Padding(padding: ...)` around the `Row`). This keeps the panel reusable across surfaces without leaking chrome assumptions.

### Convention: Caller decoration variants

**What**: The "panel is bare" rule covers *padding* — the panel never paints its own padding so the caller can decide the visual rhythm. The same caller-decides principle extends to **all** outer chrome (background fill, outline, rounded corners, elevation): if a caller wants to anchor the side panel inside a visible surface slab, it wraps the panel itself; if it wants the panel to float chrome-free, it doesn't. **The panel widget never paints its own chrome either way.**

**Why**: Different editors have different visual identities. The grid editor's side panel is a docked tool surface and reads better when visually anchored by a contained slab that fills the row's full height; the stitch editor's side panel reads better floating against the canvas background. Both call sites use the *same* bare panel widget — duplicating panels just to add / remove chrome would drift in six months.

**How to apply** — pick one of these caller patterns per editor:

```dart
// 1) Bare caller (stitch editor style) — panel floats against the page bg
SizedBox(
  width: panelWidth,
  child: const SingleChildScrollView(child: StitchControlsPanel()),
)

// 2) Surface-chrome caller (grid editor style) — panel sits inside a
//    `surfaceContainerLow` slab with an `outlineVariant` outline and
//    16 dp rounded corners. Stretched by Row(stretch) to the row's
//    full height so the chrome anchors the column top-to-bottom.
SizedBox(
  width: panelWidth,
  child: Container(
    key: kGridControlsPanelChromeKey,        // optional — for tests
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,            // keep scroll inside corners
    child: const SingleChildScrollView(
      padding: EdgeInsets.all(16),           // padding inside scroll view
      child: GridControlsPanel(),
    ),
  ),
)
```

**Current call-site decisions** (kept in sync with each editor's
class-level doc-comment):

| Editor | Side-panel chrome |
|---|---|
| `grid_editor_screen.dart` | surface chrome (pattern 2 above) |
| `stitch_editor_screen.dart` | bare (pattern 1 above) |

When adding a third editor, pick whichever pattern matches the visual
intent, then record the decision in this table.

**Don't**: Add the chrome inside the panel widget itself (`GridControlsPanel`, `StitchControlsPanel`). That breaks the "panel is bare" rule and forces a future bare-panel use-case to either fork the panel or hack around the chrome.

---

## Pattern: Editor body — height-first `Column` skeleton (single-column + side-panel variants)

**Problem**: An editor screen has a fixed-aspect canvas (e.g. `AspectRatio(1)`) plus a tall controls surface. Naively stacking them inside a `ListView`, or wrapping the canvas in `SingleChildScrollView` and letting `AspectRatio` size by width, makes the canvas claim `maxWidth` and become a square as tall as the column is wide — the controls fall *off-screen* (compact) or the canvas grows taller than the viewport on ultra-wide windows (expanded / large) and the page must scroll just to see the canvas. Both violate the editor mental model where the canvas and "what I can change" should be visible together without scrolling the page.

**Solution**: keep the **same height-first principle** across every size class. The canvas always lives inside an `Expanded` slot of a `Column` and is sized by `Center + AspectRatio(1)`; the controls live below it on phones (`Flexible(loose) + SingleChildScrollView`) and dock to the right on tablets / desktops (`SizedBox(width: panelWidth, SingleChildScrollView)` inside a `Row(crossAxisAlignment: stretch)`).

### Single-column variant (compact / medium)

```dart
return Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), // 96 = FAB clearance
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Canvas claims the leftover height. Center + AspectRatio(1)
      // turns the Expanded slot into a centered square.
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: const GridPreviewCanvas(),
          ),
        ),
      ),
      if (sourceTooSmall) ...[
        const SizedBox(height: 12),
        _SourceSizeWarning(...),
      ],
      const SizedBox(height: 16),
      // Controls slot: sizes to its content; if content > remaining
      // space, scrolls inside instead of growing the column.
      Flexible(
        fit: FlexFit.loose,
        child: SingleChildScrollView(
          child: const GridControlsPanel(),
        ),
      ),
    ],
  ),
);
```

### Side-panel variant (expanded / large)

When the viewport is wide enough to dock the controls as a side panel, apply the same height-first idiom to the **left column** of a `Row` — *the controls just move from a `Flexible(loose)` slot inside the column to a `SizedBox`-bounded column on the right of a row*.

```dart
return Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final available = (constraints.maxWidth - 16).clamp(0.0, double.infinity);
      final panelWidth = (available * 0.25).clamp(380.0, 480.0);
      return Row(
        // Stretch the row's children to the row's full height so the
        // left column inherits a bounded vertical extent. Without
        // stretch the column's height becomes unbounded and
        // AspectRatio(1) collapses back onto width — the canvas would
        // grow taller than the viewport on ultra-wide windows.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: const GridPreviewCanvas(),
                    ),
                  ),
                ),
                if (sourceTooSmall) ...[
                  const SizedBox(height: 12),
                  _SourceSizeWarning(...),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: panelWidth,
            child: const SingleChildScrollView(
              child: GridControlsPanel(),
            ),
          ),
        ],
      );
    },
  ),
);
```

**Why `Row(crossAxisAlignment: stretch)` is load-bearing**: a `Row` without `stretch` hands each child an unbounded height. Feeding that into `Expanded > Column > Expanded(Center(AspectRatio(1)))` collapses back into a width-first square — the canvas size becomes `leftColWidth × leftColWidth`, which on a 1920×1080 ultra-wide window is ~1400×1400 dp and overflows the ~980 dp tall viewport. With `stretch` the left column's height equals the Row's height (= `LayoutBuilder.maxHeight`), and `AspectRatio(1)` resolves to `min(leftColWidth, rowHeight)` — the canvas never exceeds the container's height.

**Why the left column drops `SingleChildScrollView`**: with `stretch` giving the column a finite height, the only piece that could overflow is the warning banner (a fixed-height one-line strip). The page no longer needs an outer scroll — keep the canvas pinned to its `Expanded` slot and the warning stuck just below it. The controls panel on the right keeps its own `SingleChildScrollView` because the parameter cards can still overflow the viewport height when there are many of them.

**Symmetry summary**: in both variants the canvas lives inside `Expanded(Center(AspectRatio(1, ...)))`. The only structural difference is **where the controls live** — under the canvas in a `Flexible(loose)` slot of the same column (compact / medium), or to the right of the canvas as a `SizedBox`-bounded column of a row (expanded / large). The height-first sizing contract is identical.

**Sizing contract for the canvas widget**: when this skeleton is in play, the canvas widget itself **must not** wrap its content in an `AspectRatio` — the *caller* supplies the aspect constraint via `Center + AspectRatio(1)`. A canvas widget that locks its own aspect internally breaks the height-first pattern because `AspectRatio` always picks width-first when both axes are bounded. Spell this out in the canvas widget's class doc-comment so future callers don't accidentally double-wrap.

**Where this is used**: `grid_editor_screen.dart` (both compact / medium and expanded / large branches). The `stitch_editor_screen.dart` compact path uses a different shape (`Column + Expanded(canvas) + StitchControlsSheet`) because it docks a Material sheet rather than a bare panel — the height-first principle still applies.

---


## Test pattern: Responsive widget tests

To test responsive behavior, override the viewport via `tester.view.physicalSize` + `tester.view.devicePixelRatio`, **not** `MediaQuery` wrapper — because `Column + Expanded` screens rely on the actual paint surface size.

```dart
Future<void> _setViewportSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

testWidgets('expanded width docks panel on the right', (tester) async {
  await _setViewportSize(tester, const Size(1280, 800));
  await tester.pumpWidget(/* ... */);
  expect(find.byType(StitchControlsPanel), findsOneWidget);
  expect(find.byType(StitchControlsSheet), findsNothing);
});
```

For simple list-column-count tests where `MediaQuery` is enough (no `Column + Expanded`), wrap with `MediaQuery(data: MediaQueryData(size: Size(width, 800)), child: ...)`.

---

## Responsive behavior table (current screens)

| Screen | compact (<600 dp) | medium (600-840 dp) | expanded (840-1200 dp) | large (≥1200 dp) |
|---|---|---|---|---|
| home_screen | 3-col feature grid | 3-col | 4-col | 4-col, fluid (fills container) |
| export_screen | single-column | single-column | two-column (preview / config) | same, fluid (fills container) |
| stitch_editor | scrollable canvas + bottom `StitchControlsSheet` | same as compact | canvas + right panel ∈ [380, 480] dp | same, fluid (fills container); side panel ∈ [380, 480] dp |
| grid_editor | height-first `Column`: `Expanded(Center(AspectRatio(1, canvas)))` + `Flexible(loose, panel)` (see "Editor body — height-first Column skeleton" pattern) | same as compact | height-first `Row(stretch)`: left column = `Expanded(Column(stretch) > Expanded(Center(AspectRatio(1, canvas))))` (square = `min(leftColW, rowHeight)`) + right panel ∈ [380, 480] dp wrapped in a `surfaceContainerLow` + `outlineVariant` 16 dp rounded chrome that fills the row height, scrolls internally | same, fluid (fills container); left canvas stays height-first, side panel ∈ [380, 480] dp with the surface chrome scrolls internally |

When adding a new top-level screen, fill in this table for it.

---

## Common Mistakes

### Gotcha: `ConstrainedBox` alone never centers — it just caps

If you ever need to cap the width of a *specific* component (e.g. a CTA on an ultra-wide window) — **not** an entire screen — wrap the `ConstrainedBox` in `Center`. A bare `ConstrainedBox(maxWidth: …)` parks its child at the left edge with growing whitespace on the right, which on a 1920 dp monitor looks like a layout bug.

```dart
// ❌ Wrong — left-aligned on wide screens
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 600),
  child: localCta,
)

// ✅ Correct
Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 600),
    child: localCta,
  ),
)
```

(Top-level screens don't need this — they fill the container per the "Top-level screens fill the available width" convention above.)

### Gotcha: panel content must scroll independently

On expanded/large widths the side panel can be **taller** than the viewport. Always wrap the panel in `SingleChildScrollView` (or use a `ListView`):

```dart
SizedBox(
  width: panelWidth, // clamp(380, container * 0.25, 480)
  child: const SingleChildScrollView(child: StitchControlsPanel()),
)
```

Otherwise the panel content overflows and Flutter throws "RenderBox overflow by N pixels".

### Gotcha: `LayoutBuilder.constraints.maxHeight` is `∞` inside a `SingleChildScrollView`

When a widget that uses `LayoutBuilder` is placed inside a vertically-scrolling parent (`SingleChildScrollView`, `ListView`, or any other widget that gives an unbounded main-axis constraint), `constraints.maxHeight` is `double.infinity`. Naively using it in math — `displayHeight = constraints.maxHeight` or `aspectRatio * constraints.maxHeight` — yields `Infinity` / `NaN` paint sizes and crashes at layout time.

For **aspect-locked content** (preview canvas, image, video, anything sized by `naturalWidth / naturalHeight`), fall back to the cross-axis bound when the main axis is unbounded:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final aspect = naturalWidth / naturalHeight;
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : naturalWidth;          // last-resort: natural size
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : maxWidth / aspect;     // ← derive from width when parent is unbounded vertically

    var w = maxWidth;
    var h = w / aspect;
    if (h > maxHeight) { h = maxHeight; w = h * aspect; }
    return SizedBox(width: w, height: h, child: /* aspect-locked content */);
  },
)
```

**Where this hits in this project**: `stitch_preview_canvas.dart`. The compact layout puts the canvas in a `SingleChildScrollView`, so the preview's `LayoutBuilder` sees `maxHeight = ∞`. The expanded / large two-column layout gives the canvas a bounded `Expanded` parent, so the same widget works without the fallback — but writing the fallback once keeps the widget reusable across both layouts. The general rule applies to any future editor that follows the same compact-scrollable + expanded-docked split.

### Gotcha: use `Flexible(loose)` — **not** `Expanded` — for the controls slot in a height-first `Column`

In the [height-first `Column` skeleton](#pattern-editor-body--height-first-column-skeleton-single-column--side-panel-variants), the controls slot must be a `Flexible(fit: FlexFit.loose)`-wrapped `SingleChildScrollView`. **Don't** wrap it in `Expanded`:

```dart
// ❌ Wrong — Expanded forces the slot to claim ALL remaining height,
// inflating a short controls panel with a gap between the canvas and
// the first parameter card. The "canvas + first card" visual cluster
// breaks; the FAB also overlaps the bottom of an inflated panel.
Expanded(
  child: SingleChildScrollView(child: GridControlsPanel()),
),

// ✅ Correct — Flexible(loose) lets the panel size to its intrinsic
// content height; if the content overflows the remaining space, the
// inner SingleChildScrollView scrolls inside the slot.
Flexible(
  fit: FlexFit.loose,
  child: SingleChildScrollView(child: GridControlsPanel()),
),
```

`Flexible(tight)` (the default `fit:` for `Flexible`) behaves like `Expanded` — also wrong here. The `fit: FlexFit.loose` is the load-bearing part of this gotcha.

**Symptom if you forget**: A "floating" controls panel detached from the canvas by an awkward whitespace strip, or the FAB sitting on top of the panel's last parameter card. Both look like bugs to the user.
