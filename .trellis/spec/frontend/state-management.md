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
