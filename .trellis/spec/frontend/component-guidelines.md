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

### Design Tokens (from DESIGN.md)

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#6750a4` | CTA buttons, key interactive elements |
| Secondary | `#625b71` | Chips, secondary actions |
| Tertiary | `#7d5260` | Highlights, badges |
| Neutral | `#79747e` | Backgrounds, surfaces |
| Font Family | Inter | All text |

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
