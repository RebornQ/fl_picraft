# Component Guidelines

> How widgets are built in this project.

---

## Overview

This project uses **Flutter widgets** with **Material Design 3** as the UI framework. State management is handled by **Riverpod**.

Key principles:
- Prefer **stateless widgets** when possible
- Use **const constructors** for performance
- Follow Material Design 3 guidelines from `DESIGN.md`

---

## Widget Structure

### Standard Widget File Structure

```dart
// 1. Imports (alphabetically sorted)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 2. Widget class with const constructor
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    this.size = 48.0,
  });

  // 3. Props (final, required vs optional with defaults)
  final String userId;
  final double size;

  // 4. Build method
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 5. Watch providers at the top
    final user = ref.watch(userProvider(userId));

    // 6. Return widget tree
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: user?.avatarUrl != null
          ? NetworkImage(user!.avatarUrl!)
          : null,
      child: user?.avatarUrl == null
          ? Text(user?.initials ?? '?')
          : null,
    );
  }
}
```

### StatelessWidget vs ConsumerWidget

| Use Case | Widget Type |
|----------|-------------|
| No state needed | `StatelessWidget` |
| Need to read providers | `ConsumerWidget` |
| Need to modify providers | `ConsumerStatefulWidget` |

---

## Props Conventions

### Required vs Optional

```dart
class ProductCard extends ConsumerWidget {
  const ProductCard({
    super.key,
    required this.product,        // Required - core data
    required this.onTap,          // Required - action handler
    this.showPrice = true,        // Optional with default
    this.backgroundColor,         // Optional, nullable
  });

  final Product product;
  final VoidCallback onTap;
  final bool showPrice;
  final Color? backgroundColor;
}
```

### Callback Naming

| Action | Callback Name |
|--------|---------------|
| Tap/click | `onTap` |
| Long press | `onLongPress` |
| Value changed | `onChanged` |
| Submit/confirm | `onSubmit` |
| Dismiss/close | `onDismiss` |

### Convention: Require a typed mode parameter when a widget feeds a `.family` provider

**What**: When a reusable widget routes its user input into a Riverpod
family provider keyed by a mode / kind enum, the widget MUST require the
key as a `final` constructor parameter (no default). The caller is
forced to spell out which family instance the widget feeds.

**Example** — `ImageDropZone` from the image-import feature:

```dart
class ImageDropZone extends ConsumerWidget {
  const ImageDropZone({
    super.key,
    required this.child,
    required this.sessionKind,   // ← required, no default
    ...
  });

  final ImageImportSessionKind sessionKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ...
    onPerformDrop: (event) async {
      // ...
      await ref
          .read(imageImportControllerProvider(sessionKind).notifier)
          .addFromDrop(raw);
    },
  }
}
```

**Why**: Without a required parameter, callers either silently fall
back to a default mode (leaks across sessions — the original bug this
convention prevents) or have to remember to pass the right kind every
time (silent omission becomes a runtime cross-mode contamination). A
compile-time required parameter turns a "forgot to pick the mode"
mistake into a build error.

**See also**: `state-management.md` → "Pattern: Per-mode session
isolation via `.family`".

---

## Styling Patterns

### Material Design 3 Theme

Use `Theme.of(context)` for consistent styling:

```dart
// Colors from MD3 color scheme
final colorScheme = Theme.of(context).colorScheme;
final primaryColor = colorScheme.primary;        // #6750a4
final secondaryColor = colorScheme.secondary;    // #625b71

// Text styles
final textTheme = Theme.of(context).textTheme;
final headlineStyle = textTheme.headlineMedium;
final bodyStyle = textTheme.bodyMedium;
```

### Design Tokens (from UI design HTML mocks)

The current production palette lives in `lib/app/theme/app_colors.dart`,
lifted from `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_1_首页/code.html`
(lines 14–63).

| Token | Light value | Usage |
|-------|-------------|-------|
| `primary` | `#4F378A` | CTAs, active nav, primary feature card |
| `secondary` | `#625B71` | Secondary text/icons |
| `tertiary` | `#633B48` | Accents (tips badge) |
| `background` / `surface` | `#FEF7FF` | Body bg, cards |
| `surface-container-low` | `#F9F1FD` | Feature cards |
| `outline-variant` | `#CBC4D2` | Borders |
| `error` | `#BA1A1A` | Destructive actions |
| Font Family | Inter (via `google_fonts.interTextTheme`) | All text |

> Hex literals are forbidden outside `app_colors.dart`. See
> "Convention: MD3 token sourcing" below.

---

## App Shell & Theming Conventions

The conventions in this section were captured from the
`05-08-base-architecture` task. They define how the root app, theme, and
top-level layout fit together so every feature screen is wired the same way.

### Convention: MD3 token sourcing

**What**: Every raw hex value lives in exactly one place —
`lib/app/theme/app_colors.dart`. Widgets read colors via
`Theme.of(context).colorScheme.<role>` (or `Theme.of(context).textTheme...`).
Designer-supplied HTML/Figma tokens get lifted here once and never copied
again.

**Why**: Centralizing the palette is the only way the dark theme, future
brand re-skins, and "is this the same purple?" reviews can stay coherent.
Hex literals scattered across feature files always drift.

**How to apply**:
- New design token from a mock → add to `app_colors.dart` with a comment
  citing the mock file + line range.
- Need the token in a widget → resolve via `colorScheme.primary` /
  `colorScheme.surfaceContainerLow` etc.; never `const Color(0xFF...)` in
  `lib/features/**` or `lib/core/widgets/**`.
- New role doesn't exist on `ColorScheme` → extend the theme via
  `extensions:` on `ThemeData`, don't pass raw `Color` props down the tree.

### Convention: Asymmetric light/dark theme strategy

**What**: While the design system only ships **light** tokens, the project
hand-curates the light `ColorScheme` from those tokens and seed-generates the
dark `ColorScheme` via `ColorScheme.fromSeed(seedColor: AppColors.primary,
brightness: Brightness.dark)`. `ThemeMode.system` is the default.

**Why**: The UI source-of-truth (`docs/UI Design/.../code.html`) only
specifies the light palette. Hand-rolling a dark palette without designer
input would pick arbitrary values that the next design refresh has to redo.
Seeding gives a coherent dark mode immediately and stays cheap to throw away
when real dark tokens land.

**How to apply**:
- Don't add hand-tuned dark hex tokens until the design system covers them —
  let the seed do the work.
- When the design system ships dark tokens, replace `AppTheme.dark()` with a
  hand-curated `ColorScheme` mirroring the light builder, and remove the
  seed call.
- New components must rely on `colorScheme` roles (not raw `AppColors.*`)
  so they stay correct under both themes automatically.

### Convention: StatefulShellRoute + per-branch screen + Android back-key contract

**What**: `GoRouter` exposes the four top-level tabs through
`StatefulShellRoute.indexedStack` rooted at `AppShell`
(`lib/core/widgets/app_shell.dart`). Each branch owns its own
`StatefulShellBranch` + `Navigator` stack. The shell hosts the
`Scaffold` + `AppBottomNavBar`; **tab screens themselves return a bare
`Scaffold` body without a `bottomNavigationBar`** (the shell supplies
that). Modal flows like `/export` register as sibling top-level routes
**outside** the shell so they cover the bottom nav.

`AppBottomNavBar` no longer reads `GoRouterState.uri`; the shell passes
`navigationShell.currentIndex` + an `onDestinationSelected` callback
down. Re-tapping the active tab is a no-op (per the
05-16-bottom-nav-switch-optimization task; "reset / scroll-to-top on
re-tap" is reserved for a future task).

**Why**: Reverses the earlier "flat routing + per-screen AppScaffold"
decision once real usage exposed the cost — the long-stitch editor
losing its loaded images / parameters when the user briefly visited
another tab was the breaking case. The shell topology gives us
free cross-tab state preservation (Riverpod notifiers + scroll
positions + in-flight imports all survive), prevents the
`NavigationBar` itself from being rebuilt on every tab change, and
keeps an idiomatic Material 3 NavigationBar feel (instant switch, no
transition animation). Deep-link behavior is unchanged because each
branch's first route is still a top-level path (`/`, `/stitch`,
`/grid`, `/settings`).

**Android back-key contract** (owned by `AppShell.PopScope`):

1. If the current branch's nested `Navigator` can pop → that
   Navigator handles the pop locally and the shell's `PopScope`
   never fires (system back is dispatched to the deepest active
   Navigator first; only when the branch is at its root does the
   pop bubble outward).
2. Else if `navigationShell.currentIndex != 0` →
   `navigationShell.goBranch(0)` (swap back to the home branch instead
   of exiting the app).
3. Else → `SystemNavigator.pop()` (Android-only; no-op on iOS /
   desktop / web, which fall through to OS-default behavior).

**How to apply**:
- New top-level tab → add a `StatefulShellBranch` (with its own
  `GlobalKey<NavigatorState>`) in `lib/app/router.dart` AND add a
  matching `AppNavDestination` entry to `AppBottomNavBar.destinations`
  in branch order. The screen returns a bare `Scaffold` (with its own
  `AppBar` / `FloatingActionButton` as needed) — never a
  `bottomNavigationBar`, that belongs to the shell.
- Need a screen WITHOUT the bottom nav (modal flow, full-screen
  editor) → register it as a sibling root-level `GoRoute` with
  `parentNavigatorKey: _rootNavigatorKey` so it covers the shell.
  Don't invent a `hideBottomNav` flag on the shell.
- Cross-screen state handoff into a modal route → write a Riverpod
  provider before `context.go('/modal')` (see
  `state-management.md` → "Cross-screen handoff via Riverpod, not
  GoRouter `extra`"). The provider survives the navigation because
  `ProviderScope` sits above the router.
- Each branch screen owns its own `Scaffold(appBar:, body:, floatingActionButton:)`.
  Wrap the body in `SafeArea` if it touches the bottom edge (the
  shell's bottom nav already insets the body, but the top may still
  reach the system status bar through translucent app bars).
- Branch index ↔ `AppNavDestination` order is load-bearing — keep
  `AppBottomNavBar.destinations` and `appRouter`'s branch list in
  lock-step.

**Trade-offs to accept**:
- The shell topology couples all four branches through a shared
  `StatefulNavigationShell` widget. Per-feature ownership stays clean
  because each branch's GoRoute + screen still live entirely under
  `lib/features/<feature>/presentation/screens/`; only `router.dart`
  references multiple features.
- `Navigator.canPop(context)` inside a tab's root screen returns
  `false` (the branch is at its root). Screens that conditionally
  render a back button on canPop will simply omit it on the tab root
  — that's the right behavior (a tab root is not "back-able"; use the
  bottom nav instead).
- Web browser back-button behavior follows GoRouter's default URL
  history (PopScope doesn't intercept it). Out-of-scope for the
  05-16-bottom-nav-switch-optimization task.

### Convention: Placeholder screens for in-progress features

**What**: When a route is registered before its owning feature task lands,
the screen body MUST use the shared
`PlaceholderBody(title:, description:, icon:)` widget from
`lib/core/widgets/placeholder_body.dart`. The screen file still lives in its
real future location (`lib/features/<feature>/presentation/screens/...`), so
when the real implementation arrives only one file changes.

**Why**: Earlier we duplicated four `Center > Column > Icon + Title +
Description` placeholder bodies in four different screen files. The
duplication was easy to miss at PR time and made restyling the placeholder
look-and-feel a four-file change. One shared widget keeps placeholders
visually consistent and makes the eventual swap-in trivial.

**How to apply**:
- Adding a new placeholder route → instantiate `PlaceholderBody` directly in
  the screen `build`. Don't recreate the layout inline.
- Replacing a placeholder with the real screen → delete the
  `PlaceholderBody` line and write the real body in the same file. No
  changes needed to the router.



### Spacing

Use consistent spacing values:

```dart
// Common spacing constants
const double spacing4 = 4.0;
const double spacing8 = 8.0;
const double spacing16 = 16.0;
const double spacing24 = 24.0;
const double spacing32 = 32.0;

// Use in widgets
Padding(
  padding: const EdgeInsets.all(spacing16),
  child: Column(
    children: [
      // ...
    ].withSpacing(spacing8),  // If using extension
  ),
)
```

---

## Accessibility

### Required A11y Patterns

1. **Semantic labels for images**:
   ```dart
   Image.network(
     url,
     semanticLabel: 'Product image of ${product.name}',
   )
   ```

2. **Accessible buttons**:
   ```dart
   IconButton(
     icon: const Icon(Icons.settings),
     tooltip: 'Open settings',  // Always provide tooltip
     onPressed: onPressed,
   )
   ```

3. **Minimum tap target** (48x48):
   ```dart
   GestureDetector(
     onTap: onTap,
     child: Container(
       minWidth: 48,
       minHeight: 48,
       child: // ... content
     ),
   )
   ```

4. **Screen reader support**:
   ```dart
   Semantics(
     button: true,
     label: 'Add to cart',
     child: IconButton(/* ... */),
   )
   ```

### Pitfall: `IconButton` `tapTargetSize: padded` cancelled by `visualDensity: compact`

**Symptom**: An `IconButton` styled with **both** `tapTargetSize: MaterialTapTargetSize.padded` and `visualDensity: VisualDensity.compact` renders at only **40×40 dp** — silently failing `androidTapTargetGuideline` (≥ 48) and risking `iOSTapTargetGuideline` (≥ 44).

**Cause**: `ButtonStyleButton.build` resolves the effective minimum size as

```
effectiveMinSize = max(constraints.minSize, kMinInteractiveDimension=48) + densityAdjustment
densityAdjustment = visualDensity.baseSizeAdjustment * interval(4)
```

`VisualDensity.compact = VisualDensity(horizontal: -2, vertical: -2)` resolves the adjustment to `(-8, -8)`. So `padded` (targets 48) + `compact` (−8) = **40 dp** hit area. The two settings cancel — `compact` shrinks the very tap target `padded` was supposed to guarantee.

**Fix**: For a small visual chrome that still owes a 48 dp tap target (card-corner badge buttons, dense toolbar icons), set `tapTargetSize: padded` **alone** and control visual size through `constraints` + `iconSize`:

```dart
// ❌ Wrong — `compact` shrinks the padded hit area to 40×40 dp
IconButton(
  style: IconButton.styleFrom(
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.compact,
  ),
  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
  iconSize: 14,
  onPressed: onTap,
  icon: const Icon(Icons.close),
)

// ✅ Correct — `padded` guards hit area; `constraints` + `iconSize` shape visual chrome
IconButton(
  style: IconButton.styleFrom(
    tapTargetSize: MaterialTapTargetSize.padded, // hit area ≥ 48×48 dp
    // Do NOT set `visualDensity`; let it default (standard).
  ),
  constraints: const BoxConstraints(minWidth: 24, minHeight: 24), // visual 24×24
  iconSize: 14,
  onPressed: onTap,
  icon: const Icon(Icons.close),
)
```

**Rule of thumb**: visual chrome and hit area are **separate axes**. `constraints` + `iconSize` control painted chrome; `tapTargetSize` controls hit-test bounds. When you need a small visual, never reach for `visualDensity: compact` on an a11y-sensitive button — that's a hit-area lever, not a visual-density lever.

**Historical note**: `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart::_ImageCard` × button originally adopted this pattern (visual 24×24 + hit area 48×48) and was the captured reference. Real-device review subsequently flagged the splash-feedback halo as "still too big" and the implementation switched to `shrinkWrap` (see the Caveat below). The Pitfall on `padded + compact` cancellation is still correct and applies to the **default** case — only the example call-site has moved.

#### Caveat: in card-corner badge contexts the splash feedback ring still reads as "the button's visual size"

**Where the rule of thumb breaks**: the visual / hit area decoupling above assumes users perceive only the painted chrome (`constraints` + `iconSize` → `Material(circle, ...)` + `Icon(...)`) as "the button". On a normal toolbar this is true. On a **card-corner badge** (≤ 110×140 dp card, button floats in `Positioned(top: 4, right: 4)` with no neighbor visually anchoring its scale), it is **not** — the splash / hover / focus feedback ring of `MaterialTapTargetSize.padded` fills the **entire 48×48 hit area**, and the ring is visually centered on a 24 dp chrome floating inside a 48 dp halo. Users perceive that 48 dp halo as "the button" every time they tap or hover, so the chrome-vs-hit decoupling visually defeats itself.

**Symptom**: A reviewer agrees the chrome is 24×24, the `meetsGuideline(androidTapTargetGuideline)` test passes, but on a real device the button "still looks too big" — every tap shows a 48 dp light circle around a 24 dp icon.

**Trade-off menu** (pick one, per-context):

1. **Accept the visual halo, keep ≥48dp tap target** — the default. Works on toolbar / list-row IconButtons where a 48 dp halo over a 24 dp chrome reads as "Material expressive button". Stick with the ✅ Correct example above.
2. **Drop to `tapTargetSize: shrinkWrap`, accept ≥48dp a11y violation** — for card-corner badge buttons where the visual halo dominates. Hit area = visual chrome = 24×24, `androidTapTargetGuideline` / `iOSTapTargetGuideline` fail at this widget. Document the exception in the call-site's PRD ADR-lite, guard with a `tester.getSize ≤ 28×28` regression test so the trade-off doesn't silently revert. **Reference implementation**: `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart::_ImageCard` × button (V2' / Decision v2 — superseded the V2 padded scheme above).
3. **Keep `padded`, suppress feedback chrome** via `style: IconButton.styleFrom(overlayColor: WidgetStatePropertyAll(Colors.transparent))` and/or a custom `InkResponse` with `radius: 12`. Preserves ≥48dp hit area while killing the visual halo. Trade-off: removes the user's visual confirmation of tap, which can hurt discoverability for hover-only contexts (desktop / web). Use only when the surrounding context already announces interactivity (e.g. the chrome itself animates on hover via parent `MouseRegion`).

**Decision lens**: choose option 1 by default. Choose option 2 only when a real-device review of option 1 explicitly flags "still too big" and the team accepts the a11y violation in writing (PRD ADR-lite + scoped regression test). Choose option 3 when option 2 is acceptable visually but the team is unwilling to give up the ≥48dp hit area — note that suppressing feedback is its own a11y trade-off (users can no longer confirm tap registration visually).

**Rule of thumb (extended)**: the decoupling pattern is **not unconditional** — on a card-corner badge, "the button" is `chrome + feedback halo`, not just the chrome. Validate with real-device review before relying on the decoupling.

### Pattern: Verify a11y with `meetsGuideline` widget tests

**What**: For every top-level screen, add at least four widget-test assertions:

```dart
testWidgets('home screen meets a11y guidelines', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(/* wrap in ProviderScope + MaterialApp */);

  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

  handle.dispose();
});
```

These four guidelines are Flutter's built-in checks:

| Guideline | What it asserts |
|---|---|
| `androidTapTargetGuideline` | All tappable widgets ≥ 48×48 dp |
| `iOSTapTargetGuideline` | All tappable widgets ≥ 44×44 dp |
| `textContrastGuideline` | Text-vs-background contrast ratios meet WCAG AA |
| `labeledTapTargetGuideline` | Every tappable widget has a Semantics label (so screen-readers can announce it) |

**Why**: These are non-negotiable platform requirements; failing them is grounds for App Store / Play Store rejection. Catching at test time is dramatically cheaper than discovering during review or via user complaint.

**Where to add**: `test/features/<feature>/presentation/<screen>_a11y_test.dart`. Currently covered: `home_screen_a11y_test.dart`, `export_screen_a11y_test.dart`. Editor screens (stitch / grid) have widget-level Semantics but no surface-level guideline test — their `tester.view.physicalSize` setup is more involved; track this as a known gap and add when needed.

### Pattern: Direct render-size guard for private widget a11y-critical children

**Problem**: `meetsGuideline(androidTapTargetGuideline)` is the standard hit-area assertion, but when the a11y-critical widget is a **private** (`_`-prefixed) child of a public container — e.g. `_ImageCard` inside `StitchImageStrip` — the test can't construct it directly. The usual workaround is a "mirror harness" that re-creates the same widget tree in the test file. Mirror harnesses **silently drift**: if production adds `visualDensity: compact` but the mirror doesn't, the mirror's `meetsGuideline` still passes and the regression slips through to release.

**Solution**: Double-guard with **both** a mirror harness (for `meetsGuideline` checks under a controlled minimal tree) **and** a direct production render-size assertion that pin-points the real widget through a unique tooltip / Semantics label:

```dart
testWidgets('production _ImageCard × button render size ≥ 48×48 dp', (
  tester,
) async {
  // Render the real public container, seeded with whatever providers the
  // production tree needs.
  await tester.pumpWidget(_buildRealStitchImageStrip());
  await tester.pumpAndSettle();

  // Disambiguate the target IconButton via its unique tooltip — works
  // even though the wrapping widget is private.
  final removeButton = find.ancestor(
    of: find.byTooltip('移除'),
    matching: find.byType(IconButton),
  );
  expect(removeButton, findsOneWidget);

  // Material 3 IconButton's outermost rendered widget IS the padded hit
  // area, so `tester.getSize` directly reports the tap target dimensions.
  final size = tester.getSize(removeButton);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
});
```

**Why both layers**:

- **Mirror + `meetsGuideline`** catches general a11y regressions (text contrast, missing labels, undersized siblings) under a known-stable layout.
- **Production `getSize`** catches the failure mode where the mirror has drifted from production — someone tweaks a production param (e.g. adds `visualDensity: compact`, switches `tapTargetSize` to `shrinkWrap`, shrinks `constraints`) without updating the mirror; the mirror tests pass against the stale copy while production silently drops below 48 dp.

**Reverse-sanity ritual** (recommended once per new guard): after the test goes green, temporarily break the production code (e.g. add `visualDensity: compact` back, switch `tapTargetSize` to `shrinkWrap`) and confirm the test fails. Then restore. A test that doesn't fail when the code is wrong is a rubber stamp, not a guard.

**Reference implementations**:

- **Default direction** (`getSize ≥ 48`): originally captured in `test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart::production _ImageCard × button render size ≥ 48×48 dp` (`05-19-fix-stitch-image-card-remove-button-mobile-oversized`). The same test file currently houses the **reverse direction** below; the ≥48 form is preserved as historical documentation in the PRD's Decision (ADR-lite) v1 superseded block.
- **Reverse direction** (`getSize ≤ tight_visual`): current state of the same file, `production _ImageCard × button render size is shrinkWrap-tight (≤ 28×28, NOT 48×48)`. Same pin-by-tooltip-and-getSize idiom — only the assertion direction flips. Use this form when a call-site has **explicitly** opted to violate the ≥48dp guideline (see the "Caveat: in card-corner badge contexts the splash feedback ring still reads as 'the button's visual size'" subsection under the Pitfall above). The reverse guard prevents accidental revert to `padded`, which would silently change the production rendering without anyone updating the PRD.

The pin-by-tooltip-and-`tester.getSize` recipe is identical in both directions — the takeaway is **"pin the assertion to the production widget by a stable, unique selector (tooltip / Semantics label) and assert against the rendered size"**, not which direction the bound goes.

**See also**: "Pattern: Verify a11y with `meetsGuideline` widget tests" above — the direct render-size guard is the **complement**, not a replacement: keep both when the a11y-critical widget is private and a mirror harness is in play.

### Pattern: `MergeSemantics` for label + control pairs

When a "title text + interactive control" pair (e.g. "Watermark" label + Switch) is visually one row, screen-readers should announce them as **one** tappable target, not two. Wrap them:

```dart
MergeSemantics(
  child: Row(
    children: [
      const Text('启用水印'),
      const Spacer(),
      Switch(value: enabled, onChanged: onChanged),
    ],
  ),
)
```

Without `MergeSemantics`, `labeledTapTargetGuideline` will fail because the Switch alone has no visible label (the text is a sibling node).

---

## Common Mistakes

### Gotcha: `Row(crossAxisAlignment: stretch)` inside an unbounded scrollable

**Symptom**: Runtime error `BoxConstraints forces an infinite height` (or
`infinite width`) coming from a `Row` or `Column` whose children request
`stretch` alignment.

**Cause**: A `Row` with `crossAxisAlignment: CrossAxisAlignment.stretch`
needs a finite cross-axis extent (height for `Row`, width for `Column`). When
the parent is a `ListView`, `SingleChildScrollView`, or any other widget
that hands down unbounded constraints on that axis, the `stretch` resolves
to infinity and Flutter throws.

**Fix**:
```dart
// Wrap in IntrinsicHeight when the children should match the tallest sibling
IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [/* ... */],
  ),
)

// OR drop stretch and pick a real alignment
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [/* ... */],
)
```

**Prevention**: When you reach for `stretch`, ask "what bounds the cross
axis?" If the answer is "the parent scroll view", you need `IntrinsicHeight`
(or to bound it explicitly with `SizedBox`).

### Gotcha: Reorderable list keys must be stable across position changes

**Symptom**: Drag-reorder works for the first move, then subsequent drags
"snap back", attach to the wrong item, or visibly stutter. Sometimes the
dragged card swaps content with a sibling instead of moving cleanly.

**Cause**: The reorder tracker (`ReorderableListView`,
`reorderables/ReorderableRow`, `ReorderableSliverList`, etc.) identifies
each child by its `key` to follow it across rebuilds during the drag. If
the key embeds the **position** in the list — e.g. `ValueKey('$path#$index')`
or `Key('$index')` — the key changes the moment the item moves, and the
tracker loses its anchor.

**Fix**: key by **identity**, not position.

```dart
// ❌ WRONG — key changes when index changes
ReorderableRow(
  children: [
    for (var i = 0; i < items.length; i++)
      Card(key: ValueKey('${items[i].path}#$i'), child: ...),
  ],
  onReorder: ...,
)

// ✅ CORRECT — key tracks the underlying object
ReorderableRow(
  children: [
    for (final item in items)
      Card(key: ObjectKey(item), child: ...),
  ],
  onReorder: ...,
)

// ✅ ALSO CORRECT — when items have a stable unique id
Card(key: ValueKey(item.id), child: ...)
```

`ObjectKey(item)` works because the list shuffles **references** on reorder
— the same `ImportedImage`/model instance moves to a new index but keeps
identity, so the tracker can follow it.

**Prevention**: Whenever you write a `key` for a child of a reorderable /
animated-list / `AnimatedSwitcher` widget, ask: "does this key change when
the item moves?" If yes, switch to `ObjectKey` or a domain-stable id. Path-
or content-based keys are also unsafe when two items can legitimately have
the same content (e.g. two imports of the same file path).

### Gotcha: `ScaleUpdateDetails.focalPointDelta` is per-event, not since-start

**Symptom**: A pinch-and-drag overlay tracks the finger on the first
frame, then "snaps back" or stops following on multi-frame drags. Fast
gestures only seem to apply the last frame's movement; the overlay
appears to lag behind the finger or jump to wrong positions.

**Cause**: `ScaleUpdateDetails.focalPointDelta` is the **per-event**
delta (movement since the previous `onUpdate` call), **not** the
cumulative delta since `onStart`. If you capture `_startOffset` in
`onScaleStart` and then write `_offset = _startOffset + details.focalPointDelta`
in `onScaleUpdate`, every frame overwrites `_offset` with `_startOffset +
<just this frame's tiny movement>`, so only the last frame contributes.
`ScaleUpdateDetails.scale`, in contrast, is **already** since-start (the
canonical pinch ratio), which makes the asymmetry easy to miss.

**Fix**: Derive pan from `localFocalPoint - startLocalFocalPoint`:

```dart
Offset? _startLocalFocalPoint;
Offset _startOffset = Offset.zero;

void onScaleStart(ScaleStartDetails d) {
  _startOffset = currentOffset;
  _startLocalFocalPoint = d.localFocalPoint; // capture start
}

void onScaleUpdate(ScaleUpdateDetails d) {
  // ❌ WRONG — focalPointDelta is per-event
  // setOffset(_startOffset + d.focalPointDelta);

  // ✅ CORRECT — since-start cumulative
  final pan = d.localFocalPoint - _startLocalFocalPoint!;
  setOffset(_startOffset + pan);

  // scale is already since-start, pairs naturally
  setScale(_startScale * d.scale);
}
```

**Prevention**: Default to `localFocalPoint - startLocalFocalPoint` for
pan. Only reach for `focalPointDelta` when you genuinely want a
per-frame velocity / impulse (rare — usually for inertial physics, not
for direct manipulation).

### Gotcha: Gesture priority via sibling z-order, not ancestor `HitTestBehavior`

**Symptom**: A canvas has a background pan gesture **and** a smaller
overlay child with its own gesture (e.g. `CenterCellOverlay` on top of
`GridPreviewCanvas`). The overlay's gesture should win inside its hit
bounds, but the background drag also fires — or wins outright — when
the user drags within the overlay area.

**Cause**: `HitTestBehavior.deferToChild` on the **outer** detector +
`HitTestBehavior.opaque` on the **inner** child does NOT short-circuit
hit-test. Ancestor-vs-descendant `HitTestBehavior` only controls whether
a node participates in its own hit-test pass; it does **not** stop the
ancestor from also winning the gesture arena. Both detectors enter the
arena and the outer (wider hit region, often higher accept-priority for
pan) frequently steals the gesture.

**Fix**: Make the canvas detector a **sibling** of the overlay inside
the same `Stack`, z-ordered below it, and let the overlay's
`HitTestBehavior.opaque` block hit propagation:

```dart
Stack(
  fit: StackFit.expand,
  children: [
    Image.memory(...),
    // ❌ WRONG — outer detector wrapping the Stack still enters the arena
    // GestureDetector(behavior: deferToChild, child: Stack(...))

    // ✅ CORRECT — canvas drag as a Positioned.fill sibling below overlay
    Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: ..., onScaleUpdate: ..., onScaleEnd: ...,
      ),
    ),
    AnimatedOpacity(child: IgnorePointer(child: CustomPaint(...))),
    if (showOverlay) _PositionedOverlay(...), // self-contained GestureDetector(opaque)
  ],
)
```

**Rule of thumb**: Stack hit-test runs top-down (highest z first); an
opaque hit stops propagation. So z-order alone — not ancestor behavior
— decides who sees the gesture inside the overlay's bounds.

**Prevention**: When two gestures must coexist on overlapping regions,
reach for sibling layering first; only fall back to custom arena logic
(`RawGestureDetector` + `TeamGestureRecognizer`) when the regions truly
overlap pointer-wise and z-order can't disambiguate.

### Gotcha: `withValues(alpha: x)` on tertiary surfaces breaks dark-mode contrast

**Symptom**: A custom surface (e.g. `TipsBanner` tertiary container, an inline warning) looks fine in light mode but in dark mode the text becomes hard to read against the background, or the surface itself becomes nearly invisible.

**Cause**: `Color.withValues(alpha: 0.10)` on top of a light scheme background produces a slightly tinted near-white surface — readable. The **same** alpha value on top of a dark scheme background produces a nearly transparent dark surface that disappears into the body. The alpha is applied at paint time without knowledge of what's behind it.

**Fix**: Use `Color.alphaBlend` to bake the tint into a concrete opaque color:

```dart
// ❌ Wrong — alpha is paint-time, not theme-aware
Container(
  color: colorScheme.tertiary.withValues(alpha: 0.10),
)

// ✅ Correct — alphaBlend produces a concrete blended Color that
// looks correct against both light and dark surfaces because we
// pick the underlying surface explicitly per theme
Container(
  color: Color.alphaBlend(
    colorScheme.tertiary.withValues(alpha: 0.10),
    colorScheme.surface,
  ),
)
```

**Prevention**: When designing a custom container with a tint, ask "what is the canvas behind this?" If the answer involves `surface` / `surfaceContainer`, use `alphaBlend` against that exact surface role. Reserve `withValues(alpha:)` for true transparencies (gestures, overlays on top of dynamic content where the backdrop is not a theme surface).

**Audit during dark-mode review**: grep for `withValues(alpha:` / `withOpacity(` inside `lib/features/**` and verify each one is either (a) a genuine transparency over dynamic content, or (b) needs an `alphaBlend` rewrite.

### Gotcha: EXIF Orientation 让 `Image.memory` 与 `package:image` 元数据方向不一致

**Symptom**: 一张相机/手机拍摄的竖图（例如 1080×1440 含 EXIF Orientation=6）被导入后，预览中纵横比明显错误（被横向或纵向压扁）；或者预览看上去对了，但导出 PNG 旋转了 90°。改变 `BoxFit` / `AspectRatio` 都无法消除压扁。

**Cause**: 图像处理链路里**渲染层和数据层对 EXIF Orientation 的应用策略不同**：

- Flutter `Image.memory` / `Image.file` 底层走 `ui.instantiateImageCodec`，**会**自动按 EXIF Orientation 旋转像素后再贴图；用户看到的"自然"尺寸 = 旋转后的宽高
- `package:image` 的 `startDecode` / `findDecoderForData` 只读 SOF 头，**不**应用 Orientation；返回的 `width / height` 是原始字节中的像素方向。某些版本（image:4.8.0+）的 `decodeImage` 在 JPEG 全像素解码阶段会自动烤入 orientation，但 metadata-only API 不会

如果在 `data/` 层用 `image.startDecode` 读到 `width=1080, height=1440` 存进 domain entity，再到 widget 里用 `Positioned(width, height) + BoxFit.fill` 显示一张已被 Flutter 旋转过的图，宽高就会被强行拉伸 → 视觉压扁。**同根因下渲染器（仍用 `image.decodeImage` 走 raw 坐标系）裁切出的字节方向也错了** —— 是个连带的隐性 bug。

**Fix**: 在 `data/` 层归一化时一次性把 Orientation 烤进像素并清除 tag，让 metadata 与显示视角永远一致。`package:image` 提供的 `img.bakeOrientation()` 是幂等的（无 tag 时直接返回原图），可以安全无脑调用：

```dart
// ✅ Correct — bake orientation in the data layer once, downstream layers
// see consistent metadata. See `lib/features/image_import/data/utils/
// image_normalizer.dart::bakeOrientationToBytes` for the isolate-safe
// reference implementation.
@pragma('vm:entry-point')  // ensure compute() can find it
({Uint8List bytes, int width, int height})? bakeOrientationToBytes(
  BakeOrientationRequest req,
) {
  if (req.orientation == 1) return null;          // fast path: no work
  final decoded = img.decodeImage(req.bytes);     // image:4.8.0 may already bake
  if (decoded == null) return null;
  final baked = img.bakeOrientation(decoded);     // idempotent — safe to chain
  final encoded = req.mimeType == 'image/png'
      ? img.encodePng(baked)
      : img.encodeJpg(baked, quality: _kJpegBakeQuality);  // quality=95 ≈ visually lossless
  return (bytes: Uint8List.fromList(encoded), width: baked.width, height: baked.height);
}

// ❌ Wrong — read metadata only, store raw dimensions, let Image.memory
// auto-rotate at display time. Metadata ≠ displayed aspect → BoxFit.fill
// stretches the rotated pixels into the wrong rectangle.
final info = decoder.startDecode(bytes);
return ImportedImage(bytes: bytes, width: info.width, height: info.height);
```

**Fast-path discipline**: orientation == 1 / no EXIF / non-JPEG 必须走零开销快路径（不解码、不重编码、`bytes` 保持 same-instance），否则每次普通 PNG 导入也要付一次解码-编码成本。用 `same(bytes)` 在单测里硬断言。

**Failure handling**: bake 任意环节失败（损坏 EXIF / unsupported encoder） → 返回 `null`，让 normalizer 用**原始字节 + raw metadata** 兜底（pre-fix 行为），不要丢掉这次 import 也不要抛异常。

**Cross-layer implication**: 一旦 `data/` 层烤入 orientation，**所有**消费 `ImportedImage` 的渲染器（无论是 Flutter widget 还是 `package:image` rasterizer）都自动 align —— 这正是 "Isolate-safe rasterizer in `data/`" 模式的延伸。如果某条链路绕过归一化（例如直接读 `XFile.readAsBytes()` 喂给 `Image.memory` + 喂给 `image.decodeImage` 做 layout），bug 就会复发。

**Prevention checklist**: 任何把字节同时交给「Flutter 渲染层」和「`package:image` rasterizer」的功能，都必须在 `data/` 层做一次归一化，至少包括：
- EXIF Orientation 烘焙
- 颜色空间归一化（如 ICC profile / sRGB —— 当前未覆盖，未来扩展点）
- 元数据宽高记录的是**烘焙后**的方向

### ❌ Don't

```dart
// Hardcoded colors
Container(color: Color(0xFF6750A4))

// Non-const widgets
return UserAvatar(userId: id);  // Missing const

// Ignoring theme
Text('Hello', style: TextStyle(fontSize: 16));

// Building heavy widgets in build method
@override
Widget build(BuildContext context) {
  final expensiveList = computeExpensiveList();  // ❌
  return ListView(children: expensiveList);
}
```

### ✅ Do

```dart
// Use theme colors
Container(color: Theme.of(context).colorScheme.primary)

// Const constructors
return const UserAvatar(userId: '123');

// Use theme text styles
Text('Hello', style: Theme.of(context).textTheme.bodyMedium);

// Compute once (use provider or memoization)
@override
Widget build(BuildContext context) {
  final items = ref.watch(filteredItemsProvider);  // ✅
  return ListView(children: items);
}
```

---

## Best Practices

1. **Always use `const`** when possible for performance
2. **Extract reusable widgets** to `core/widgets/` or feature widgets
3. **Keep build methods simple** - move logic to providers
4. **Use `Theme.of(context)`** instead of hardcoded values
5. **Provide tooltips** for icon buttons
6. **Test widgets** in `test/` with descriptive test names
