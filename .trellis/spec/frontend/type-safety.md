# Type Safety

> Type safety patterns in this project (Dart).

---

## Overview

Dart has a sound type system with null safety. This project leverages:
- **Null safety** (`?` for nullable types)
- **Type inference** (`var`, `final`, `const`)
- **Generics** for type-safe collections
- **Sealed classes** for exhaustive pattern matching (Dart 3)

---

## Type Organization

### Where Types Live

| Type | Location |
|------|----------|
| Entities | `features/<feature>/domain/entities/` |
| DTOs/Models | `features/<feature>/data/models/` |
| State classes | `features/<feature>/presentation/providers/` |
| Shared types | `core/types/` or `core/models/` |
| Failures/Errors | `core/error/` |

### Type File Naming

```dart
// domain/entities/user.dart
class User { ... }

// data/models/user_model.dart
class UserModel extends User { ... }

// presentation/providers/auth_state.dart
@freezed
class AuthState with _$AuthState { ... }
```

---

## Null Safety

### Nullable vs Non-Nullable

```dart
// Non-nullable (always has a value)
String name;           // Must be initialized
final int count = 0;   // Can't be null

// Nullable (can be null)
String? nickname;      // Can be null
int? optionalValue;    // Use ?. for access
```

### Null Assertion vs Null Check

```dart
// ❌ Avoid null assertion (throws if null)
final name = user!.name;

// ✅ Use null check with default
final name = user?.name ?? 'Unknown';

// ✅ Use pattern matching
if (user case User(:final name)) {
  print(name);
}
```

### Late Initialization

```dart
// Use late for deferred initialization
class _MyState extends State<MyWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }
}
```

---

## Validation

### Form Validation

```dart
// Use validators in TextFormField
TextFormField(
  validator: (value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a value';
    }
    if (value.length < 3) {
      return 'Minimum 3 characters';
    }
    return null;  // Valid
  },
)
```

### Model Validation

```dart
class User {
  const User({
    required this.email,
    required this.name,
  });

  final String email;
  final String name;

  // Factory with validation
  static User? fromJson(Map<String, dynamic> json) {
    final email = json['email'] as String?;
    final name = json['name'] as String?;

    if (email == null || name == null) return null;
    if (!_isValidEmail(email)) return null;

    return User(email: email, name: name);
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}
```

---

## Common Patterns

### Sealed Classes (Dart 3)

Use sealed classes for exhaustive pattern matching:

```dart
// core/error/failure.dart
sealed class Failure {}

class NetworkFailure extends Failure {
  final String message;
  NetworkFailure(this.message);
}

class CacheFailure extends Failure {
  final String message;
  CacheFailure(this.message);
}

class ValidationFailure extends Failure {
  final Map<String, String> errors;
  ValidationFailure(this.errors);
}

// Usage with exhaustive matching
String getErrorMessage(Failure failure) {
  return switch (failure) {
    NetworkFailure(:final message) => 'Network error: $message',
    CacheFailure(:final message) => 'Cache error: $message',
    ValidationFailure(:final errors) => 'Validation failed',
  };
}
```

### Records (Dart 3)

```dart
// Named records for structured data
typedef GeoLocation = ({double lat, double lng});

final GeoLocation location = (lat: 37.7749, lng: -122.4194);
print('Lat: ${location.lat}, Lng: ${location.lng}');

// Positional records
typedef Point = (double x, double y);
final Point point = (10.0, 20.0);
```

### Generics

```dart
// Generic repository interface
abstract class Repository<T> {
  Future<T> getById(String id);
  Future<List<T>> getAll();
  Future<void> save(T entity);
  Future<void> delete(String id);
}

// Generic result type
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final String message;
  const Failure(this.message);
}
```

---

## Forbidden Patterns

### ❌ Don't

```dart
// Using dynamic
dynamic value = getData();  // ❌

// Ignoring null safety
String name = null;  // ❌ Compile error

// Type casting without checks
final user = data as User;  // ❌ Can throw

// Raw Map types
Map data = {};  // ❌
```

### ✅ Do

```dart
// Explicit types
User? value = getData();  // ✅

// Null safety
String? name = null;  // ✅

// Type checking
if (data is User) {
  final user = data;  // ✅ Smart cast
}

// Typed Map
Map<String, dynamic> data = {};  // ✅
```

---

## Type Utilities

### Extension Methods

```dart
// core/extensions/string_extensions.dart
extension StringExtensions on String {
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  }

  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

// Usage
final email = 'test@example.com';
if (email.isValidEmail) {
  print(email.capitalize);  // 'Test@example.com'
}
```

### Type Guards

```dart
// Using pattern matching
Object processValue(Object value) {
  return switch (value) {
    String s => 'String: $s',
    int i => 'Int: $i',
    List l => 'List with ${l.length} items',
    _ => 'Unknown type',
  };
}
```

---

## Best Practices

1. **Prefer non-nullable types** - Use `?` only when necessary
2. **Use type inference** - `final` and `var` reduce boilerplate
3. **Sealed classes for states** - Exhaustive pattern matching
4. **Validate at boundaries** - Check input from external sources
5. **Avoid `dynamic`** - Use `Object` or specific types
6. **Use `is` for type checks** - Avoid `as` without checking
