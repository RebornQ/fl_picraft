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
| stitch_editor / grid_editor | canvas + bottom sheet | same as compact | canvas + right panel ∈ [380, 480] dp | same, fluid (fills container); side panel ∈ [380, 480] dp |

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
