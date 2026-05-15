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

## Convention: Cap content with `Breakpoints.maxContentWidth`

**What**: Every top-level screen wraps its body in `ConstrainedBox(maxWidth: Breakpoints.maxContentWidth)` (currently `1200`) + `Center`. Cards do not stretch to fill ultra-wide windows.

**Why**: On a 27-inch monitor, a feature card that stretches to 2000 dp wide looks broken — text becomes one long line, hit targets become absurdly large. A 1200 dp cap gives the layout a comfortable upper bound while still letting tablets use double-pane mode.

**How to apply**:

```dart
@override
Widget build(BuildContext context) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: Breakpoints.maxContentWidth,
      ),
      child: _body(),
    ),
  );
}
```

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
   - expanded / large → use `Row(Expanded(canvas), SizedBox(width: 380, XxxControlsPanel))`

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
        ? Row(children: [
            Expanded(child: _canvas()),
            const SizedBox(
              width: _kStitchControlsPanelWidth, // 380
              child: SingleChildScrollView(child: StitchControlsPanel()),
            ),
          ])
        : Column(children: [
            Expanded(child: _canvas()),
            const StitchControlsSheet(),
          ]),
  );
}
```

### Convention: side panel is **380 dp** wide

Both editor screens use `_kXxxControlsPanelWidth = 380` for visual rhythm consistency. If a future design wants a fluid panel (e.g. 30% of canvas), swap `SizedBox(width: 380)` for `Expanded(flex: 1)` or use a `LayoutBuilder` ratio — but do this in **one** place, not piecemeal per screen.

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
| home_screen | 3-col feature grid | 3-col | 4-col | 4-col, capped @ 1200 |
| export_screen | single-column | single-column | two-column (preview / config) | same, capped @ 1200 |
| stitch_editor / grid_editor | canvas + bottom sheet | same as compact | canvas + right panel (380 dp) | same, capped @ 1200 |

When adding a new top-level screen, fill in this table for it.

---

## Common Mistakes

### Gotcha: forgetting `Center` outside `ConstrainedBox`

`ConstrainedBox(maxWidth: 1200)` alone doesn't horizontally center — it just caps the max width. Without `Center`, the body left-aligns on a 1920 dp monitor with 720 dp of empty space on the right.

```dart
// ❌ Wrong — left-aligned on wide screens
ConstrainedBox(
  constraints: BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
  child: body,
)

// ✅ Correct
Center(
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
    child: body,
  ),
)
```

### Gotcha: panel content must scroll independently

On expanded/large widths the side panel can be **taller** than the viewport. Always wrap the panel in `SingleChildScrollView` (or use a `ListView`):

```dart
SizedBox(
  width: 380,
  child: SingleChildScrollView(child: StitchControlsPanel()),
)
```

Otherwise the panel content overflows and Flutter throws "RenderBox overflow by N pixels".
