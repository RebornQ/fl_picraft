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

### Convention: Flat routing + per-screen `AppScaffold`

**What**: `GoRouter` exposes top-level routes as a flat list (no
`ShellRoute`). Each top-level screen wraps its body in `AppScaffold`, which
owns the `BottomNavBar`. `BottomNavBar` derives the active tab from
`GoRouterState.uri.toString()` rather than holding its own selected-index
state.

**Why**: Flat routes keep deep-link behavior obvious and let the
`05-08-*` feature tasks swap real screens in for placeholders one file at a
time. A `ShellRoute` would couple all top-level screens through a shared
widget tree; we don't need the cross-tab state preservation that `ShellRoute`
buys, and the coupling makes per-feature ownership messier.

**How to apply**:
- New top-level route → add to `lib/app/router.dart` AND wire its screen to
  return `AppScaffold(body: ...)`.
- Need a screen WITHOUT the bottom nav (modal flow, full-screen editor) →
  return `Scaffold` directly; do not invent a `hideBottomNav` flag on
  `AppScaffold`.
- Active-tab logic stays in `BottomNavBar` (reading the router) — never pass
  a "selected index" prop down from screens.

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
