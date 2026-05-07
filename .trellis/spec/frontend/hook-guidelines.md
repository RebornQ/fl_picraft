# Provider Guidelines

> How Riverpod providers are used in this project.

---

## Overview

This project uses **Riverpod** for state management. Unlike React hooks, Riverpod uses **providers** to manage state.

Key concepts:
- **Providers** declare state
- **ConsumerWidget** reads providers
- **ref.watch()** subscribes to state changes
- **ref.read()** reads without subscribing (for callbacks)

---

## Provider Types

### When to Use Each Type

| Provider Type | Use Case | Example |
|---------------|----------|---------|
| `Provider` | Read-only computed values | `ThemeProvider`, `ConfigProvider` |
| `StateProvider` | Simple mutable state | `CounterProvider`, `FilterProvider` |
| `StateNotifierProvider` | Complex state with logic | `AuthProvider`, `CartProvider` |
| `FutureProvider` | Async data fetching | `UserProfileProvider` |
| `StreamProvider` | Real-time data streams | `WebSocketProvider` |

### Examples

#### Simple State (StateProvider)

```dart
// providers/filter_provider.dart
final filterProvider = StateProvider<String>((ref) => 'all');

// Usage in widget
class FilterDropdown extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);

    return DropdownButton<String>(
      value: filter,
      items: ['all', 'active', 'completed']
          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
          .toList(),
      onChanged: (value) {
        ref.read(filterProvider.notifier).state = value!;
      },
    );
  }
}
```

#### Complex State (StateNotifierProvider)

```dart
// providers/auth_state.dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = AuthInitial;
  const factory AuthState.loading() = AuthLoading;
  const factory AuthState.authenticated(User user) = AuthAuthenticated;
  const factory AuthState.error(String message) = AuthError;
}

// providers/auth_provider.dart
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repository) : super(const AuthState.initial());

  final AuthRepository _repository;

  Future<void> login(String email, String password) async {
    state = const AuthState.loading();
    try {
      final user = await _repository.login(email, password);
      state = AuthState.authenticated(user);
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState.initial();
  }
}
```

#### Async Data (FutureProvider)

```dart
// providers/user_provider.dart
final userProvider = FutureProvider.family<User, String>((ref, userId) async {
  final repository = ref.read(userRepositoryProvider);
  return repository.getUser(userId);
});

// Usage in widget
class UserDetail extends ConsumerWidget {
  const UserDetail({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider(userId));

    return userAsync.when(
      data: (user) => Text(user.name),
      loading: () => const CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
```

---

## Provider Organization

### File Structure

```
features/
  auth/
    presentation/
      providers/
        auth_provider.dart      # Main provider + notifier
        auth_state.dart         # State class (with freezed)
```

### Provider Naming

| Provider Type | Naming Convention |
|---------------|-------------------|
| Main provider | `<feature>Provider` |
| State class | `<feature>State` |
| Notifier class | `<feature>Notifier` |
| Repository provider | `<feature>RepositoryProvider` |

---

## Common Patterns

### Dependency Injection

```dart
// core/providers/repository_providers.dart
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    localDataSource: ref.read(authLocalDsProvider),
    remoteDataSource: ref.read(authRemoteDsProvider),
  );
});

// In feature provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authRepositoryProvider),  // Inject repository
  );
});
```

### Computed State (Combining Providers)

```dart
// Derived state from multiple providers
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider);
  final filter = ref.watch(filterProvider);

  return products.where((p) {
    if (filter == 'all') return true;
    return p.status == filter;
  }).toList();
});
```

### Provider Modifiers

```dart
// .family - parameterized providers
final userProvider = Provider.family<User, String>((ref, userId) {
  return UserRepository.getUser(userId);
});

// .autoDispose - clean up when not used
final searchResultsProvider = StateProvider.autoDispose<List<Result>>((ref) {
  return [];
});
```

---

## Common Mistakes

### ❌ Don't

```dart
// Using ref.watch in callbacks (causes rebuild)
onPressed: () {
  ref.watch(authProvider);  // ❌
}

// Not using const with providers
final counterProvider = StateProvider<int>((ref) => 0);
// Missing provider scope in tests

// Over-using StateProvider for complex logic
final authProvider = StateProvider<AuthState>((ref) => AuthInitial());  // ❌
```

### ✅ Do

```dart
// Use ref.read in callbacks
onPressed: () {
  ref.read(authProvider.notifier).login();  // ✅
}

// Use StateNotifier for complex state
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();  // ✅
});

// Wrap tests with ProviderScope
void main() {
  testWidgets('auth test', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MyApp(),
      ),
    );
  });
}
```

---

## Testing Providers

```dart
void main() {
  test('auth provider login success', () async {
    // Create container for testing
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(MockAuthRepository()),
      ],
    );

    // Read notifier
    final notifier = container.read(authProvider.notifier);

    // Test initial state
    expect(container.read(authProvider), const AuthState.initial());

    // Trigger action
    await notifier.login('test@test.com', 'password');

    // Verify state change
    expect(container.read(authProvider), isA<AuthAuthenticated>());

    container.dispose();
  });
}
```
