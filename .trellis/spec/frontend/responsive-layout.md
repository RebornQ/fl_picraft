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
//
// Note: this example shows the canonical Sheet → Panel dispatch. The
// real stitch_editor's `isSideDocked` branch wraps `StitchControlsPanel`
// inside a Column whose top half is the vertical
// `StitchVerticalImageList` (see the editor's class-level doc-comment
// and the responsive behavior table). The Sheet → Panel pattern itself
// is unchanged — what varies is the composition inside the docked
// `SizedBox`.
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

### Variant: tri-form (sheet + inline + panel) when compact needs both peek and full-screen modes

The base Sheet → Panel pattern above assumes compact / medium share a **single** form (modal sheet). When compact needs the controls to be **togglable inline alongside the canvas** (not modal — the user wants live parameter feedback while keeping the canvas visible), introduce a **third** form: an inline container that squeezes the canvas via `Expanded`.

**Trigger**: the user wants to adjust parameters while watching the preview update in real time, and the modal sheet's "pop up → tweak → dismiss" loop feels too disruptive. Typical signal: the user complains the modal sheet "covers half the canvas" or "I have to keep reopening it".

**Form mapping**:

| size class | form | widget | mounted-state behavior |
|---|---|---|---|
| compact (<600 dp) | **inline container** (new) | `StitchInlineControlsContainer` | toggled by a bottom-bar chip; collapsed by default; mounts the panel between canvas and bottom bar; canvas's `Expanded` shrinks when panel expands |
| medium (600–840 dp) | bottom sheet | `StitchControlsSheet` | always docked under canvas |
| expanded / large | right dock | `StitchControlsPanel` (raw) | always docked next to canvas |

**Inline container contract** (compact form):

1. **Bounded parent → bounded child.** Wrap the panel in `SizedBox(height: kInlineHeight)` (e.g. `200`). The panel must implement the [`LayoutBuilder` dual-mode pattern](#pattern-same-widget-across-bounded--unbounded-parents-via-layoutbuilder-dual-mode) so the same `XxxControlsPanel` works inline (bounded) and docked (unbounded).
2. **No outer `SingleChildScrollView`.** The inline container itself must NOT wrap the panel in a `SingleChildScrollView` — that would scroll the TabBar header out of view. Tab content scrolls inside each `TabBarView` child instead (each Tab content widget owns its own `SingleChildScrollView`).
3. **Visibility via `StateProvider<bool>`.** Drive show/hide from a dedicated provider (e.g. `xxxControlsInlineVisibleProvider`); the toggle chip flips it. Don't persist — every fresh editor mount lands collapsed.
4. **Toggle button visual state.** When the panel is expanded, the chip's visual changes from `FilledButton.tonalIcon` (default) to `FilledButton.icon` (primary fill, "selected"). Tooltip flips accordingly ("展开参数" ⇄ "收起参数").
5. **Animation contract.** `AnimatedSize(duration: 250ms, curve: Curves.easeInOutCubicEmphasized)` for height; nested `AnimatedSwitcher` with `FadeTransition` for cross-fade between expanded and `SizedBox.shrink()`. Use distinct `ValueKey`s for the two children so the AnimatedSwitcher actually cross-fades (default `null` keys skip the transition).
6. **Mount-only-when-expanded.** When the provider is `false`, the child is `SizedBox.shrink()`; the `XxxControlsPanel` (and its `TabController`) is released. Next expansion rebuilds — matches the "no persisted tab" convention.

**Why the inline form earns its own widget instead of reusing `XxxControlsSheet`**:

- The sheet's `Material(elevation: 8, borderRadius: vertical-top)` chrome is sized for a draggable modal — too heavy as a flush-mounted panel.
- The inline form needs an explicit fixed height; the sheet sizes itself by its child + `DraggableScrollableSheet` snap stops.
- The chip's selected-vs-default visual state is a fourth axis the sheet's open/close gesture doesn't have.

**Where this hits in this project**: `05-26-compact` task — `StitchInlineControlsContainer` replaces `showStitchParamsSheet` on compact. The sheet function is kept (not deleted) so future entry points can still invoke it modally if needed; the bottom-bar chip just stops calling it.

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

| Editor | compact / medium | expanded / large |
|---|---|---|
| `grid_editor_screen.dart` | inline panel + surface chrome inside an `Expanded` slot of the body `Column` — same `surfaceContainerLow` + `outlineVariant` + 16 dp rounded decoration as the side panel below | side panel + surface chrome (pattern 2 above) |
| `stitch_editor_screen.dart` | bottom `StitchControlsSheet` (Material sheet chrome — different shape, not an inline panel) | bare side column (pattern 1 above) — but the `SizedBox` contains a `Column` that splits 50/50 between `StitchVerticalImageList` (top) and `SingleChildScrollView(StitchControlsPanel)` (bottom), so the same `[380, 480]` dp slot hosts both the image list and the parameter controls |

**Note**: `grid_editor` reuses the **same** chrome decoration across all
size classes via a shared `_buildControlsPanelChrome` helper, with a
single `kGridControlsPanelChromeKey`. The two branches are mutually
exclusive, so the key resolves to one widget at a time — tests can
locate the chrome without caring about the active size class.

When adding a third editor, pick whichever pattern matches the visual
intent, then record the decision in this table.

**Don't**: Add the chrome inside the panel widget itself (`GridControlsPanel`, `StitchControlsPanel`). That breaks the "panel is bare" rule and forces a future bare-panel use-case to either fork the panel or hack around the chrome.

### Convention: Cap bottom-sheet height on compact / medium with `max(floor, min(screenHeight * ratio, ceiling))` + internal scroll

**What**: When the dual-form panel docks as a bottom `Material` sheet on compact / medium (e.g. `StitchControlsSheet`), wrap the inner panel in a `ConstrainedBox` whose `maxHeight` follows the three-layer clamp:

```dart
final screenHeight = MediaQuery.sizeOf(context).height;
final maxHeight = math.max(
  200.0,                               // floor — protects tiny windows (foldable outer ~400 dp tall)
  math.min(screenHeight * 0.22, 320.0), // ratio + ceiling — keeps the canvas ≥ ~70% of screen
);
```

then nest a `SingleChildScrollView` so panel content can overflow and scroll within the cap instead of pushing the canvas off-screen.

```dart
class StitchControlsSheet extends StatelessWidget {
  const StitchControlsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(
      200.0,
      math.min(screenHeight * 0.22, 320.0),
    );
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: const SingleChildScrollView(
          child: StitchControlsPanel(),
        ),
      ),
    );
  }
}
```

**Why each layer is load-bearing**:

| Layer | What it solves | What happens without it |
|---|---|---|
| `ratio` (`* 0.22`) | Anchors the sheet to a fraction of the actual viewport so it reads consistently across phones / foldables / desktops | A fixed `maxHeight: 320` looks fine on 800 dp phones but reads as a huge slab on a 600 dp foldable outer screen |
| `ceiling` (`320.0`) | Prevents the sheet from inflating on very tall windows where 22% would be 400 dp+ | On a tablet portrait 1366 dp tall, `* 0.22` ≈ 301 dp without a ceiling — the sheet starts feeling like a half-page modal once parameter rows grow |
| `floor` (`200.0`) | Guarantees the sheet stays usable on ultra-short windows (foldable outer ~400 dp, web with browser chrome stealing height); on common phone viewports (h < 909 dp) the floor wins outright | `400 * 0.22 = 88 dp` — the sheet collapses to a strip that can barely show one slider row before scroll |
| Internal `SingleChildScrollView` | Lets panel content overflow gracefully when the user opens a mode that adds more sliders | Without it, Flutter logs a `RenderFlex overflowed by N pixels` and the bottom controls visually vanish |

**Why not `LayoutBuilder`**: a `LayoutBuilder` placed inside a parent that hands the sheet an unbounded vertical extent reports `maxHeight: ∞`, so the math fails. Read the viewport height directly via `MediaQuery.sizeOf(context).height` — it's the actual paint surface height regardless of the parent's intrinsic-height story.

**Why this lives on the sheet wrapper, not the panel**: the same `StitchControlsPanel` is reused by the expanded / large side-panel branch, where the cap doesn't apply (the row's `crossAxisAlignment: stretch` already bounds the panel's height — see the height-first row variant). Keeping the cap on the sheet means the panel itself stays size-agnostic.

**How to apply** (adding a new editor with a bottom sheet):

1. Pick a `ratio` between `0.22` and `0.4`. Closer to `0.22` favors the canvas; closer to `0.4` favors the controls. `stitch_editor` uses `0.22` because the canvas is the primary work surface and the floor (200 dp) keeps the sheet readable on common phone viewports where the ratio branch would otherwise undershoot. **Historical note**: the recommended range was previously `[0.25, 0.4]`; it was widened down to `0.22` under the ADR-lite of `05-20 mobile-control-bar-compact` to reclaim ≥ 48 dp of canvas on compact / medium. Going below `0.22` risks the ratio branch becoming dead code on every realistic phone viewport — keep the lower bound here unless you also lower the floor.
2. Set the `ceiling` to roughly `(maximum reasonable slider count) * (per-row height ~56 dp) + padding`. For 6 sliders + 2 toggle rows + swatch row ≈ 320 dp.
3. Set the `floor` to roughly `(2 essential rows) * 56 dp + padding ≈ 200 dp` — what the user MUST be able to see even on an outer foldable screen.
4. Always wrap the panel in `SingleChildScrollView` inside the `ConstrainedBox`. The cap is a hard ceiling; the scroll lets content extend past it.
5. Do NOT pull the same cap into the side-panel path — that branch is already bounded by `Row(crossAxisAlignment: stretch)` + its own `SingleChildScrollView`.

**Where this is used**: `stitch_editor_screen.dart` (via `StitchControlsSheet`) — `floor=200, ratio=0.22, ceiling=320` (per `05-20 mobile-control-bar-compact` ADR-lite). On common phone viewports (h < 909 dp) the floor wins; the ratio branch governs tablets / desktops / foldables ≥ 909 dp; the ceiling caps at h ≥ 1455 dp. Add a row here when a new editor adopts the pattern.

**Don't**: Reach for `DraggableScrollableSheet` for this **persistent sheet** case. It's intended for user-pullable modals (think Google Maps' place card). Editor controls in this layout are persistent (always docked to the bottom of the column), not dismissible; a `ConstrainedBox + SingleChildScrollView` keeps the contract explicit and avoids accidentally introducing a drag gesture that fights with the slider drags inside.

> **Note**: `DraggableScrollableSheet` **is** the right tool when the controls live inside a **trigger-fired modal** (e.g. tap a chip → `showModalBottomSheet` → user can pull the sheet up to a larger snap, then dismiss). The "don't" above only applies to the **persistent** sheet docked into the screen layout. See the "Mobile-first canvas-dominant editor" pattern below for the modal-trigger variant.

---

## Pattern: Mobile-first canvas-dominant editor (persistent bottom bar + trigger sheets)

**Problem**: On compact phones, an editor needs to maximize the preview canvas (e.g. long-image stitching, photo edit) while still surfacing input management (image list, parameters, export CTA). The classic single-column `Column { strip, Expanded(canvas), bottom-sheet }` shape (see the height-first skeleton pattern and `stitch_editor`'s legacy `medium` branch) eats ~50% of the column on a 360×800 dp phone (a ~208 dp strip + a ~200 dp bottom sheet), leaving the canvas with only ~232 dp / ~29% of the viewport. Users complain the canvas is unusable.

**Solution**: collapse the input-management surfaces (image strip + parameter sheet) into **trigger-fired modal sheets** behind a thin **persistent editor bottom bar**. The bottom bar carries state-aware chips (`[+ 添加]` / `[🖼 N/20]` / `[⚙ 参数]`) — taps open ephemeral `showModalBottomSheet` overlays that reuse the **same** widgets the side-panel branch uses (`StitchVerticalImageList`, `StitchControlsPanel`) — no duplicate code, no drift across size classes. The bar itself docks via the inner `Scaffold.bottomNavigationBar` slot, which naturally stacks above the outer `AppShell` nav bar without any router / shell changes. The export CTA is intentionally **kept out of the bar** — it stays in the AppBar's action slot on compact + medium (and becomes a FAB on expanded / large), so users keep one consistent export position regardless of size class.

Canvas size budget (assuming 800 dp viewport): 800 − 56 (AppBar) − 64 (editor bar) − 80 (AppShell nav bar) = **600 dp / 75%**. On test harnesses without `AppShell`, the canvas is 680 dp / 85%.

### When to apply this pattern

| Trigger | Apply this pattern? |
|---|---|
| Editor on compact phone where canvas is the primary work surface | ✅ Yes |
| Editor on tablet / desktop where vertical space is plentiful | ❌ Use the height-first single-column or side-panel pattern instead |
| Tool surface that should always be visible (e.g. a brush palette in a paint app) | ❌ Use the persistent bottom sheet (cap convention above) — modal sheets are dismissible by definition |
| Sheets that need to coexist with persistent canvas hints / overlays | Mixed — modal sheets dim/disable the canvas while open, so prefer this pattern only if "edit then preview" is the natural flow |

### Composition

```
StitchEditorScreen (compact branch)
└─ Scaffold
   ├─ appBar:                  // keeps the existing export IconButton (same as medium)
   ├─ body: SafeArea > ImageDropZone > Column {
   │    Expanded(StitchPreviewCanvas)   // canvas-only, ~75% of viewport
   │  }
   └─ bottomNavigationBar: StitchEditorBottomBar (64 dp, 3 chip)
```

Each chip is a `FilledButton.tonalIcon`. The state-aware chip (`[🖼 N/20]`) flips to `onPressed: null` when `state.hasImages` is false; `[+ 添加]` and `[⚙ 参数]` stay enabled. Every chip has a `Tooltip` whose message changes between enabled / disabled. The export CTA is **not** in the bar — it lives in the AppBar action slot (`Icons.save_outlined`, tooltip "导出每张子图") and follows its own `hasImages` disable rule there.

### Sheet helpers

Each trigger is a top-level `Future<void> showXxxSheet(BuildContext context, [WidgetRef ref])` function in its own file, returning the `showModalBottomSheet` future. Three flavors:

| Sheet kind | Top-level helper | Sheet config | Inner content |
|---|---|---|---|
| **ActionSheet** (3-tile picker) | `showStitchAddActionSheet(context, ref)` | `showModalBottomSheet` (default height) | `SafeArea > Column { GripHandle, ListTile×3 }` — each `onTap` pops first, then calls the controller method |
| **Content sheet** (re-mounted widget) | `showStitchImageSheet(context)` | `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)` | `ConstrainedBox(maxHeight: screenH * 0.7) > Column { GripHandle, Expanded(StitchVerticalImageList) }` |
| **Pull-up sheet** (params w/ snap sizes) | `showStitchParamsSheet(context)` | `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent)` | `DraggableScrollableSheet(initial: 0.55, snapSizes: [0.3, 0.55, 0.9])` builder returns `Material(top-rounded 16) > SingleChildScrollView(controller: scrollController) > Column { GripHandle, StitchControlsPanel, SizedBox(80) }` |

### Why `DraggableScrollableSheet` is the right tool **here** (vs the persistent-sheet "Don't" above)

The persistent `StitchControlsSheet` (legacy `medium` branch) docks into the screen's main layout and must NOT be draggable — it would fight with the sliders inside. The new `showStitchParamsSheet` is a **trigger-fired modal** invoked by a chip tap; the user opens it intentionally and dismisses it intentionally. Inside a modal, `DraggableScrollableSheet` adds the right affordance: pull up to ~0.9 to see the full panel, pull down to ~0.3 to peek the canvas while adjusting. The two cases are different surfaces with different contracts; the snap-sizes UX only makes sense in the modal one.

### Code reuse contract

Both sheet helpers **must reuse** the existing widgets that the side-panel branch uses (`StitchVerticalImageList`, `StitchControlsPanel`). Do **not** copy or fork those widgets for the sheet path:

* `StitchVerticalImageList` already supports its own scroll + reorder; the sheet just hosts it inside an `Expanded`.
* `StitchControlsPanel` is bare (no chrome — see "panel has no outer padding" convention). The pull-up sheet supplies the chrome via the `Material(borderRadius: vertical(top: Radius.circular(16)), color: surface)` wrapper.

If a future tweak needs sheet-specific behavior (e.g. a "close after action" button), add it as an optional widget parameter rather than duplicating the panel.

### Visual differentiation from the outer `AppShell` nav bar

Two `Scaffold.bottomNavigationBar` slots in the same widget tree create a stacked-bottom-bar visual. The MVP differentiation rule is **at least one** of these axes:

* `Material(elevation: 3, color: colorScheme.surface)` + top `outlineVariant` 1 dp border on the editor bar — distinguishes from the outer `NavigationBar`'s `surfaceContainer` default.
* Editor bar height 64 dp vs `NavigationBar`'s default 80 dp.
* Editor bar uses pill-shaped chips (FilledButton, tonal); `NavigationBar` uses icon + label destinations.

These three combined are enough for the MVP. If a future polish pass wants a sharper visual break, drop a `Divider(height: 1)` above the editor bar or bump its elevation to 6.

### Where this is used

* `stitch_editor_screen.dart` — compact branch only. medium / expanded / large branches stay on the legacy three-section Column / side-panel patterns. The bar widget is `StitchEditorBottomBar`; the three sheet helpers are `showStitchAddActionSheet`, `showStitchImageSheet`, `showStitchParamsSheet` (per the `05-23 mobile-canvas-redesign-for-long-image-stitching` ADR-lite).

When adding a new editor that hits the same canvas-cramped problem on compact, follow this pattern and add a row here.

### Don't

* **Don't** apply this pattern on tablet / desktop — the height-first single-column or side-panel patterns already give the canvas enough room without dismissing the controls behind a modal.
* **Don't** delete the legacy persistent-sheet widgets (`StitchControlsSheet`, `StitchImageStrip`) when migrating a single size class — the **other** size class branches still depend on them.
* **Don't** fork the panel widgets just because they live behind a modal — that's the "Sheet → Panel dual-form" anti-pattern again, just translated to mobile.

---

## Pattern: Editor body — height-first `Column` skeleton (single-column + side-panel variants)

**Problem**: An editor screen has a fixed-aspect canvas (e.g. `AspectRatio(1)`) plus a tall controls surface. Naively stacking them inside a `ListView`, or wrapping the canvas in `SingleChildScrollView` and letting `AspectRatio` size by width, makes the canvas claim `maxWidth` and become a square as tall as the column is wide — the controls fall *off-screen* (compact) or the canvas grows taller than the viewport on ultra-wide windows (expanded / large) and the page must scroll just to see the canvas. Both violate the editor mental model where the canvas and "what I can change" should be visible together without scrolling the page.

**Solution**: keep the **same height-first principle** across every size class. The canvas always lives inside an `Expanded` slot of a `Column` and is sized by `Center + AspectRatio(1)`; the controls live below it on phones (the wrapper choice — `Expanded` vs `Flexible(loose)` — depends on whether the controls slot is wrapped in chrome; see the Gotcha below) and dock to the right on tablets / desktops (`SizedBox(width: panelWidth, SingleChildScrollView)` inside a `Row(crossAxisAlignment: stretch)`).

### Single-column variant (compact / medium)

```dart
return Padding(
  // 16 dp on every side. FAB clearance is NOT applied here — see the
  // "FAB clearance lives in the scrollview, not the outer Padding"
  // convention below.
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
      // Controls slot. Wrapper choice (`Expanded` vs `Flexible(loose)`)
      // is load-bearing — see the "Flexible(loose) vs Expanded for the
      // controls slot depends on chrome" Gotcha below.
      //
      // Chrome variant (grid_editor): Expanded forces the chrome to
      // fill the column's remaining height, so the chrome background
      // (not bare page bg) covers everything below the canvas.
      //
      // The chrome's [SingleChildScrollView] takes a dynamic
      // `bottomPadding`: 80 dp when the extended FAB is visible
      // (`hasSource == true`), 16 dp otherwise. See the FAB-clearance
      // convention below.
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, hasSource ? 80 : 16),
            child: const GridControlsPanel(),
          ),
        ),
      ),

      // Bare variant (no chrome — e.g. a future editor that doesn't
      // decorate its controls): Flexible(loose) lets the slot collapse
      // to the panel's intrinsic height so the panel sits flush against
      // the canvas, no whitespace strip between them.
      // Flexible(
      //   fit: FlexFit.loose,
      //   child: SingleChildScrollView(child: const XxxControlsPanel()),
      // ),
    ],
  ),
);
```

### Convention: FAB clearance for chrome-wrapped controls slots lives in the scrollview, not the outer `Padding`

**What**: When an editor's controls slot is wrapped in surface chrome (a tinted container with a border / rounded corners) **and** the screen has a floating action button that floats above the chrome, the FAB clearance MUST be applied as **internal padding on the chrome's [SingleChildScrollView]**, not as a bottom inset on the screen's outer `Padding`.

```dart
// ✅ Correct — clearance on the scrollview
Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
  child: Column(
    children: [
      // ...canvas / warning...
      Expanded(
        child: Container(
          decoration: BoxDecoration(/* chrome */),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            // FAB clearance lives here.
            padding: EdgeInsets.fromLTRB(16, 16, 16, hasSource ? 80 : 16),
            child: const ControlsPanel(),
          ),
        ),
      ),
    ],
  ),
)

// ❌ Wrong — clearance on the outer Padding
Padding(
  // 96 dp here forces the chrome's bottom to stop 96 dp above the
  // body bottom, exposing a strip of bare page bg between the chrome
  // and the bottom nav.
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
  child: Column(
    children: [
      // ...
      Expanded(
        child: Container(
          decoration: BoxDecoration(/* chrome */),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: ControlsPanel(),
          ),
        ),
      ),
    ],
  ),
)
```

**Why**: With clearance on the outer `Padding`, the chrome's bottom edge stops `clearance` dp above the body bottom. Between the chrome's bottom and the `AppBottomNavBar` (owned by `AppShell`), Flutter paints whatever sits behind the chrome — the screen's page background. The result is a visible page-background strip the height of the FAB clearance (≈ 96 dp on phones), exactly the bleed the chrome is supposed to prevent. Moving the clearance inside the scrollview lets the chrome's outer dimensions stay anchored to its `Expanded` slot — the chrome's visible bottom rests at body bottom − 16 dp — while the scrollable content still stops `clearance` dp above the chrome's bottom edge, leaving the last card clear of the FAB when scrolled to the bottom. The FAB still floats over the chrome via `FloatingActionButtonLocation.endFloat`; the M3 idiom is for the FAB's rounded square to overlap the chrome's rounded corner, which is the intended look.

**How to apply**:

1. Outer `Padding` for the body uses a symmetric inset (typically 16 dp on every side).
2. The chrome-builder helper (e.g. `_buildControlsPanelChrome`) takes a named `bottomPadding` parameter, defaulting to the symmetric value (16 dp).
3. The size-class branch that hosts the FAB watches the visibility predicate (e.g. `hasSource` for the grid editor) and passes a larger `bottomPadding` (≈ extended-FAB height + ~32 dp safe buffer ≈ 80 dp) when the FAB is visible; the default 16 dp otherwise.
4. Size-class branches that **don't** sit under the FAB (e.g. the expanded / large side-panel branch in `grid_editor_screen.dart` — the FAB floats over the canvas column, not the docked panel) keep the default and need no special handling.

**Where this is used** (current call sites):
- `grid_editor_screen.dart`: compact / medium passes `bottomPadding: hasSource ? 80 : 16`; expanded / large uses the default 16 dp.

**Don't**: Reserve the FAB clearance as an outer-Padding bottom inset. Don't pad the chrome decoration itself with bottom margin either — the chrome must stay flush against the slot's bottom edge so its background covers what would otherwise be page bleed.

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

**Symmetry summary**: in both variants the canvas lives inside `Expanded(Center(AspectRatio(1, ...)))`. The only structural difference is **where the controls live** — under the canvas in a chrome-wrapped `Expanded` slot of the same column (compact / medium), or to the right of the canvas as a chrome-wrapped `SizedBox`-bounded column of a row (expanded / large). The height-first sizing contract is identical, and the same chrome decoration anchors the controls in both branches (see `grid_editor_screen.dart` → `_buildControlsPanelChrome`). For bare controls slots (no chrome) use `Flexible(loose)` instead of `Expanded` — see the Gotcha below.

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
| stitch_editor | **canvas-first**: body = `Column { Expanded(StitchPreviewCanvas) }` (no top strip, no bottom sheet). Inner `Scaffold.bottomNavigationBar` = `StitchEditorBottomBar` (64 dp, 3 chip: `[+ 添加]` / `[🖼 N/20]` / `[⚙ 参数]`), which naturally stacks above the outer `AppShell.bottomNavigationBar`. AppBar 保留现有的「导出每张子图」`IconButton`（与 medium 行为对齐）—— compact 与 medium 共用同一个导出入口位置，便于 muscle-memory 复用。Chips trigger ephemeral `showModalBottomSheet` overlays: add → `showStitchAddActionSheet` (3 ListTiles); image management → `showStitchImageSheet` (wraps reused `StitchVerticalImageList`); params → `showStitchParamsSheet` (wraps reused `StitchControlsPanel` in a `DraggableScrollableSheet` with `snapSizes: [0.3, 0.55, 0.9]`). See "Mobile-first persistent-bottom-bar + trigger sheets" pattern below. | scrollable canvas + bottom `StitchControlsSheet` capped at `max(200, min(screenHeight * 0.22, 320))` dp with internal `SingleChildScrollView` (see "Cap bottom-sheet height" convention) — **legacy three-section Column kept on medium pending future migration** | two-column `Row(stretch)`: canvas on the left fills the `Expanded` slot; right column is `SizedBox(width ∈ [380, 480])` wrapping a `Column` that gives `Expanded(flex:1)` to `StitchVerticalImageList` (top half — header + reorderable selected-images list with its own `SingleChildScrollView`) and `Expanded(flex:1)` to `SingleChildScrollView(StitchControlsPanel)` (bottom half). Top image strip is **not** rendered on this size class. | same, fluid (fills container); side column stays in `[380, 480]` dp with the same 50/50 split |
| grid_editor | height-first `Column`: `Expanded(flex: 3, Center(AspectRatio(1, canvas)))` + `Expanded(flex: 2, chrome[GridControlsPanel])` — chrome (`surfaceContainerLow` + `outlineVariant` + 16 dp rounded; matches the side-panel chrome at expanded / large) fills its `Expanded` slot edge-to-edge while the 3:2 flex split returns ≈ 60 % of the column's remaining height to the canvas. Per the 05-20 grid-controls-chrome-cap ADR-lite (revised), the chrome slot stays `Expanded` (an earlier `Flexible(loose) + ConstrainedBox` attempt was reverted — the chrome collapsed to its intrinsic height and a strip of bare page background bled through below it). The outer `Padding` uses 16 dp on every side; FAB clearance lives **inside** the chrome's `SingleChildScrollView` (`hasSource ? 80 : 16` dp) so the chrome's visible bottom rests on body bottom − 16 dp (no page bleed under the bottom nav). See "Editor body — height-first Column skeleton" pattern + "FAB clearance for chrome-wrapped controls slots lives in the scrollview" convention + the "Lesson: tune flex weight, not `ConstrainedBox`-on-chrome" callout below. | same as compact | height-first `Row(stretch)`: left column = `Expanded(Column(stretch) > Expanded(Center(AspectRatio(1, canvas))))` (square = `min(leftColW, rowHeight)`) + right panel ∈ [380, 480] dp wrapped in the **same** surface chrome that fills the row height, scrolls internally (default 16 dp scrollview bottom padding — FAB floats over the canvas column, not the docked panel). | same, fluid (fills container); left canvas stays height-first, side panel ∈ [380, 480] dp with the surface chrome scrolls internally |

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

### Pattern: Same widget across bounded + unbounded parents via `LayoutBuilder` dual-mode

**Problem**: A shared widget (e.g. `StitchControlsPanel`) is mounted under three different parents that disagree on whether the main-axis maxHeight is bounded:

- **compact inline** form: `SizedBox(height: 200, child: StitchControlsPanel())` → `maxHeight = 200` (bounded)
- **medium bottom sheet**: `Material > SingleChildScrollView > StitchControlsPanel()` → `maxHeight = ∞` (unbounded)
- **expanded right dock**: `SizedBox(width: panelWidth) > SingleChildScrollView > StitchControlsPanel()` → `maxHeight = ∞` (unbounded)

The widget contains a `Column { TabBar, SizedBox(8), TabBarView }`. `TabBarView` requires a bounded child height (Flutter throws `RenderFlex layout failed` otherwise). So:

- Under the bounded parent: the widget should `Expanded(child: TabBarView(...))` so the TabBar pins and the TabBarView claims **the remaining space the parent gave** (no internal scroll of the TabBar header).
- Under the unbounded parent: the widget must fall back to `SizedBox(height: 224, child: TabBarView(...))` because `Expanded` would crash (unbounded parent ⇒ no remaining space to claim), and the outer `SingleChildScrollView` already handles overflow.

**Correct pattern**: detect boundedness from `LayoutBuilder.constraints.maxHeight.isFinite`, and **flip both `Column.mainAxisSize` and the TabBarView wrapper** together:

```dart
return Padding(
  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final hasBoundedHeight = constraints.maxHeight.isFinite;
      final tabBarView = TabBarView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        children: tabViews,
      );
      return Column(
        // Bounded parent → max, so Expanded works.
        // Unbounded parent → min, so the Column shrinks to children.
        mainAxisSize:
            hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          TabBar(controller: controller, isScrollable: true, tabs: tabs),
          const SizedBox(height: 8),
          if (hasBoundedHeight)
            Expanded(child: tabBarView)
          else
            SizedBox(height: 224, child: tabBarView),
        ],
      );
    },
  ),
);
```

**Why both axes must flip together**:

- `Column(mainAxisSize: max) + Expanded` requires a bounded parent — flipping only one half crashes the other parent.
- `Column(mainAxisSize: min) + SizedBox` works under any parent — but under a bounded parent it would leave a gap below the SizedBox (chrome stops at intrinsic height instead of filling the slot) and the TabBar would scroll with the outer `SingleChildScrollView` when one is wrapped over the widget. The bounded-form `Expanded` keeps the TabBar pinned at the slot's top.

**Where this hits in this project**: `stitch_controls_panel.dart` (`05-26-compact` task). Same widget mounts under three parents — compact inline (`SizedBox(height: 200)`), medium sheet (`SingleChildScrollView`), expanded dock (`SingleChildScrollView`). The dual-mode keeps a single widget contract: caller chooses parent boundedness; widget self-adapts.

**Don't**:

- Don't pass an `isInline` / `isCompact` flag through the constructor. The widget should be **self-describing** via its child constraints — this prevents call-site drift when a new size class adds yet another mount form.
- Don't hard-code `Expanded` and leave a comment "only mount inside bounded parent". Even with the comment, the first developer who wraps the widget in a `SingleChildScrollView` for "safety" will crash production. The LayoutBuilder check is cheap and self-documenting.


### Gotcha: `Flexible(loose)` vs `Expanded` for the controls slot depends on whether the slot has chrome

In the [height-first `Column` skeleton](#pattern-editor-body--height-first-column-skeleton-single-column--side-panel-variants), the right wrapper for the controls slot depends on whether the slot is **bare** or **chrome-wrapped**:

| Slot variant | Wrapper | Why |
|---|---|---|
| **Bare panel** (no chrome) | `Flexible(fit: FlexFit.loose)` | `Expanded` would inflate a short panel and leave an awkward whitespace strip between the canvas and the first parameter card — the "canvas + first card" visual cluster breaks, and the FAB ends up overlapping the bottom of the inflated panel. `Flexible(loose)` lets the slot size to its intrinsic content height; if the content overflows the remaining space, the inner `SingleChildScrollView` scrolls inside the slot. |
| **Chrome-wrapped panel** (e.g. a surface-tinted container) | `Expanded` | `Flexible(loose)` would collapse the slot to the panel's intrinsic height, leaving a strip of bare page background visible below the chrome (≈ `free_space/2 − intrinsic_panel_h` dp on phones with tall viewports). `Expanded` forces the chrome to fill its full free-space share — the chrome's background covers the entire slot, no bare bleed. When the chrome would otherwise consume too much of the column on compact viewports, tune the canvas/chrome `Expanded(flex: N)` weights rather than wrapping the chrome in a `ConstrainedBox` — see the "Lesson: tune flex weight, not `ConstrainedBox`-on-chrome" callout below. |

Two examples:

```dart
// ✅ Bare panel — Flexible(loose) (placeholder / future editor that
// doesn't decorate the controls slot):
Flexible(
  fit: FlexFit.loose,
  child: const SingleChildScrollView(child: XxxControlsPanel()),
),

// ✅ Chrome-wrapped panel — Expanded (chrome's BoxDecoration paints
// edge-to-edge inside the slot; flex weight tunes canvas/chrome ratio
// when needed — see grid_editor's 3:2 split):
Expanded(
  flex: 2, // canvas Expanded carries flex: 3
  child: Container(
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: GridControlsPanel(),
    ),
  ),
),
```

`Flexible(tight)` (the default `fit:` for `Flexible`) behaves like `Expanded`, so prefer the explicit `Expanded` form when you want fill semantics. The `fit: FlexFit.loose` is the load-bearing part of the bare variant.

**Symptoms if you mismatch**:
- *Bare panel wrapped in `Expanded`*: a "floating" controls panel detached from the canvas by an awkward whitespace strip; or the FAB sitting on top of the panel's last parameter card.
- *Chrome-wrapped panel wrapped in `Flexible(loose)` (with or without `ConstrainedBox`)*: a strip of bare page background below the chrome (the chrome anchors to its content's intrinsic height instead of the slot's allocated share, exposing the page bg below). Looks especially wrong on tall phone viewports where `free_space − intrinsic_panel_h` is large. **The grid editor hit this exact failure mode** when a prior revision wrapped the chrome in `Flexible(loose) + ConstrainedBox(maxHeight: ...)` to "return space to the canvas" — see the lesson below for the correct technique.

### Lesson: tune flex weight, not `ConstrainedBox`-on-chrome (`05-20 grid-controls-chrome-cap` revised)

**Context**: An editor with a chrome-wrapped controls slot needs more vertical space for its canvas; the chrome looks too tall under a default `Expanded` (50/50 split with the canvas).

**Wrong approach**: wrap the chrome in `Flexible(fit: FlexFit.loose) + ConstrainedBox(maxHeight: ...)` to cap its height. **Failure mode**: `Flexible(loose)` lets the slot collapse to the panel's intrinsic height. Whenever the controls don't fill the cap, a strip of bare page background appears below the chrome (because the chrome's decoration only paints to its intrinsic height, not to the slot's allocated share). The grid editor's compact branch hit this exact bug — captured in `05-20 grid-controls-chrome-cap` PRD revised decision.

**Correct approach** (two complementary levers):

1. **Tune flex weight on the two `Expanded` slots** to skew the canvas/chrome ratio without breaking the "chrome fills its slot" invariant. The grid editor uses `Expanded(flex: 3, canvas)` + `Expanded(flex: 2, chrome)` → canvas claims ≈ 60 % of the column's remaining height while the chrome's `BoxDecoration` still paints edge-to-edge inside its slot. No page bleed.
2. **Trim the intrinsic chrome height** by lightly compressing the controls (bento card heights, type-selector strip height, etc.) so the chrome doesn't feel cramped at the smaller flex. The grid editor shaved `_BentoCard.height` 128 → 104 and `GridTypeSelector` strip 104 → 92 alongside the flex change.

Combine both — the flex skew gives the canvas its space back without ever exposing page background; the intrinsic-height trim keeps the chrome's contents legible at the smaller share.

**Don't**: reach for `ConstrainedBox` on a chrome-wrapped slot — it visually fights the chrome decoration contract and will leak page bg as soon as the controls are shorter than the cap.
