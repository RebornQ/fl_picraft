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
