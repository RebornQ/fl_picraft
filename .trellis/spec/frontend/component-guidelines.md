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

### Convention: Expensive-preview sliders submit on `onChangeEnd`, not `onChanged`

**What**: When a slider drives a downstream pipeline whose evaluation
is non-trivial (isolate hop, image encode, async render, network call),
the widget MUST submit the final value via `Slider.onChangeEnd` and
locally buffer mid-drag changes in widget state. `Slider.onChanged`
updates local state only — it does NOT propagate to the controller /
provider. Sync `didUpdateWidget` to absorb external value mutations
(e.g. format toggle restoring a default) so the next render reflects
them.

**Why**: Each `onChanged` tick during a drag is ~30/s. Forwarding every
tick to a provider re-schedules the downstream pipeline 30×/s, which
(a) thrashes a debounce timer (300 ms in this project's preview
controller) so it never fires until release anyway, (b) repeatedly
transitions preview state to `Loading` causing flicker, and (c) queues
isolate tasks the user will never see. Committing only on release
collapses all this to a single render without sacrificing visual
responsiveness — the thumb and value text still follow the finger via
local `setState`.

**Example** — `_QualitySlider` in the export feature
(`lib/features/export/presentation/widgets/format_quality_card.dart`):

```dart
class _QualitySlider extends StatefulWidget {
  const _QualitySlider({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged; // submit-on-release contract

  @override
  State<_QualitySlider> createState() => _QualitySliderState();
}

class _QualitySliderState extends State<_QualitySlider> {
  late int _draftValue = widget.value;

  @override
  void didUpdateWidget(_QualitySlider old) {
    super.didUpdateWidget(old);
    // External value can change without the user dragging (e.g. format
    // toggle restoring a default). Resync the draft so the next render
    // reflects it. While the user is actively dragging, `_draftValue`
    // is already in sync via setState, so this branch only fires on
    // real external mutations.
    if (widget.value != old.value && widget.value != _draftValue) {
      _draftValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _draftValue.toDouble(),
      min: 1, max: 100, divisions: 99,
      onChanged: (v) => setState(() => _draftValue = v.round()),  // local only
      onChangeEnd: (v) => widget.onChanged(v.round()),             // commit
    );
  }
}
```

**When to apply**: Any slider whose `onChanged` ultimately writes to a
Riverpod provider that is observed by a controller running `compute()`
/ isolate work, re-rasterizing an image, re-encoding bytes, or
recomputing a memoized snapshot. Cheap sliders (volume %, scroll
opacity, layout-only tweaks that drive a synchronous rebuild already
covered by Flutter's frame budget) may continue using `onChanged`
directly — the `didUpdateWidget` + draft ceremony is overhead that
only pays off when the downstream work is genuinely expensive.

**Required tests**: assert (a) mid-drag invocations of
`Slider.onChanged` leave the upstream provider's state untouched;
(b) a subsequent `Slider.onChangeEnd` invocation commits the final
value exactly once. Invoke the callbacks directly via
`tester.widget<Slider>(...).onChanged!(v)` rather than gesture
simulation — it is deterministic and proves the wiring contract
regardless of platform pointer dispatch.

### Pattern: Dynamic-length `TabController` + nested horizontal scrollables in `TabBarView`

**Problem A — Dynamic Tab count**: A `TabBar` / `TabBarView` pair needs to add or remove a Tab in response to state (e.g. a feature-flagged settings Tab that only appears when a toggle is on). Flutter's `TabController` locks `length` at construction; you can't mutate it. `DefaultTabController` hides the controller, but inside a `ConsumerStatefulWidget` you typically own the controller so you can observe the current index, animate transitions, or react to swipes — and you need to swap it when the Tab count changes.

**Problem B — Nested horizontal scroll**: A Tab body contains a horizontal `ListView` (or a card row). `TabBarView` defaults to its own swipe physics; the two horizontal pan gestures fight in the gesture arena and the inner list often loses, making the inner scroll feel broken or inert.

**Solution**:

1. Own a `TabController` in the widget's `State`; recreate it whenever the Tab count needs to change (e.g. via `ref.listen` on the relevant provider). Defer dispose of the old controller until after the frame so in-flight listeners don't touch a disposed controller.
2. Pass `physics: const NeverScrollableScrollPhysics()` to the `TabBarView` so it never claims horizontal pan; the user switches Tabs only by tapping the `TabBar`. Inner horizontal lists then own the horizontal-pan arena uncontested.

```dart
class _PanelState extends ConsumerState<Panel> with TickerProviderStateMixin {
  late TabController _controller;
  // Track the current visibility predicate so we only rebuild the controller
  // when Tab count actually changes (not on every state update).
  late bool _hasOptionalTab;

  @override
  void initState() {
    super.initState();
    _hasOptionalTab = ref.read(
      myStateProvider.select((s) => s.shouldShowOptionalTab),
    );
    _controller = TabController(length: _hasOptionalTab ? 4 : 3, vsync: this);
    _syncOnFlip();
  }

  void _syncOnFlip() {
    ref.listenManual<bool>(
      myStateProvider.select((s) => s.shouldShowOptionalTab),
      (prev, next) {
        if (prev == next) return;
        final old = _controller;
        setState(() {
          _hasOptionalTab = next;
          _controller =
              TabController(length: next ? 4 : 3, vsync: this);
        });
        // Defer dispose until after the frame so any in-flight listener
        // (TabBar animation ticker, TabBarView's index subscription)
        // doesn't touch a disposed controller.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(controller: _controller, tabs: [...]),
        Expanded(
          child: TabBarView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(), // ← disables swipe
            children: [...],
          ),
        ),
      ],
    );
  }
}
```

**Why `addPostFrameCallback` for dispose**: the old `TabController` may still have listeners (animation tickers, `_TabBarState`'s subscription) that fire one more time during the rebuild. Disposing inside `setState` synchronously can trip `AnimationController used after being disposed` in the next frame. Deferring the dispose by one frame lets the framework drain its listeners against the still-live old controller. Cheaper than tracking every listener manually.

**Why disable `TabBarView` swipe when inner scroll exists**: with default physics, the user dragging a horizontal `ListView` inside a Tab body simultaneously satisfies the inner-list-pan and the outer-Tab-swipe gesture recognizers. The outer recognizer usually wins (it accepts on smaller deltas because it doesn't have to commit to a specific scroll direction first), so the user's drag is captured as a Tab swipe instead of a list scroll. `NeverScrollableScrollPhysics` removes `TabBarView` from the arena entirely. The user can still switch Tabs by tapping — that's the only way they should, in this layout.

**When to use**:
- Tab count depends on state (feature flags, mode-conditional Tabs, dynamic forms).
- Any Tab body contains a horizontal `ListView` / `PageView` / card row that owns its own pan gesture.

**When NOT to use**:
- Static Tab count + Tab bodies are vertical scrolls only → use plain `DefaultTabController`; default `TabBarView` swipe is the expected UX.

**Required tests**:
- Tab count flip: trigger the underlying state change; assert the Tab appears / disappears and the consumer reads the new `TabController.length`. The test would surface a `dispose`-related framework exception as an uncaught error if the deferred-dispose pattern regresses.
- Inner-list scroll: with `NeverScrollableScrollPhysics`, simulate a horizontal drag on the inner list and assert the list scrolls (not the Tab).

**Reference**: `lib/features/long_stitch/presentation/widgets/stitch_controls_panel.dart` — dynamic 3/4-Tab swap on `subtitleOnlyMode`; basic Tab body `stitch_basic_tab_cards.dart` is the nested horizontal `ListView` that required `NeverScrollableScrollPhysics`. Tests:
`test/features/long_stitch/presentation/widgets/stitch_controls_panel_test.dart::subtitle Tab is dynamically inserted / removed when subtitleOnlyMode flips`.

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

### Convention: Compact secondary-page editors (`/m/*` sibling routes) + PopScope discard confirmation

> Captured from `05-26-mobile-stitch-secondary-page`. Builds on
> the StatefulShellRoute convention above — does **not** replace it.

**What**: On `WindowSizeClass.compact` (< 600 dp) the long-stitch and
grid editors are entered as **secondary pages pushed from the home
FeatureCards**, not as bottom-nav tabs. The implementation keeps the
existing four-branch StatefulShellRoute intact for desktop / tablet
and adds two **sibling root-level GoRoutes** that cover the shell:

```dart
// lib/app/router.dart — sibling routes, mounted on _rootNavigatorKey
GoRoute(
  path: '/m/stitch',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (context, state) => const StitchEditorScreen(),
),
GoRoute(
  path: '/m/grid',
  parentNavigatorKey: _rootNavigatorKey,
  builder: (context, state) => const GridEditorScreen(),
),
```

The `/m/` prefix is the project's "mobile secondary page" convention.
Same widget (`StitchEditorScreen` / `GridEditorScreen`) is reused —
both entries (branch + sibling) build the same screen and rely on the
editor's non-autoDispose Riverpod controllers (which live above the
router in `ProviderScope`) to keep state coherent across the two
entry points. **No state duplication, no parallel widget tree.**

The home FeatureCard chooses entry style based on size class:

```dart
// lib/features/home/presentation/screens/home_screen.dart
// inside _FeatureCardsLayout.build
void goStitch() {
  if (isCompact) {
    context.push('/m/stitch');     // covers the shell on compact
  } else {
    context.go('/stitch');         // switches branch on desktop
  }
}
```

And the bottom nav trims its destinations on compact so the editor
tabs disappear (see `AppBottomNavBar.destinationsFor`).

**Why**: Compact viewports cannot afford four bottom-nav destinations
without hurting touch targets, and an "always-on" tab for the editors
collides with the task-style mental model ("enter editor → work → exit").
The secondary-page shape gives compact users the familiar
back-arrow / system-back exit affordance and a single explicit
discard-confirmation gate, without disturbing the desktop tab UX. The
double-route topology keeps desktop ZERO-changed while shipping the
compact UX.

**Compact bar destination filtering + index mapping** (lives in
`AppBottomNavBar`):

```dart
static List<AppNavDestination> destinationsFor(WindowSizeClass sc) {
  if (sc == WindowSizeClass.compact) {
    return const [_homeDestination, _settingsDestination]; // 0, 3
  }
  return destinations; // all four
}

static int branchToDisplayIndex(int branchIndex, WindowSizeClass sc) {
  if (sc != WindowSizeClass.compact) return branchIndex;
  return switch (branchIndex) {
    0 => 0,
    3 => 1,
    _ => 0, // stitch / grid: unreachable on compact, fall back to home
  };
}

static int displayToBranchIndex(int displayIndex, WindowSizeClass sc) {
  if (sc != WindowSizeClass.compact) return displayIndex;
  return displayIndex == 0 ? 0 : 3;
}
```

`AppShell` consumes these helpers so `NavigationBar.selectedIndex`
paints the right destination and `goBranch(...)` receives the right
branch even though display indices and branch indices no longer match
on compact. The shell also schedules a `goBranch(0)` reconcile when
the user drags the window from medium → compact while on a stitch /
grid branch (otherwise the bar would paint "home" via the fall-back
while the IndexedStack keeps showing the editor — a confusing
mismatch).

**PopScope discard-confirmation contract** (editor side):

```dart
// stitch_editor_screen.dart / grid_editor_screen.dart top-level
final isSecondaryPage = Navigator.canPop(context);

return PopScope(
  canPop: !isSecondaryPage || !state.hasImages, // or hasSource for grid
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    if (!isSecondaryPage) return; // shell handles tab-root pops
    final confirmed = await showDiscardEditorDialog(context);
    if (!confirmed) return;
    ref.read(stitchEditorControllerProvider.notifier).clear();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  },
  child: Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: isSecondaryPage, // explicit toggle
      // ...
    ),
    // ...
  ),
);
```

Three invariants:

1. **`Navigator.canPop(context)` is the single signal** for "I am a
   secondary page". Branch tab roots return `false` (per the
   StatefulShellRoute convention), pushed sibling routes return
   `true`. No `isCompact` flag is passed in — the topology already
   tells you.
2. **`canPop: !isSecondaryPage || !state.hasData`** lets empty
   editors pop instantly and intercepts only when there's something
   to lose. Three exit gestures (AppBar back arrow, Android system
   back, iOS edge swipe) all funnel through this single PopScope so
   the confirmation can't be bypassed.
3. **Confirm → clear() then pop** (in that order, synchronously).
   Matches the dialog's "未导出的拼图将丢失" copy. The next entry
   into the same editor lands on an empty canvas. The dialog itself
   lives in `lib/core/widgets/discard_editor_dialog.dart` so the
   stitch and grid call sites stay in lock-step (per the code-reuse
   guide).

**How to apply** (adding a new editor that needs the same shape):

- Register the editor's branch route as usual; **also** add a
  `/m/<editor>` sibling root-level route bound to `_rootNavigatorKey`.
- In the home FeatureCard's `onActionPressed`, branch on
  `windowSizeClassOf(context) == WindowSizeClass.compact` and push
  the `/m/...` variant on compact, `go(...)` the branch route
  otherwise.
- Wrap the editor's top-level widget in `PopScope` with the
  `Navigator.canPop`-driven `isSecondaryPage` predicate above.
- Call `showDiscardEditorDialog` for the confirm; reuse the existing
  helper rather than rolling a new dialog.
- Set `AppBar.automaticallyImplyLeading: isSecondaryPage` so the
  back arrow only appears on the secondary-page entry.

**Trade-offs to accept**:

- The same screen is mounted under two route paths; widget tests for
  the secondary-page contract must use the `/m/...` path to reproduce
  `Navigator.canPop == true`. The branch-route tests stay unchanged.
- `PopScope.canPop` watches `state.hasImages` / `state.hasSource`, so
  the editor must `ref.watch` the controller in its `build` to drive
  rebuilds of the PopScope. The watch already exists for other
  reasons in both editors, so this is free.
- Branch index ↔ destination display index translation lives in
  `AppBottomNavBar`; widget tests that previously assumed
  `selectedIndex == branchIndex` must call `branchToDisplayIndex` to
  stay correct on compact.

**Don't**:

- Don't invent a `hideBottomNav` flag on `AppShell` — keep the
  shell's "host the nav" contract intact; compact just feeds it a
  shorter destination list.
- Don't duplicate `StitchEditorScreen` / `GridEditorScreen` under a
  `compact_` variant; the same widget handles both entries.
- Don't gate the discard dialog on size class — gate it on
  `Navigator.canPop(context)` (i.e. on whether this is a secondary
  page). A future surface that pushes the editor for non-compact
  reasons gets the dialog for free.

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

### Gotcha: `TextButton.icon` / `IconButton.icon` 不能用 `find.byType(TextButton)` 定位

**Symptom**: 用 `find.byType(TextButton)` 在 widget 测试里查找一个 `TextButton.icon(...)` 时返回 0 个匹配，断言 `findsOneWidget` 失败；改成 `find.byWidgetPredicate((w) => w is TextButton)` 立刻就能找到。`IconButton.icon` 同样的现象。

**Cause**: `TextButton.icon` 这类 `.icon` 命名构造器在 Flutter SDK 内部返回的是**私有子类**（`_TextButtonWithIcon` extends `TextButton`、`_IconButtonM3` extends `IconButton` 等），而 `find.byType(T)` 的匹配语义是**严格按 `runtimeType` 等于 T**（不是 `is T`）—— 因此私有子类不会被 `find.byType(父类)` 匹配到。

**Fix**: 用 `find.byWidgetPredicate((w) => w is TextButton)` 替代 `find.byType(TextButton)`，谓词走的是 Dart 的 `is` 子类型检查，能正确捕获私有子类：

```dart
// ❌ Wrong — strict runtimeType match misses the private subclass
final btn = find.byType(TextButton);
expect(btn, findsOneWidget);  // 失败：找到 0 个

// ✅ Correct — subtype-aware predicate
final btn = find.byWidgetPredicate((w) => w is TextButton);
expect(btn, findsOneWidget);
```

**When multiple `.icon` buttons coexist**（例如「添加」「清空」两个相邻 `TextButton.icon`），结合 `find.ancestor` + 唯一 `tooltip` 来 pin（与上面 "Pattern: Direct render-size guard" 的 pin-by-tooltip 思路一致）：

```dart
final addButton = find.ancestor(
  of: find.byTooltip('已达上限 20 张'),  // 或对应的可用 tooltip
  matching: find.byWidgetPredicate((w) => w is TextButton),
);
expect(tester.widget<TextButton>(addButton).onPressed, isNull);
```

**Why this matters**：现在常用的 disabled-state 断言（`onPressed == null`）依赖能取到那个 `TextButton` widget；若 finder 找不到，整个测试只会停在 `findsOneWidget` 失败，看不到真正的 disabled / enabled 状态，给人「按钮根本没渲染」的误判。

**Reference implementations**: `test/features/long_stitch/presentation/widgets/stitch_image_strip_test.dart` 与 `stitch_vertical_image_list_test.dart` 的 "session-cap" 测试组同时使用 `find.byWidgetPredicate((w) => w is TextButton)` + `find.byTooltip(...)` pin（来自 `05-20-stitch-import-limit-20`）。

**See also**: "Pattern: Direct render-size guard for private widget a11y-critical children" — 同样的 pin-by-tooltip 思路，只是断言的目标不同（render size vs `onPressed == null`）。

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

### Gotcha: stale-while-loading 占位会让用户误以为是最新结果

**Symptom**: 用户调整某个配置（水印/格式/质量/滤镜参数等），预览区在防抖+重渲染期间
显示了"上一次的真实渲染结果"作为占位（"无白屏闪烁"的优化）。用户看到画面没变，
以为「设置没生效」/「就是这个效果」，开始反复调、点保存确认、报 bug。本质上：**视觉
占位的"信息含量"远高于 chip 文案/spinner 的"状态提示"**——stale 帧太"逼真"，盖过了
"刷新中..."的语义提示。

**Cause**: 把"占位"当成"过渡"——以为用 stale 帧 + chip 就能让用户既知道"在刷新"
又有"参考"。但用户对画面的第一感知是"它就是结果"，chip 是次要信号。当 stale 与
配置变更后的真实结果差异不大（如水印 opacity 从 50% 调到 60%）时，用户根本看不出
差别；当差异大（如切了水印开关）时，用户会信 stale 不会信 chip。

**Fix**: 占位状态使用**视觉上明显不同于"完成态"的形态**：

```dart
// ❌ Wrong — stale 帧 + chip，看上去像是完成的预览
case PreviewLoading(:final staleBytes?):
  return Stack([
    Image.memory(staleBytes),           // 用户以为这是最新结果
    Positioned(child: _RefreshingChip()), // 用户没注意到这个 chip
  ]);

// ❌ Also wrong (iteration 1 in this project) — widget canvas 仍像"完成的预览"
// 即便 + Opacity(0.6) + chip，canvas 本身就是"完整的预览图样貌"
// （只是不含水印/格式编码），还会随用户在编辑器侧的源图变化跳动，
// 与"在加载中"语义脱节
case PreviewLoading(:final staleBytes):
  return Stack([
    Opacity(opacity: 0.6, child: const StitchPreviewCanvas()),
    Positioned(child: _LoadingChip(label: '加载中...')),
  ]);

// ✅ Correct — Material 标准 spinner + 文案，视觉上明确"不是结果"
case PreviewLoading(:final staleBytes):
  return ColoredBox(
    color: colorScheme.surfaceContainerLow,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          // 文案差异：staleBytes == null → "加载中..."，否则 "刷新中..."
          Text(staleBytes == null ? '加载中...' : '刷新中...'),
        ],
      ),
    ),
  );
```

**Heuristic**: 任何"配置变更 → 异步重计算 → 结果替换"流程，loading 占位应该用
**视觉上明显能区分"未完成"的形态**（spinner + 文案是最朴素也最稳妥的选择），
而不是"上一次的真实结果 + 一个 chip"或"虽然不是结果但样貌仍像结果的 widget
canvas + chip"。规则更朴素：**别给用户看任何"看上去像是结果"的图，并指望他读
chip 文案理解 "其实在 reloading"**。

**例外**：**错误状态**下用 stale 作半透明背景是可以的——明确的错误标题（如
"预览暂不可用"）已经告知用户当前状态，stale 此时只起"上一次还在那"的安抚作用，
不会引发"误以为是最新"的歧义。Loading（无明确错误信号）和 Error（有明确错误信号）
在这一点上语义不同。

**Reference**: `lib/features/export/presentation/widgets/preview_skeleton.dart` —
`PreviewLoading.staleBytes` 字段被 controller 一直传递（保留扩展空间），但 widget
**忽略它**，主视觉只画 Material 标准 `CircularProgressIndicator` + 文案
（按 staleBytes 是否非空切换"加载中..."/"刷新中..."）。`PreviewError` 仍保留 stale
半透明背景作为对比。决策详见
`.trellis/tasks/05-20-preview-ui/prd.md` §D4 (revised twice 2026-05-21)
——记录了从 "stale + chip" → "widget canvas + chip" → "spinner + 文案"
的两次迭代历程及理由。

### Gotcha: `FloatingActionButton` 默认 heroTag 在多 screen 同时存活时冲突

**Symptom**: 在拥有 `StatefulShellRoute.indexedStack` / `IndexedStack` / Drawer 多 page
等"多 screen 同时挂载"的应用里，点击任意一个 screen 上的 `FloatingActionButton` 后
应用抛断言：

```
Hero animation: There are multiple heroes that share the same tag within a subtree.
... multiple heroes had the following tag: <default FloatingActionButton tag>
```

**Cause**: `FloatingActionButton` 在 build 时自动把自己包进 `Hero(tag: _kDefaultHeroTag)`
以支持 FAB 的滑入/翻转过渡动画（MD3 标准 transition）。`_kDefaultHeroTag` 是 Flutter
内部常量、所有未显式指定 `heroTag` 的 FAB **共用同一个**。一旦两个或更多 FAB 同时
存活于同一个 hero 子树（`StatefulShellRoute` 的 IndexedStack 让所有 branch screen
始终在 widget tree 里，即便不显示），点击其中任意一个触发路由切换 → Flutter 收集
所有同 tag 的 Hero → 检测到多于 1 个 → 断言抛出。

注意：单 screen 应用下默认 heroTag **没问题**——Flutter 会在路由切换时只看 from / to
两个 route 的 hero 子树，单 FAB 的话不会冲突。bug 的触发条件是"多 FAB 同时存活"。

**Fix**: 对每个 `FloatingActionButton` 显式声明 `heroTag`，命名约定
`<feature>-<purpose>-fab`：

```dart
// ❌ Wrong — 当多 screen 共存时崩溃
FloatingActionButton.extended(
  onPressed: _onExportPressed,
  icon: const Icon(Icons.output),
  label: const Text('导出'),
)

// ✅ Correct — 显式唯一 tag，保留默认 hero 过渡动画
FloatingActionButton.extended(
  // StatefulShellRoute 让 stitch / grid 两个 editor screen 同时存活，
  // 默认 heroTag (_kDefaultHeroTag) 会与兄弟 screen 的 FAB 冲突
  // 触发 "multiple heroes share the same tag" 断言。
  heroTag: 'stitch-export-fab',
  onPressed: _onExportPressed,
  icon: const Icon(Icons.output),
  label: const Text('导出'),
)
```

**Don't reach for `heroTag: null`** —— 那会**禁用** hero animation，FAB 在路由切换时
不再有 MD3 标准的滑入/翻转过渡。除非你确实不想要动画，否则始终给唯一字符串。

**Prevention**: 任何 `lib/features/<feature>/presentation/screens/*` 下的
`FloatingActionButton`（含 `.extended` / `.large` / `.small` 等变体）必须带
`heroTag`，命名 `<feature>-<purpose>-fab`。多 FAB 同 feature 时再加序号
（`stitch-export-fab` / `stitch-share-fab`）。新增 screen 时如果用了 FAB，先
`grep -rn "FloatingActionButton" lib/` 看看有没有其他 screen 已经在用——避免命名碰撞。

**Reference**: `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
+ `lib/features/grid/presentation/screens/grid_editor_screen.dart` 同时存在
"导出"FAB，分别用 `heroTag: 'stitch-export-fab'` / `'grid-export-fab'` 避免冲突。


### Gotcha: `Scaffold.appBar` 槽位的 `Material` 即使透明也会吃掉下层 hit-test

**Symptom**: 一个全屏 / 沉浸式 dialog 在 `Scaffold.appBar` 上放了个透明 `AppBar`
（`backgroundColor: Colors.transparent, elevation: 0`），同时想在 `body` 的同一区域
（典型场景：左上角浮动关闭按钮）放一个**常驻**的悬浮按钮，让它即使在 AppBar
显示时也能被点。**结果**：浮动按钮在 AppBar 显示态下完全不响应 tap；只要把 AppBar
隐藏（或临时把 `appBar` 设成 `null`）按钮就重新可点。改 AppBar 的 `backgroundColor`
/ `elevation` / `surfaceTintColor` 都没用。

**Cause**: `Scaffold` 把 `appBar` 槽位的 widget 包进自己的 `Material` 层，并把它布局到
**body 之上的独立子树**（`Scaffold.of(context).appBarMaxHeight` 区域）。Material 默认
`type: MaterialType.canvas`、`color` 透明也照样是个完整的 `_RenderInkFeatures` 区域
—— hit-test 阶段它**作为一个 opaque box 接收命中**，根本不会把命中下穿给 body。
"`color: transparent` 等于透传"这个直觉只对**绘制**成立，对**命中测试**不成立。
（与 `withValues(alpha:)` 不影响命中的现象同源——alpha 是 paint-time，hit-test 走的
是 `RenderBox.hitTest` 的几何判定。）

**Fix**: 任何"全屏 viewer / 沉浸式编辑器 / photo gallery"类页面，**别用
`Scaffold.appBar` 槽位**。把 AppBar 作为 `body: Stack` 的一员：

```dart
// ❌ Wrong —— 透明 AppBar 仍然挡住下层浮动按钮的 hit-test
Scaffold(
  appBar: AppBar(backgroundColor: Colors.transparent, ...),
  body: Stack(
    children: [
      PageView(...),
      Positioned(top: 8, left: 8, child: _FloatingCloseButton(...)),
    ],
  ),
)

// ✅ Correct —— AppBar 进 body Stack；浮动 X 与 AppBar 同级、永远位于 Stack 顶层
Scaffold(
  extendBody: true,
  extendBodyBehindAppBar: true,
  body: Stack(
    children: [
      Positioned.fill(child: PageView(...)),
      // AppBar 作为 Positioned 子层，自带 IgnorePointer 控制可点状态
      Positioned(
        top: 0, left: 0, right: 0,
        child: IgnorePointer(
          ignoring: !_chromeVisible, // 隐藏期间不拦截下层
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _chromeVisible ? 1.0 : 0.0,
              child: AppBar(
                backgroundColor: Colors.transparent,
                automaticallyImplyLeading: false,
                title: Text(title),
              ),
            ),
          ),
        ),
      ),
      // 常驻浮动按钮：与 AppBar 同级、位于 Stack 顶层，永远可点
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        child: _FloatingCloseButton(onPressed: ...),
      ),
    ],
  ),
)
```

**Why the `IgnorePointer` wrap matters**: AppBar 隐藏期间（`_chromeVisible == false`）
即便已经 `Opacity = 0`，它的 hit-test box 仍然存在；用户点击图片区会被 AppBar 拦住、
触发不了底层的"单击切显隐"。`IgnorePointer(ignoring: !_chromeVisible)` 在隐藏期间
把整条 AppBar 子树从 hit-test 中拿掉，单击直接落到 PageView 上。

**Rule of thumb**: 只要满足以下任一条件，就**不要**用 `Scaffold.appBar`：
1. AppBar 是透明 / 半透明，且 body 内容在视觉上延伸到 AppBar 区域（`extendBodyBehindAppBar: true`）
2. AppBar 需要"显隐切换"且切换期间下层必须可点（沉浸式 photo viewer、视频播放器、地图全屏模式）
3. AppBar 同区域还需要一个**常驻**浮动按钮（关闭 / 设置 / 收藏），不能跟随 chrome 隐藏

退路：标准 `Scaffold(appBar: AppBar(...))` 仍然是非沉浸式页面的首选——AppBar 不透明、
不需要"穿透"时，本 Pitfall 不适用。

**Anti-pattern checklist**：写完代码后自查"AppBar 显示时下层是否还能点击"——如果
你正在 `_chromeVisible` 这类状态里改 AppBar 的可见性，且 body 同区域有按钮，**先**
把 AppBar 挪进 body Stack 再继续，别等"全部看上去对了但点不到"才回头排查。

**Reference**:
`lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
（`05-22-export-preview-fullscreen-immersive` 任务）—— 全屏沉浸式照片查看器的
AppBar + 常驻浮动 × 按钮分层。

### Gotcha: 图片交互必须用 `BoxFit.contain` 实际渲染矩形计算热区，不能假设图铺满 viewport

**Symptom**: 给一个 `BoxFit.contain` 的图片加双击放大 / 点击热区 / 拖拽手势时，
* 双击图片**留白区**（letterbox 黑边），放大锚点出现在留白处 → 图片瞬间被弹出 viewport，
  用户看到的是"放大到一半空白"；
* 或者基于 `tap.localPosition` 直接换算图片像素坐标，得到的点是错的——尤其图片宽高比
  与 viewport 不同时，偏移量恒定错位；
* 又或者横向 pan "触底"判定永远不准——以 viewport 宽算极限，但实际图片可能只占
  viewport 的 60% 宽，剩下的 40% 全是黑边。

**Cause**: `BoxFit.contain` 把图片**等比例缩放进** viewport，结果尺寸 = `min(viewport.w/img.w,
viewport.h/img.h) * img`；图片实际占据的 rect 居中且小于 viewport，**留白区在两侧（横图）
或上下（竖图）**。任何用 `Offset.zero ~ viewport` 区间假设图片均匀分布的换算都是错的。
"图片应该铺满 viewport" 是只有 `BoxFit.cover` / `BoxFit.fill` 才成立的前提，对 `contain`
就是 bug。

**Fix**: 在 `LayoutBuilder` 里拿到 `viewport`，结合 `Image` 流上来的 intrinsic
`_imageSize`，**先算出真实渲染矩形**，再做任何坐标判定：

```dart
/// Returns the rect occupied by the image inside the viewport under
/// `BoxFit.contain`. Returns `null` until the image stream has reported
/// the intrinsic size.
Rect? _imageDisplayRect(Size viewport, Size imgSize) {
  if (imgSize.isEmpty || viewport.isEmpty) return null;
  final imageAspect = imgSize.width / imgSize.height;
  final viewportAspect = viewport.width / viewport.height;
  double displayWidth;
  double displayHeight;
  if (imageAspect > viewportAspect) {
    // 横向受限：图片宽 = viewport 宽，上下有黑边
    displayWidth = viewport.width;
    displayHeight = viewport.width / imageAspect;
  } else {
    // 纵向受限：图片高 = viewport 高，左右有黑边
    displayHeight = viewport.height;
    displayWidth = viewport.height * imageAspect;
  }
  final left = (viewport.width - displayWidth) / 2;
  final top = (viewport.height - displayHeight) / 2;
  return Rect.fromLTWH(left, top, displayWidth, displayHeight);
}

// 拿到 intrinsic size：监听 Image 的 ImageStream
Image.memory(bytes).image
    .resolve(ImageConfiguration.empty)
    .addListener(ImageStreamListener((info, _) {
      setState(() => _imageSize = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      ));
    }));
```

**Double-tap focal point fallback**：双击点 `localTap` 落在留白区时，回退到图片中心，
**避免锚点被弹出图片范围**：

```dart
Offset _resolveFocalPoint(Offset localTap, Rect? imageRect) {
  if (imageRect == null || imageRect.contains(localTap)) return localTap;
  return imageRect.center;
}
```

**Companion: scale-around-focal Matrix4 formula**

围绕"图中某一点"放大的标准仿射变换是 `T(focal) ⋅ S(s) ⋅ T(-focal)`——即先把 focal
平移到原点、缩放、再平移回去。展开 `Matrix4` 后的等价写法只用一次 translate + 一次
scale：

```dart
Matrix4 _zoomMatrix(double scale, Offset focal) {
  // 等价于 T(focal) ⋅ S(scale) ⋅ T(-focal)：focal 像素是变换的不动点
  return Matrix4.identity()
    ..translateByDouble(focal.dx * (1 - scale), focal.dy * (1 - scale), 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}
```

**反例**：直接 `Matrix4.identity()..scale(s)..translate(focal)`——这是"先缩放再平移
focal 个单位"，焦点会跟着缩放系数漂移，双击点根本不会保持在原位。验证方法：双击
屏幕角落，看图片是不是真的"以双击点为不动点"放大；若用错误公式，双击屏幕右下角
会把图片中心都拽到屏幕外。

**Anti-pattern**:
```dart
// ❌ 假设图片铺满 viewport
final imageX = localTap.dx / viewport.width * imageBytes.width;
// 图片是 contain，viewport.width 包含两侧黑边 → 横图时坐标恒偏

// ❌ 直接拿 viewport 当 "触底" 判定的极限宽
final maxTx = (viewport.width * scale - viewport.width) / 2;
// 应是 imageDisplayRect.width * scale，否则缩放系数 ≤ viewport/img 比时永远算不到极限
```

**Rule of thumb**: 只要项目里出现 `BoxFit.contain` + 任意一个动词（tap / drag / zoom /
crop / annotate），**第一步**就是写 `_imageDisplayRect()`；之后所有坐标判定都基于
这个 rect，不基于 viewport。这条规则同样适用于网格编辑器 / 长图拼接器里把"图层坐标"
换算成"像素坐标"的 use case。

**Reference**:
`lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
的 `_imageDisplayRect` / `_resolveFocalPoint` / `_zoomMatrix`
（`05-22-export-preview-fullscreen-immersive` 任务）。

### Gotcha: Flutter 桌面端 PageView / ListView 默认不响应鼠标拖动

**Symptom**: 在 macOS / Windows / Linux / Web 上，一个 `PageView` / `ListView` /
任何 `Scrollable` 在手机端测试一切正常，但桌面 / Web 浏览器里用鼠标按住拖动
**没有任何反应** —— 既不滚动也不切页。换成 trackpad two-finger 滑就立刻能动。
真机触摸屏（如带触摸的 Surface / Chromebook）也能动。换言之：**只有鼠标拖动失效**。

**Cause**: Flutter 默认的 `ScrollBehavior` 通过 `dragDevices` getter 声明
**哪些 pointer 类型可以触发滚动手势**。该 getter 默认返回：

```dart
static const Set<PointerDeviceKind> _kTouchLikeDeviceTypes = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.unknown,
};
```

注意 **`PointerDeviceKind.mouse` 不在集合里**。`MaterialScrollBehavior` 继承自
`ScrollBehavior`，没有覆写 `dragDevices`，所以同样不包含鼠标。当鼠标 pointer
down + drag 事件到达 `Scrollable` 时，`HorizontalDragGestureRecognizer` /
`VerticalDragGestureRecognizer` 通过 `acceptKind` 判定后**拒绝**该事件 ——
recognizer 不进入 gesture arena，PageView 完全收不到鼠标拖动。

这是 Flutter 的历史决策：早期桌面 / Web 期望用滚轮滚动而非鼠标拖动，避免与
"鼠标点击选择 / 框选" 等手势冲突。但对于 PageView 风格的交互（一次只显示一张
图，要求鼠标拖动切换），这个默认就不合适。

**Fix**: 自定义 `ScrollBehavior`（继承自 `MaterialScrollBehavior` 复用其他默认）
覆写 `dragDevices`，把所有 6 种 pointer kind 都加进去，然后用 `ScrollConfiguration`
包裹目标 `Scrollable`：

```dart
class _ImmersiveScrollBehavior extends MaterialScrollBehavior {
  const _ImmersiveScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,        // ← 关键：补齐鼠标
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

// 在 PageView / ListView 外层
ScrollConfiguration(
  behavior: const _ImmersiveScrollBehavior(),
  child: PageView.builder(...),  // 现在鼠标 + trackpad + 触摸全都能拖
)
```

`ScrollConfiguration.of(context)` 走的是 "最近祖先优先" 语义，所以即便外层
`MaterialApp` 也有一个默认 `ScrollConfiguration`，更靠近 `Scrollable` 的自定义
版本会胜出。

**Anti-pattern**:

```dart
// ❌ 期望 MaterialApp 全局生效 —— 这只会改"应用根"的 ScrollBehavior
//    并波及到所有 Scrollable，包括 Drawer / Dialog 里的滚动表单
//    （而那些可能"鼠标可拖"反而是异常体验，不希望统一开）
MaterialApp(
  scrollBehavior: _ImmersiveScrollBehavior(),
  ...
)
```

应该按需在目标 `Scrollable` 外层包装，**而非全局覆写**。

```dart
// ❌ 试图在 onPanStart 里手动 detect 鼠标 + 转发到 PageController
//    —— pointer 事件根本进不来这一层（被 dragDevices 过滤掉了），
//    onPanStart 不会触发
GestureDetector(
  onPanStart: (d) { /* detect mouse here ... */ },
  child: PageView(...),
)
```

`dragDevices` 的过滤是在 recognizer 层做的，比 `GestureDetector` 还要靠下。
要解决问题必须从 `ScrollBehavior` 入手。

**Reference**: `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
里的 `_ImmersiveScrollBehavior` + `ScrollConfiguration` 包装
（`05-22-export-preview-fullscreen-immersive` 任务的桌面端回归修复）。
验证方式：单测查 `find.ancestor(of: find.byType(PageView), matching: find.byType(ScrollConfiguration))`
的 `behavior.dragDevices` 是否包含 `PointerDeviceKind.mouse`。

---

### Pattern + Gotcha: `extended_image` 三件套多图沉浸式画廊

> 沉淀自 `05-22-migrate-fullscreen-dialog` (ST2 of brainstorm
> `05-22-brainstorm-fullscreen-preview-extended-image`)：884 行自实现
> `InteractiveViewer + PageView + 自定义 ScrollPhysics` 替换为 429 行
> 第三方包三件套。ADR-0001 因此被 Superseded by ADR-0002。

**Problem**: 多图沉浸式预览（iOS Photos / Google Photos 风格）需要同时满足:
- 单图: pinch / pan / double-tap zoom
- 多图: 横向 fling 切页
- 联动: 缩放到边缘后水平拖动自然 bleed 到下一页
- drag-to-dismiss: 未缩放时下拉关闭，缩放时该手势被屏蔽（pan 接管）

Flutter 原生 `InteractiveViewer + PageView` 不能开箱完成"缩放↔切页"协调；
自实现需要 (a) 自定义 `PageScrollPhysics`、(b) 上报当前页 zoom + edge 状态、
(c) 外层 GestureDetector callback null/non-null 切换以避免手势竞技场冲突。
~800 行实现成本 + 持续维护负担。

**Solution**: 用 `extended_image: ^10.0.1` 的三件套组合（每层职责正交）:

```dart
Dialog.fullscreen(
  backgroundColor: Colors.transparent,
  child: ExtendedImageSlidePage(            // ① 外层 drag-to-dismiss
    slideAxis: SlideAxis.vertical,
    slideType: SlideType.onlyImage,
    slideEndHandler: (Offset offset, {Size? pageSize, ScaleEndDetails? details}) {
      final dy = offset.dy.abs();
      final flingV = details?.velocity.pixelsPerSecond.dy.abs() ?? 0;
      return dy >= 100 || flingV >= 800;    // 命中阈值 → dismiss
    },
    slidePageBackgroundHandler: (Offset offset, Size pageSize) {
      final frac = (offset.dy.abs() / 100).clamp(0.0, 1.0);
      return Colors.black.withValues(alpha: (1.0 - frac * 0.6).clamp(0.4, 1.0));
    },
    child: ScrollConfiguration(             // 桌面 mouse drag 保险（见上一节）
      behavior: const _ImmersiveScrollBehavior(),
      child: ExtendedImageGesturePageView.builder(  // ② 中层多图画廊
        controller: ExtendedPageController(initialPage: initialIndex),
        onPageChanged: _onPageChanged,
        itemCount: bytes.length,
        itemBuilder: (_, i) => ExtendedImage.memory(
          bytes[i],
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,  // ③ 叶子单页手势
          enableSlideOutPage: true,         // CRITICAL — 见 Gotcha-1
          onDoubleTap: _handleDoubleTap,    // 见 Pattern-B
          initGestureConfigHandler: (state) => GestureConfig(
            inPageView: true,               // CRITICAL — 见 Gotcha-2
            minScale: 1.0,
            maxScale: 4.0,
            animationMinScale: 0.8,
            animationMaxScale: 4.4,
            initialAlignment: InitialAlignment.center,
          ),
        ),
      ),
    ),
  ),
)
```

**Why**: ext 把所有手势协调藏在包内 (`gesture.dart:347-389` 在 zoomed 时
自动屏蔽 drag-to-dismiss 路由；`gesture.dart:396-431` + `utils.dart:350-369`
在 zoomed + 已触边时把剩余 delta 灌回 PageView)。我们不再需要维护
`{zoomed, atLeftEdge, atRightEdge}` 状态机、外层垂直手势 callback
null/non-null 切换、`TransformationController` 监听 / 边界计算等约 ~500 行。

#### Gotcha-1: `enableSlideOutPage: true` 必须在 `ExtendedImage` 上设置

**Symptom**: drag-to-dismiss 触发了 (route pop)，但下拉过程中 `slidePageBackgroundHandler`
返回的 alpha 没有联动到背景；或者图片在 drag 过程中不下移。

**Cause**: `ExtendedImageSlidePage` 与内层 `ExtendedImage` 通过 InheritedWidget
通信，`enableSlideOutPage: true` 是叶子 widget 的订阅开关。漏写则 SlidePage
更新 state 时叶子收不到通知 → 背景 / 位移不更新。

**Fix**: 三件套用法时 `ExtendedImage.memory(..., enableSlideOutPage: true)` 必填。

#### Gotcha-2: `GestureConfig(inPageView: true)` 必须设置

**Symptom**: 多图模式下，缩放到边缘后水平拖动**不会**切到下一页；要么图片
继续 pan 出边界、要么手势被 ExtendedImageGesturePageView 抢走但页面不动。

**Cause**: ExtendedImage 通过 `findAncestorStateOfType<ExtendedImageGesturePageViewState>`
注册到外层 PageView (`gesture.dart:140`)，仅在 `inPageView == true` 时才执行
注册。漏写则图片与 PageView 间没有协调通道，"缩放到边切页"行为消失。

**Fix**: 用 `ExtendedImageGesturePageView` 时，叶子的 `GestureConfig` 必须
`inPageView: true`。**单图场景**（非 PageView 包裹）下保持 `false`（默认）即可。

#### Pattern-A: `Dialog.fullscreen + ExtendedImageSlidePage` 双层 wrapper 兼容 `showDialog`

`ExtendedImageSlidePage` 设计上配合透明 PageRoute（如
`Navigator.push(PageRouteBuilder(opaque: false, barrierColor: transparent, ...))`），
但项目里可能仍有 `showDialog<void>(builder: ...)` 调用方未迁移。**保留外层
`Dialog.fullscreen(backgroundColor: Colors.transparent)` 兼容两种调用**：

- `showDialog` 调用方：Dialog.fullscreen 提供 fullscreen layout；
  ExtendedImageSlidePage 提供背景 alpha ramp + drag-to-dismiss。
- `Navigator.push(PageRouteBuilder(opaque: false))` 调用方：透明 PageRoute
  让 SlidePage backdrop 直接可见；Dialog.fullscreen 仅做 sizing 容器，无视觉
  副作用（其 backgroundColor 已设为 transparent）。

迁移调用方时可以平滑过渡（先迁 widget 内部 → 再迁调用方），不必一步到位。

#### Pattern-B: 双击 zoom 到 2× 需 caller-owned `AnimationController`

**Problem**: `ExtendedImage` 内置 `state.handleDoubleTap()` 默认行为是
**reset 到 `initialScale`**（即缩到 1.0），不是切换到 2.0×。要实现"双击放大到
2× / 再双击复位"必须 caller 自己驱动 scale 动画。

**Solution**: 每个 `_PreviewPage` 持自己的 `AnimationController` + `Animation<double>`，
在 `onDoubleTap` 回调里反复调 `state.handleDoubleTap(scale, doubleTapPosition)`:

```dart
class _PreviewPage extends StatefulWidget { ... }

class _PreviewPageState extends State<_PreviewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _doubleTapAc;
  Animation<double>? _scaleAnim;
  ExtendedImageGestureState? _gestureState;
  TapDownDetails? _lastDownDetails;

  @override
  void initState() {
    super.initState();
    _doubleTapAc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      final s = _gestureState;
      final a = _scaleAnim;
      if (s == null || a == null || _lastDownDetails == null) return;
      s.handleDoubleTap(scale: a.value, doubleTapPosition: _lastDownDetails!.globalPosition);
    });
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    _gestureState = state;
    final current = state.gestureDetails?.totalScale ?? 1.0;
    final begin = current;
    final end = current > 1.01 ? 1.0 : 2.0; // toggle
    _scaleAnim = Tween<double>(begin: begin, end: end)
        .animate(CurvedAnimation(parent: _doubleTapAc, curve: Curves.easeOutCubic));
    _doubleTapAc..reset()..forward();
  }
  // ...
}
```

**Why**: ext 把双击的语义留给调用方决定（reset / toggle / continuous zoom 等
都合理）；提供 `handleDoubleTap(scale, doubleTapPosition)` 这样一个底层 API
让调用方按需驱动。**焦点 clamping 是免费的** —— 当 `doubleTapPosition` 落在
缩放后图片可见区之外，ext 内部自动 fallback 到图像中心（不再需要自实现
`_resolveFocalPoint` letterbox 降级）。

#### When NOT to use this pattern

- 单图、无需 drag-to-dismiss、只需 zoom/pan：直接 `InteractiveViewer` 仍然
  是更轻量的选择。
- 需要旋转 / 裁剪 / 滤镜等 `ExtendedImageMode.editor` 能力：本 pattern 不覆盖
  editor mode 的 widget tree。
- 网络图加载 + 缓存：`ExtendedImage.network` 加载 + `loadStateChanged` 自定义
  占位是另一个独立用法，不在本 pattern 范围内。

#### References

- ADR-0001 (Superseded by ADR-0002): `docs/adr/0001-immersive-page-scroll-physics.md`
- ADR-0002 (Current): `docs/adr/0002-extended-image-fullscreen-preview.md` (ST4)
- 参考实现: `lib/features/export/presentation/widgets/preview_full_screen_dialog.dart`
- 历史 PoC（最终 ST4 cleanup）: `lib/_poc/extended_image_poc.dart`
- 研究档案: `.trellis/tasks/archive/2026-05/05-22-brainstorm-fullscreen-preview-extended-image/research/extended_image-{overview,gallery-api,gesture-and-slide}.md`
  （任务 archive 后路径会变 — 用 `git log` 或 `find .trellis/tasks/archive -name "extended_image-*.md"` 定位）

---

## Best Practices

1. **Always use `const`** when possible for performance
2. **Extract reusable widgets** to `core/widgets/` or feature widgets
3. **Keep build methods simple** - move logic to providers
4. **Use `Theme.of(context)`** instead of hardcoded values
5. **Provide tooltips** for icon buttons
6. **Test widgets** in `test/` with descriptive test names
