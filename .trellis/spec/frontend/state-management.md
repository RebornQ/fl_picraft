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

**Testing nuance — listener side-effects on a *third* provider don't fire on bare `container.read`**: when the
listener body writes to a separate `StateProvider` / `NotifierProvider` (e.g. `stitchControlsInlineVisibleProvider`
flipped by `stitch_editor_provider.dart`'s listener on an `empty → non-empty` edge), a `ProviderContainer` test that
only reads the **destination** provider sees stale values — the `Provider.family` derivation in the middle is lazy and
stays dirty until something reads it. The fix is a `read(controllerProvider)` "poke" between the trigger and the
assertion (see `quality-guidelines.md` → "Pattern: Poke the consumer to fire `ref.listen` side-effects on lazy
`Provider.family` derivations in `ProviderContainer` tests" for the helper, the symptom matrix, and the worked
example). The subtitle-reset tests next door don't trip on this because they assert on the controller's own `state`,
which inherently wakes the chain.

### Pattern: Atomic multi-field setter when fields are coupled

**Problem**: A controller exposes setters that each touch one field. When two fields are *coupled* — i.e. some combinations are semantically illegal — calling `setA(...)` then `setB(...)` from a UI handler produces an intermediate state where the pair is in an illegal combo. Consumers that re-render on every state change see one frame in that illegal combo, which can:

- Flash the wrong preview (e.g. the layout algorithm reads the illegal pair and produces a garbage frame the user sees for one tick before the second setter "fixes" it).
- Trigger derived computations / `ref.listen` callbacks that interpret the illegal combo as a meaningful transition.

The naive fix is to write two `state = state.copyWith(...)` lines back-to-back inside the controller method. Each assignment is a separate emit; Riverpod broadcasts twice; the same intermediate-frame problem persists.

**Solution**: Provide a *named* atomic operation on the controller that performs the coupled update in **one** `state.copyWith(...)`. Keep the single-field setters public for cases where only one field is changing, but call sites must use the atomic operation when the fields are semantically coupled.

```dart
// lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart

class StitchEditorController extends Notifier<StitchEditorState> {
  // ❌ Wrong — two emits; consumers see (vertical, subtitleOnlyMode=true)
  // for one frame before the second emit lands as (horizontal, false).
  void toggleOrientationWrong() {
    setMode(state.mode == StitchMode.vertical
        ? StitchMode.horizontal
        : StitchMode.vertical);
    if (state.mode == StitchMode.horizontal) {
      setSubtitleOnlyMode(false);
    }
  }

  // ✅ Correct — single emit; coupled fields move together.
  void toggleOrientation() {
    state = switch (state.mode) {
      StitchMode.vertical => state.copyWith(
          mode: StitchMode.horizontal,
          // Subtitle mode is meaningless in horizontal; clear it in the
          // same emit so consumers never see the illegal pair.
          subtitleOnlyMode: false,
        ),
      StitchMode.horizontal => state.copyWith(mode: StitchMode.vertical),
    };
  }

  void selectMovieSubtitleMode() {
    // Subtitle mode requires vertical; flipping just `subtitleOnlyMode`
    // would yield (horizontal, true) for one frame if the caller was in
    // horizontal. Emit both at once.
    state = state.copyWith(
      subtitleOnlyMode: true,
      mode: StitchMode.vertical,
    );
  }
}
```

**Required tests**: assert the coupled setter emits **exactly once** with a single listener subscription, not twice — otherwise a refactor that splits the `copyWith` back into two assignments silently regresses to the intermediate-frame bug.

```dart
test('selectMovieSubtitleMode emits once with both fields updated', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final emitted = <StitchEditorState>[];
  container.listen<StitchEditorState>(
    stitchEditorControllerProvider,
    (_, next) => emitted.add(next),
  );
  container
      .read(stitchEditorControllerProvider.notifier)
      .setMode(StitchMode.horizontal);
  emitted.clear();

  container
      .read(stitchEditorControllerProvider.notifier)
      .selectMovieSubtitleMode();

  expect(emitted, hasLength(1));               // single emission
  expect(emitted.single.mode, StitchMode.vertical);
  expect(emitted.single.subtitleOnlyMode, isTrue);
});
```

**When to use**:
- Two or more state fields whose combinations have explicit semantic constraints (e.g. "X requires Y", "X is meaningless when Y").
- A UI gesture is conceptually one action ("enter subtitle mode") even though it has to touch multiple fields to land.

**When NOT to use**:
- Fields are independent; chaining single setters is fine.
- The "intermediate state" is itself a legal state the consumer should observe (e.g. a multi-step wizard where each step is meaningful).

**Reference**: `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart` — `toggleOrientation` / `selectMovieSubtitleMode` / `selectNormalMode`; covered by `test/features/long_stitch/presentation/providers/stitch_editor_provider_atomic_setters_test.dart`.

### Pattern: Inject isolate-bound functions through a typedef + Provider for testability

**Problem**: A controller depends on a function that hops to a background isolate via
`compute(...)`. Production callers want the real isolate hop; tests want a synchronous fake
so `FakeAsync` can advance the debounce / cache / pause-gate timeline and assertion helpers
can count calls. Calling the production function directly from the controller makes both
goals impossible:

- `FakeAsync` cannot advance time inside a real isolate
- The Flutter binding is not initialized in unit tests, so `compute` throws (or you rely
  on a fallback to sync, which defeats the test's intent of asserting "the controller
  called the function exactly once")

**Solution**: Define a `typedef` for the function signature and expose a `Provider` that
returns the production implementation. The controller reads the function through the
provider; tests `overrideWithValue` a synchronous fake.

```dart
// lib/features/export/data/preview_renderer.dart
typedef ProcessBytesFn = Future<Uint8List> Function({
  required Uint8List source,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
});

Future<Uint8List> processExportBytes({...}) async {
  // Real implementation: compute(_processExportInIsolate, _ProcessExportRequest(...))
}

// lib/features/export/presentation/providers/process_bytes_fn.dart
final processBytesFnProvider = Provider<ProcessBytesFn>((_) => processExportBytes);

// In the controller — never call processExportBytes directly
final processFn = ref.read(processBytesFnProvider);
final bytes = await processFn(source: src, watermark: wm, format: fmt, quality: q);

// In the test — override with a synchronous, counted fake
var callCount = 0;
ProviderScope(
  overrides: [
    processBytesFnProvider.overrideWithValue(({required source, required watermark,
        required format, required quality}) async {
      callCount++;
      return Uint8List.fromList([1, 2, 3]);
    }),
  ],
  child: ...,
);
// Now `FakeAsync` can advance debounce timers; `callCount` proves dedup works.
```

**When to use**: any controller whose hot path goes through `compute()`, `Isolate.spawn`,
or other isolation-bound primitives that defeat `FakeAsync`.

**Reference**: `lib/features/export/presentation/providers/process_bytes_fn.dart`;
`test/features/export/presentation/providers/preview_controller_test.dart`.

### Pattern: `NotifierProvider<SealedState>` when the sealed already owns loading/error

**Problem**: A controller has four states — *empty*, *loading*, *ready*, *error* — and the
natural model is a Dart 3 sealed class:

```dart
sealed class PreviewState {}
class PreviewEmpty extends PreviewState { ... }
class PreviewLoading extends PreviewState { final List<Uint8List>? staleBytes; ... }
class PreviewReady extends PreviewState { final List<Uint8List> bytes; ... }
class PreviewError extends PreviewState { final String message; ... }
```

The instinct is to reach for `AsyncNotifierProvider<_, PreviewState>` because the renderer
is async. **Don't.** `AsyncValue<PreviewState>` produces a 4×4 cartesian product on the
consumer side, because `AsyncValue` *also* expresses loading / error:

```dart
// Anti-pattern — double expression of loading/error
asyncState.when(
  loading: () => /* what does this even mean if the sealed has PreviewLoading? */,
  error: (e, _) => /* and this? sealed has PreviewError too! */,
  data: (state) => switch (state) {
    PreviewEmpty() => ...,
    PreviewLoading() => /* unreachable in theory, but compiler still demands it */,
    PreviewReady() => ...,
    PreviewError() => /* unreachable in theory, but compiler still demands it */,
  },
);
```

The two "unreachable" branches are real footguns: anyone refactoring later may accidentally
route through them, and exhaustiveness checks force you to write them anyway.

**Solution**: Use `NotifierProvider<Controller, SealedState>`. The controller's `Future`
work is internal; the consumer sees a flat `PreviewState` and switches once:

```dart
class PreviewController extends Notifier<PreviewState> {
  @override
  PreviewState build() => const PreviewEmpty();

  Future<void> _runRender() async {
    state = const PreviewLoading();
    try {
      final bytes = await processFn(...);
      state = PreviewReady(bytes: bytes, ...);
    } catch (e) {
      state = PreviewError(message: '...', ...);
    }
  }
}

final previewControllerProvider =
    NotifierProvider<PreviewController, PreviewState>(PreviewController.new);

// Consumer — one level, exhaustive
final state = ref.watch(previewControllerProvider);
return switch (state) {
  PreviewEmpty() => _EmptyView(),
  PreviewLoading(:final staleBytes) => _LoadingView(stale: staleBytes),
  PreviewReady(:final bytes, :final totalSizeBytes) => _ReadyView(...),
  PreviewError(:final message, :final staleBytes) => _ErrorView(...),
};
```

**Heuristic**: if your sealed already enumerates the loading/error/empty cases, never wrap
it in `AsyncValue`. Choose either:

- **`NotifierProvider<SealedState>`** when the sealed owns all states (preferred when the
  state machine is rich — e.g. carries `staleBytes`, partial progress, attempt count)
- **`AsyncNotifierProvider<RawData>`** when the data type is plain (`List<Foo>` etc.) and
  you genuinely want `AsyncValue` to express loading/error — see the
  *Preserve previous data during `AsyncLoading`* pattern above

**Reference**: `lib/features/export/presentation/providers/preview_controller.dart`
(`NotifierProvider<PreviewController, PreviewState>`).


---

## Common Mistakes

### ❌ Don't: cache by `identityHashCode(bytes)` when the source produces fresh `Uint8List` each call

**Symptom**: A cache that "should obviously hit" never does. Every controller rebuild,
every consumer re-fetch, re-runs the expensive isolate work.

**Cause**: The data source (e.g. a renderer `Future<Uint8List> render(...)`) returns
`Uint8List.fromList(...)` — a fresh allocation every call. `identityHashCode(bytes)` is
therefore different on each call even when the *content* is identical.

**Fix**: Key the cache on an immutable upstream state's `hashCode`, not on the produced
bytes:

```dart
// ❌ Wrong — bytes identity changes every call
final key = Object.hash(sourceKind, identityHashCode(sourceBytes), watermark, format, quality);

// ✅ Correct — hash the immutable editor state that produced the bytes
final key = Object.hash(sourceKind, editor.state.hashCode, watermark, format, quality);
```

**Prevention**: when designing a cache key for derived bytes (encoded images, hashed
payloads, serialized blobs), trace back to the **immutable input** that produced them.
Make sure that input has a proper structural `hashCode` (full field hash via `Object.hash`
+ `Object.hashAll` for list fields, with element types that themselves have stable
hashes — avoid `bytes.length`-only shortcuts when length collisions matter; use
identity-fields like timestamps or source paths instead).

**Reference**: `lib/features/export/presentation/providers/processed_bytes_cache.dart`
and `preview_controller.dart` use `StitchEditorState.hashCode` / `GridEditorState.hashCode`
(both have complete field hashes) rather than `identityHashCode(sourceBytes)`.

### ❌ Don't: rely on async dependency-listens to set the initial state in a non-`autoDispose` controller

**Symptom**: User leaves a page, comes back — UI briefly **flashes the prior render**
(an old `PreviewReady` frame, an old `AsyncData`, an old computed widget) for ~300 ms
before transitioning into the correct new state (typically `Loading`). Looks like a
"glitch" on every re-mount when there's already a cached result.

**Cause**: Two compounding pieces of Riverpod behavior:

1. A `NotifierProvider` (without `.autoDispose`) keeps the controller instance AND its
   `state` alive across consumer mount/unmount cycles. Returning to the page → first
   `ref.watch` immediately yields whatever `state` was when the user last left.
2. `build()` returns `PreviewEmpty` (or some "neutral" initial state), then registers
   `ref.listen(...)` callbacks that re-fire `_scheduleRender()` after the build returns.
   The render itself is async (debounce timer + isolate hop), so the state stays at the
   old `PreviewReady` until the next render lands — that's the "flash" window.

If you wrap the controller in `AsyncNotifierProvider` instead, you get the same problem
with the `AsyncValue.previous` payload — `previous` survives across mounts, the consumer
sees it on the first frame, and the new request only updates the state seconds later.

**Fix**: make `build()` **synchronously compute** the correct initial state from
whatever caches / current inputs the controller has access to — don't rely on async
listens to "catch up" afterwards.

```dart
// ❌ Wrong — build() returns a neutral state, async listens correct it later.
@override
PreviewState build() {
  ref.listen(deps, (_, _) => _scheduleRender());
  _scheduleRender();              // async — debounce timer hasn't fired yet
  return const PreviewEmpty();    // ← consumer sees Empty (or stale prior state!) for 300 ms
}

// ✅ Correct — build() consults the same caches the async path would, decides the
// initial state synchronously, only kicks off the async render if needed.
@override
PreviewState build() {
  ref.listen(deps, (_, _) => _scheduleRender());

  final initial = _initialStateFromCache();   // synchronous: cache hit → Ready,
                                              // miss + has source → Loading,
                                              // no source → Empty
  if (initial is PreviewLoading) {
    // Queue the timer directly; do NOT call _scheduleRender() because Riverpod's
    // `state` getter throws when accessed before build() returns, and
    // _scheduleRender does state-checking.
    _debounce = Timer(kPreviewDebounce, _runRender);
  }
  return initial;
}
```

**Also fix the listen path** so a dependency change that diverges from the last
rendered key immediately pre-transitions the state to Loading instead of waiting for
the debounce:

```dart
void _scheduleRender() {
  if (ref.read(exportControllerProvider).isSaving) return;

  final key = _currentInputKey();
  if (key == null) {
    _debounce?.cancel();
    if (state is! PreviewEmpty) state = const PreviewEmpty();
    return;
  }
  // Pre-transition the moment inputs diverge from the last rendered key — kills
  // the stale-frame flash on re-mount when an outer listen fires asynchronously.
  if (key != _lastRenderedKey && state is! PreviewLoading) {
    state = PreviewLoading(staleBytes: _staleBytesFromState(state));
  }
  _debounce?.cancel();
  _debounce = Timer(kPreviewDebounce, _runRender);
}
```

**Riverpod gotcha (deviation noted in the implementation)**: `build()` cannot call
`_scheduleRender()` directly because the latter reads `state`, and Riverpod throws
`StateError('Tried to read the state of an uninitialized provider')` if anything
touches `state` before `build()` returns. Split the timer-queuing logic out and let
`build()` set the initial state via its return value, then queue the timer separately.

**Alternative fix** (when the controller doesn't need to survive across visits):
switch to `.autoDispose`, so the controller is destroyed on unmount and `build()`
runs fresh on remount. This sidesteps the stale-state issue but loses any per-instance
caches (`_cachedSource` etc.). The persistent caches that DO need to survive (the
result cache shared with `save`) should live in a separate provider that isn't
`autoDispose`. Pick whichever pattern fits the cache topology; both work.

**Prevention heuristic**: whenever a controller (a) is not `.autoDispose`, AND (b)
exposes a state whose validity depends on async-computed dependencies, ask the
question: *"What does the consumer see on the first frame of a re-mount?"* If the
answer is "whatever it was when I left," you need a synchronous `build()` that
recomputes the initial state from current inputs — never trust `ref.listen` callbacks
to update state before the consumer reads it for the first time.

**Reference**: `lib/features/export/presentation/providers/preview_controller.dart` —
`build()` consults `processedBytesCacheProvider` and the active editor state to
synchronously emit `PreviewReady` / `PreviewLoading` / `PreviewEmpty`;
`_scheduleRender` synchronously pre-transitions to `PreviewLoading` when the input
key has moved on. Tests:
`preview_controller_test.dart::cache-hit on first build → first emitted state is PreviewReady`
and `::input key change after PreviewReady immediately transitions to PreviewLoading`
lock in the contract.

### Pattern: Split lifecycle — autoDispose controller + non-autoDispose cache

**Problem**: A page-level controller owns expensive resources that should be released
when the user leaves the page (debounce timers, `ref.listen` callbacks, in-flight
`Future` handles, multi-MB cached source bytes). The intuitive fix is `.autoDispose`.
But the controller also writes to a **result cache** (LRU of processed bytes,
memoized network responses, etc.) that we want to **survive** across visits so a
re-mount can hit the cache and skip the expensive re-compute. If the cache lives
inside the controller's fields, `autoDispose` throws it away too — and the next visit
re-computes everything from scratch, defeating the cache.

The two desires pull in opposite directions:
- **Release page-level state on unmount** → prevents silent background work (listens
  re-fire while the page is offscreen, debounce timers schedule renders nobody sees,
  cached source bytes hold memory)
- **Keep the result cache alive across visits** → so the next mount is instant

**Solution**: split into **two providers** with different lifecycles. The cache lives
in its own provider that is **NOT** `autoDispose`; the controller is `autoDispose`
and reads/writes the cache provider on demand.

```dart
// 1. The cache lives in its own provider — survives across page visits.
class ProcessedBytesCache extends Notifier<Map<int, List<Uint8List>>> {
  // LRU map with capacity cap, read/write/invalidate API
}
final processedBytesCacheProvider =
    NotifierProvider<ProcessedBytesCacheNotifier, ProcessedBytesCache>(...);
//  ^^^^^^^^^^^^^^^^                                                 NOT autoDispose

// 2. The controller is autoDispose — released on unmount.
class PreviewController extends AutoDisposeNotifier<PreviewState> {
  @override
  PreviewState build() {
    ref.listen(deps, (_, _) => _scheduleRender());      // released on dispose
    ref.onDispose(() { _debounce?.cancel(); });          // released on dispose

    // Synchronously consult the surviving cache for the initial state.
    return _initialStateFromCache();
  }

  Future<void> _runRender() async {
    final cached = ref.read(processedBytesCacheProvider.notifier).read(key);
    if (cached != null) {                                // cache hit, skip compute
      state = PreviewReady(...);
      return;
    }
    final bytes = await processFn(...);                  // expensive
    ref.read(processedBytesCacheProvider.notifier).write(key, bytes);  // survives this controller
    state = PreviewReady(...);
  }
}

final previewControllerProvider =
    AutoDisposeNotifierProvider<PreviewController, PreviewState>(...);
//  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                                    autoDispose

// 3. Derived providers should match their dependency's autoDispose-ness.
final previewBytesProvider = Provider.autoDispose<List<Uint8List>>((ref) {
  return switch (ref.watch(previewControllerProvider)) {
    PreviewReady(:final bytes) => bytes,
    _ => const [],
  };
});
```

**When to use**: any expensive page-level compute that (a) has dependencies that
keep firing while the page is offscreen if the controller stays alive, OR (b) holds
multi-MB byte buffers / large derived state in controller fields. If only (b)
applies, you might just need to clear the fields on unmount — but if (a) applies,
`autoDispose` is the cleaner fix.

**Diagnostic symptom**: silent background CPU bursts after the user navigates away
("why is the device warming up?"), worst-case memory hold growing with visit count
(`adb shell dumpsys meminfo` shows your Riverpod container's retained byte buffers
ballooning).

**Why not just keep everything autoDispose**: if both the controller AND the cache
are autoDispose, the cache dies with the controller and every visit re-renders from
scratch — the cache provides zero value.

**Why not just keep everything non-autoDispose**: the controller's `ref.listen`
callbacks stay subscribed to its dependencies forever; any change in those
dependencies (slider drag in a sibling editor screen, watermark toggle, etc.)
silently fires `_scheduleRender` and the background isolate hop. Memory hold
grows. CPU burns.

**Don't forget**:
- Derived providers (e.g. `previewBytesProvider` above) should be `.autoDispose`
  too, matching the controller's lifecycle (Riverpod best practice).
- Test the contract: assert `identical(notifier1, notifier2) == false` after the
  last subscriber goes away, AND the cache survives across the dispose. The
  `_keepPreviewAlive(container)` helper pattern in
  `test/features/export/presentation/providers/preview_controller_test.dart` is
  load-bearing — without an explicit subscription, autoDispose disposes the
  controller mid-test and assertions on `_scheduleRender` etc. silently no-op.
- `ref.watch` in a Widget counts as a subscriber; the controller stays alive as
  long as the widget tree references it. autoDispose only fires when the LAST
  subscriber goes away.
- In-flight `compute()` results that arrive AFTER `autoDispose` are silently
  dropped by Riverpod (state assignment on a disposed notifier is a no-op).
  This is usually what you want for stale background renders.

**Reference**: `lib/features/export/presentation/providers/preview_controller.dart`
(`AutoDisposeNotifier`) + `processed_bytes_cache.dart` (non-autoDispose `Notifier`).
Audit and decision documented in
`.trellis/tasks/05-20-preview-ui/prd.md` §D8 (added 2026-05-21).

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
