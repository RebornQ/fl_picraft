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
