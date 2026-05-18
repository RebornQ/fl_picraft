# State Management

> How state is managed in this project.

---

## Overview

This project uses **Riverpod** for state management, following Clean Architecture principles.

State layers:
- **UI State** → Widgets (ephemeral, local to widget)
- **Application State** → Riverpod providers (shared across widgets)
- **Domain State** → Entities (business data)
- **Data State** → Models/DTOs (persistence/API)

---

## State Categories

### Local Widget State

Use `StatefulWidget` for ephemeral state that:
- Doesn't need to persist
- Doesn't need to be shared
- Is only relevant to one widget

```dart
class ExpandableCard extends StatefulWidget {
  @override
  State<ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<ExpandableCard> {
  bool _isExpanded = false;  // Local state

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      expanded: _isExpanded,
      onExpansionChanged: (expanded) {
        setState(() => _isExpanded = expanded);
      },
    );
  }
}
```

### Application State (Riverpod)

Use Riverpod providers for state that:
- Is shared across multiple screens/widgets
- Needs to persist during app lifecycle
- Involves async operations

```dart
// Shared cart state
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

// Accessible from any widget
class CartBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    return Badge(count: cart.itemCount);
  }
}
```

### Domain State (Entities)

Immutable business entities in `domain/entities/`:

```dart
// features/cart/domain/entities/cart_item.dart
class CartItem {
  const CartItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.price,
  });

  final String id;
  final String productId;
  final int quantity;
  final double price;

  // Immutable copyWith for updates
  CartItem copyWith({
    String? id,
    String? productId,
    int? quantity,
    double? price,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
    );
  }
}
```

---

## When to Use Global State

### Promote to Global (Riverpod) When:

1. **Cross-screen access**: Data needed in multiple screens
2. **Persistence needed**: State survives navigation
3. **Async operations**: Loading/error states
4. **Business logic**: Validation, transformation

### Keep Local When:

1. **Single widget**: Only used in one place
2. **Ephemeral**: Animation state, form input focus
3. **Simple**: Boolean flags, counters

### Decision Flow

```
Is state shared across widgets?
├── Yes → Riverpod provider
└── No
    └── Does it need to survive rebuilds?
        ├── Yes → Riverpod provider
        └── No → Local StatefulWidget state
```

---

## State Patterns

### Loading/Error/Data Pattern

Use `AsyncValue` or sealed classes:

```dart
// Using Riverpod AsyncValue
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final repository = ref.read(productRepositoryProvider);
  return repository.getProducts();
});

// In widget
class ProductList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) => ListView(children: products),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => ErrorWidget(message: err.toString()),
    );
  }
}
```

### Using Freezed for State

```dart
// features/auth/presentation/providers/auth_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_state.freerozen.dart';

@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.authenticated(User user) = AuthAuthenticated;
  const factory AuthState.unauthenticated() = AuthUnauthenticated;
  const factory AuthState.error(String message) = AuthError;
}
```

### Pattern: Preserve previous data during `AsyncLoading`

**Problem**: When an `AsyncNotifier` re-runs (refresh, append, retry), the
naive transition is `state = const AsyncLoading()`. This sets `valueOrNull`
to `null` for the duration of the in-flight request, so any widget that
reads the current data flickers to its empty/loading branch — even though
the previous data is still valid.

**Solution**: Use `AsyncLoading.copyWithPrevious(state)` to keep
`valueOrNull` populated while `isLoading` is `true`. Widgets can show a
non-blocking spinner over the existing list rather than blanking out.

**Wrong**:
```dart
Future<void> appendImport() async {
  state = const AsyncLoading();          // ← previous list disappears
  final result = await _repo.run();
  state = AsyncData(result);
}
```

**Correct**:
```dart
Future<void> appendImport() async {
  state = const AsyncLoading<List<ImportedImage>>()
      .copyWithPrevious(state);          // ← keeps the previous list visible
  final result = await _repo.run();
  state = AsyncData(result);
}
```

**Why**: Riverpod's `AsyncValue` has dedicated machinery for "loading on
top of existing data" exactly to avoid the blank-flash problem. Use it
whenever a re-run is expected to *augment* or *replace* an existing list,
not bootstrap an empty one. The first build (`build()` returning the
initial empty value) should still use plain `const AsyncLoading()` since
there is no previous data to preserve.

**When to use**:
- Append-style updates (paginated lists, import sessions, infinite scroll)
- Refresh triggered by user action (pull-to-refresh on a populated list)
- Retry after a transient failure when the last good value is still relevant

**When NOT to use**:
- Initial load (`build()` returns the first value)
- Operations that *invalidate* the previous data (logout, project switch)

### Pattern: Cross-screen handoff via Riverpod, not GoRouter `extra`

**Problem**: Screen A needs to pass a value (route source kind, selected item id, filter state) to Screen B. Two ways:

- GoRouter `extra`: `context.go('/b', extra: payload)` — looks idiomatic, payload travels with the navigation
- Riverpod `StateProvider` / `Notifier`: set the value before navigating; Screen B reads it via `ref.watch`

**Decision**: **Default to Riverpod** for any cross-screen state that should survive a hot reload, a web refresh, or a deep-link.

**Why GoRouter `extra` is risky**:

1. **`extra` is lost on web refresh**. The browser reloads the URL but the in-memory `extra` map is wiped. Screen B sees `null` and either crashes or silently falls back to a default — both bad.
2. **`extra` is lost on deep-link**. If the user shares the URL or hits it from a notification, `extra` is empty.
3. **`extra` is typed as `Object?`**. Every consumer has to `as MyType` cast it. Riverpod providers carry their type all the way through.
4. **`extra` is invisible to other screens**. If a sibling widget (e.g. a bottom nav badge) needs to know "did we come from grid?", it can't ask the router — but it can `ref.watch` the provider.

**How to apply** (concrete example — Round 2a of `polish-platform-test`):

```dart
// lib/features/export/presentation/providers/export_dispatch.dart
final currentExportSourceKindProvider = StateProvider<ExportSourceKind>(
  (_) => ExportSourceKind.stitch,
);

// stitch_editor_screen.dart — caller sets kind then navigates
void _onExportPressed() {
  ref.read(currentExportSourceKindProvider.notifier).state =
      ExportSourceKind.stitch;
  context.go('/export');
}

// grid_editor_screen.dart — same pattern, different value
void _onExportPressed() {
  ref.read(currentExportSourceKindProvider.notifier).state =
      ExportSourceKind.grid;
  context.go('/export');
}

// export_screen.dart — consumer reads typed value
@override
Widget build(BuildContext context, WidgetRef ref) {
  final kind = ref.watch(currentExportSourceKindProvider);
  // ... renders source-specific UI
}
```

**When GoRouter `extra` is fine**: ephemeral hand-offs that genuinely should not survive a refresh — e.g. a "confirm delete" intermediate screen that loses meaning on reload. In practice, those are rare; when in doubt, use Riverpod.

**Trade-offs to accept**:

- The provider state is **sticky** — it stays put until someone else writes it. If the user navigates `grid → /export → home → /export` (deep-link), the second visit still shows `grid` until something resets it. This is usually the right behavior (user just left grid; they expect to see grid context). Document the policy in the provider's doc-comment.
- Reset on logout / project switch / "new project" must be explicit (call `ref.invalidate(currentExportSourceKindProvider)`) — same as any other sticky state.

**Required tests**: assert (a) caller writes the right kind before navigating; (b) consumer reads the kind from the provider, not from `GoRouterState.extra`; (c) the provider's default value is sane (whichever editor is "default" when the user deep-links into `/export` directly).

### Pattern: Per-mode session isolation via `.family`

**Problem**: Two (or more) top-level editor modes need the same underlying behavior — e.g. "import images, hold them as a session, accept add / remove / reorder / clear" — but each mode must keep its own independent state. Long-stitch and grid-split both consume the result of an image picker / drag-drop / clipboard paste, but they are conceptually different workspaces: the user expects the imports they collected for stitch mode to survive a quick visit to grid mode (and vice versa), and a failure surfaced in one mode must never produce a snackbar in the other.

A naive single global `AsyncNotifierProvider<List<ImportedImage>>` collapses both sessions into one bucket:

- Importing 3 images in stitch and switching to grid leaks the same 3 images into grid (cross-mode contamination)
- A `pickFromGallery` failure in stitch flips the controller to `AsyncError`; any grid-side `ref.listen` for SnackBars fires too (cross-mode error storm)
- Closing one mode (`clear()`) wipes the other mode's session

**Solution**: convert the controller to a Riverpod **family** keyed by a typed enum of modes. Each call to `provider(kind)` resolves to a separate notifier instance with its own state and its own `AsyncValue`. Tests and editor screens look up the family instance that matches their mode; the controller body is identical across instances.

```dart
// lib/features/image_import/domain/entities/image_import_session_kind.dart
enum ImageImportSessionKind { stitch, grid }

// lib/features/image_import/presentation/providers/image_import_provider.dart
class ImageImportController
    extends FamilyAsyncNotifier<List<ImportedImage>, ImageImportSessionKind> {
  @override
  Future<List<ImportedImage>> build(ImageImportSessionKind kind) async {
    // `kind` is only a cache key — the controller body is identical
    // across instances. Each kind just gets its own storage.
    return const [];
  }
  // ... pickFromGallery / addFromDrop / reorder / clear ...
}

final imageImportControllerProvider =
    AsyncNotifierProvider.family<
      ImageImportController,
      List<ImportedImage>,
      ImageImportSessionKind
    >(ImageImportController.new);

final importedImagesProvider =
    Provider.family<List<ImportedImage>, ImageImportSessionKind>((ref, kind) {
      return ref.watch(imageImportControllerProvider(kind)).valueOrNull ??
          const [];
    });
```

**Caller**:

```dart
// Stitch editor screen — every call site picks the .stitch instance
ref.listen<AsyncValue<List<ImportedImage>>>(
  imageImportControllerProvider(ImageImportSessionKind.stitch),
  (prev, next) { /* SnackBar on AsyncError */ },
);

// The drop-zone widget makes the choice required so callers can't
// forget which session a drop belongs to:
ImageDropZone(
  sessionKind: ImageImportSessionKind.stitch,  // required, no default
  child: _StitchEditorBody(),
);
```

**Test override pattern** (per-kind, so a single test can stub one mode and leave the other empty):

```dart
ProviderScope(
  overrides: [
    importedImagesProvider(
      ImageImportSessionKind.stitch,
    ).overrideWith((ref) => stubbedImages),
    importedImagesProvider(
      ImageImportSessionKind.grid,
    ).overrideWithValue(const []),
  ],
  child: ...,
);
```

**When to use**:

- Multiple top-level modes / workspaces share behavior but must keep independent state
- A failure in one mode must not surface as a UI side-effect in another
- The user's expectation is "switch back later and find my work where I left it" per mode

**When NOT to use**:

- The state genuinely is global (e.g. "current logged-in user") — a family adds ceremony without benefit
- The mode is ephemeral (e.g. a transient dialog open / close flag) — local widget state is fine
- The number of kinds is unbounded (e.g. per-document state) — use a different mechanism (e.g. a `Map<DocId, State>` inside a single notifier) so eviction is explicit

**Trade-offs to accept**:

- **Family key stability is load-bearing**. The enum value names become part of the Riverpod cache key. Renaming a value silently invalidates every test override that targets that key and any persisted reference. Lock value names with a stability note in the enum's dartdoc; add new values without touching old ones.
- **Tests need the family arg everywhere**. `imageImportControllerProvider.notifier` → `imageImportControllerProvider(.stitch).notifier`. Plan the migration as a single rename pass; mixed-mode tests get noisier.
- **Cross-mode helpers go through a typed bridge**. If a sibling enum (e.g. `ExportSourceKind`) needs to map to / from the session kind, define a single explicit `sessionKindFor(...)` function rather than coupling the two types. See `lib/features/export/presentation/providers/export_dispatch.dart` for the convention.
- **Memory**: every `.family` instance lives until the container is disposed unless `.autoDispose` is added. For a bounded enum (one entry per editor) this is fine. For unbounded keys you must opt into `.autoDispose` or evict manually.

**Don't**:

- Don't introduce a third instance just because you need a one-off bypass — e.g. the grid editor's nine-grid-social "center image" pick deliberately goes through the **repository** (`imageImportRepositoryProvider.pickFromGallery`) rather than the import controller, because that pick is a peer flow that must NOT populate the grid session. Reach for the bypass before adding `ImageImportSessionKind.gridCenterImage`. See `code-reuse-thinking-guide.md` → "Pattern: Side-Channel Reuse via Repository, Not Controller".

**Required tests** (per the pattern's intent):

- Per kind: the controller's existing behavior unit tests still pass when run against any one instance (use a single representative kind to avoid duplication; the controller body is identical).
- Cross-kind isolation: assert (a) imports into kind A don't appear in kind B; (b) `lastWarning` is per-instance; (c) `clear()` on one doesn't touch the other; (d) `AsyncError` on one doesn't propagate to the other.
- Round-trip survival: build kind B's editor controller after populating kind A and assert kind A's state is intact (this guards the `StatefulShellRoute` tab-switch invariant).

**Where this lives**:
- Enum: `lib/features/image_import/domain/entities/image_import_session_kind.dart`
- Family providers: `lib/features/image_import/presentation/providers/image_import_provider.dart`
- Widget API that surfaces the choice to callers: `ImageDropZone(sessionKind: ...)`
- Bridge to a sibling enum: `sessionKindFor(ExportSourceKind)` in `export_dispatch.dart`
- Cross-kind isolation tests: `test/features/image_import/presentation/cross_mode_isolation_test.dart`

---

### Pattern: Mirror a family provider with `ref.listen` — guard the first-fire when resetting on an `empty → non-empty` edge

**Problem**: A feature controller (e.g. `StitchEditorController`, `GridEditorController`) mirrors the image-import family
provider so its own state stays in sync with picks / drops happening outside the editor's own surface. The standard shape
inside `build()` is:

```dart
final initial = ref.read(importedImagesProvider(kind));
ref.listen<List<ImportedImage>>(importedImagesProvider(kind), (prev, next) { /* sync */ });
return EditorState.initial().copyWith(images: initial);
```

This works as long as the listener only **mirrors** the list. But the moment the listener also needs to **react to an
edge** — most commonly: "reset a sticky, first-image-dependent parameter when the user clears all and picks a fresh
batch" — naïve `prev.isEmpty && next.isNotEmpty` is wrong, because on Riverpod's **first listener invocation `prev == null`**
(not `[]`). If the editor mounts onto an already-non-empty session and the first user action is to pick more images, the
listener fires once with `prev == null` and a stale "empty→non-empty" reading clobbers a value the user never intended
to reset.

**Solution**: AND the edge predicate with a snapshot of the editor's **own** state taken at the listener's call site.
The editor's `state.images` reflects what `build()` actually seeded; it is the source of truth for "did the editor ever
hold images before this fire?".

```dart
// lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart
ref.listen<List<ImportedImage>>(importedImagesProvider(kind), (prev, next) {
  // `prev == null` on the very first listener invocation (Riverpod
  // semantics) — so `prev.isEmpty` alone says "was empty" even when the
  // editor was actually seeded from a pre-existing session. AND with
  // `state.images.isEmpty` so the reset fires only on a real
  // user-driven "all cleared → pick again" transition.
  final wasEmpty = prev == null || prev.isEmpty;
  final shouldReset = wasEmpty && next.isNotEmpty && state.images.isEmpty;
  state = state.copyWith(
    images: next,
    subtitleBandHeightPercent: shouldReset
        ? kDefaultSubtitleBandHeightPercent
        : state.subtitleBandHeightPercent,
  );
});
```

**When this pattern applies**:

- A sticky parameter is semantically bound to a property of the *current first image* (e.g. its scaled height, its
  aspect ratio, its dominant color). A new batch invalidates the binding.
- The reset must NOT fire on append, reorder, or non-first removal — only on a true `empty → non-empty` re-entry.

**When NOT to use**:

- The listener only mirrors `next` into local state with no edge-driven side effect — the simpler shape used by
  `grid_editor_provider.dart`'s `_syncSourceFromImports` (which keys off `next` alone) is fine; no guard needed.
- The "edge" you care about is `non-empty → empty` instead. That direction is symmetric in `prev`/`next` and `prev`'s
  null case is safe because `next.isEmpty` doesn't depend on `prev` at all.

**Required tests** (the one that actually validates the guard is non-obvious):

- `empty → first image picked`: percent resets to default even if `setSubtitleBandHeightPercent` had previously customized it.
- `non-empty → append`: percent unchanged.
- `clear() → repick`, `remove-all-one-by-one → repick`: percent resets.
- `reorder` / `remove non-first`: percent unchanged.
- **First-fire guard**: pre-seed the import controller with a non-empty list *before* building the editor controller,
  then customize the percent, then add more images. The listener's first fire has `prev == null` + `next.isNotEmpty`
  but `state.images` is non-empty — assert the percent is **not** reset. Without the `state.images.isEmpty` guard this
  assertion fails; with it the test is genuine, not a tautology.

**Where this lives**:

- `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` — the listener with the guard.
- `test/features/long_stitch/presentation/providers/stitch_editor_provider_test.dart` — the first-fire guard test
  in particular.
- `lib/features/grid/presentation/providers/grid_editor_provider.dart` — counter-example (pure-mirror form, no guard
  needed).


---

## Common Mistakes

### ❌ Don't

```dart
// Mutating state directly
ref.read(userProvider).name = 'New Name';  // ❌

// Using global variables
User? currentUser;  // ❌

// Storing widgets in state
final widgetProvider = StateProvider<Widget>((ref) => Container());  // ❌

// Deeply nested state
class AppState {
  final AuthState auth;
  final UserState user;
  final SettingsState settings;
  final CartState cart;
}
```

### ✅ Do

```dart
// Create new state instance
ref.read(userProvider.notifier).updateName('New Name');  // ✅

// Use providers for global state
final currentUserProvider = StateProvider<User?>((ref) => null);  // ✅

// Store data, not widgets
final currentPageProvider = StateProvider<int>((ref) => 0);  // ✅

// Separate providers by feature
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(...);
final cartProvider = StateNotifierProvider<CartNotifier, CartState>(...);
```

---

## Best Practices

1. **Single source of truth**: Each piece of state has one owner
2. **Immutable state**: Always create new instances for updates
3. **Keep state minimal**: Only store what's needed
4. **Derive when possible**: Use `Provider` for computed values
5. **Dispose properly**: Use `.autoDispose` for cleanup
6. **Test state in isolation**: Test providers independently of widgets
