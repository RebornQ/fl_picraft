# Quality Guidelines

> Code quality standards for Flutter development.

---

## Overview

This project follows Flutter best practices with strict linting via `flutter_lints` and additional team conventions.

Quality bar:
- **All warnings must be fixed** (no ignored lints)
- **Tests required** for business logic
- **Code review** for all PRs

---

## Linting Rules

### Active Rules (via `flutter_lints`)

The project uses `flutter_lints` which includes:

| Rule | Description |
|------|-------------|
| `avoid_print` | Warn on `print()` calls (use logging instead) |
| `prefer_const_constructors` | Require const where possible |
| `prefer_const_declarations` | Const for compile-time constants |
| `prefer_final_locals` | Final for local variables |
| `avoid_unnecessary_containers` | Reduce widget tree depth |
| `prefer_single_quotes` | Single quotes for strings |
| `sort_child_properties_last` | Child as last property |

### Running Lints

```bash
# Check for issues
flutter analyze

# Auto-fix where possible
dart fix --apply
```

---

## Forbidden Patterns

### Widget Anti-patterns

```dart
// ❌ Unnecessary Container
Container(
  child: Text('Hello'),
)

// ✅ Direct child
Text('Hello')

// ❌ Missing const
return Text('Hello');

// ✅ Const constructor
return const Text('Hello');

// ❌ Nested logic in build
@override
Widget build(BuildContext context) {
  if (condition) {
    return Widget1();
  } else {
    return Widget2();
  }
}

// ✅ Extract to method/widget
@override
Widget build(BuildContext context) {
  return _buildContent();
}

Widget _buildContent() {
  if (condition) {
    return const Widget1();
  }
  return const Widget2();
}
```

### State Management Anti-patterns

```dart
// ❌ Global mutable state
List<User> users = [];

// ✅ Provider-managed state
final usersProvider = StateProvider<List<User>>((ref) => []);

// ❌ Business logic in widgets
void _handleSubmit() {
  if (email.isValidEmail && password.length >= 8) {
    api.login(email, password);
  }
}

// ✅ Business logic in providers/notifiers
class AuthNotifier extends StateNotifier<AuthState> {
  Future<void> login(String email, String password) async {
    // Validation + API call here
  }
}
```

### Build Method Anti-patterns

```dart
// ❌ Heavy computation in build
@override
Widget build(BuildContext context) {
  final filtered = items.where(filter).toList();  // Computed every frame
  return ListView(children: filtered);
}

// ✅ Compute once with provider
@override
Widget build(BuildContext context, WidgetRef ref) {
  final filtered = ref.watch(filteredItemsProvider);
  return ListView(children: filtered);
}
```

---

## Required Patterns

### Code Organization

1. **Imports sorted alphabetically**
2. **Constants at top of file**
3. **Private members before public**
4. **Related methods grouped together**

```dart
// 1. Imports (sorted)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/core/widgets/app_button.dart';
import 'package:my_app/features/auth/providers/auth_provider.dart';

// 2. Constants
const double _kDefaultPadding = 16.0;

// 3. Widget class
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Private state
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  // Build method
  @override
  Widget build(BuildContext context) {
    return Scaffold(/* ... */);
  }

  // Helper methods
  void _handleSubmit() {/* ... */}

  // Lifecycle
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
```

### Error Handling

```dart
// Always handle errors in async operations
Future<void> fetchData() async {
  try {
    final data = await repository.getData();
    state = Success(data);
  } on NetworkException catch (e) {
    state = Error('Network error: ${e.message}');
  } on CacheException catch (e) {
    state = Error('Cache error: ${e.message}');
  } catch (e) {
    state = Error('Unexpected error: $e');
  }
}
```

---

## Testing Requirements

### What to Test

| Component | Test Type | Required |
|-----------|-----------|----------|
| Providers/Notifiers | Unit tests | ✅ Yes |
| Repositories | Unit tests | ✅ Yes |
| Use cases | Unit tests | ✅ Yes |
| Widgets | Widget tests | Recommended |
| Screens | Widget tests | Optional |

### Test File Structure

```
test/
  features/
    auth/
      providers/
        auth_provider_test.dart
      repositories/
        auth_repository_test.dart
  core/
    widgets/
      app_button_test.dart
```

### Widget Test Pattern

```dart
void main() {
  group('LoginScreen', () {
    testWidgets('shows error for invalid email', (tester) async {
      // Arrange
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      // Act
      await tester.enterText(
        find.byKey(const Key('email_field')),
        'invalid-email',
      );
      await tester.tap(find.byKey(const Key('submit_button')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Invalid email'), findsOneWidget);
    });
  });
}
```

### Pattern: Performance benchmarks via `@Tags(['benchmark'])`

**What**: Place all performance benchmarks in `test/benchmarks/` and tag them with `@Tags(['benchmark'])`. Configure `dart_test.yaml` to skip the tag by default:

```yaml
# dart_test.yaml (repo root)
tags:
  benchmark:
    skip: "perf benchmark — run with --run-skipped --tags benchmark"
```

This means `flutter test` (the default CI invocation) **skips** benchmarks — they're locally-driven baselines, not CI gates. To run them: `flutter test --run-skipped --tags benchmark test/benchmarks/`.

**Why**:

1. Performance varies wildly across host machines (CI runner vs local M-series Mac); a hard deadline would flap.
2. Debug build benchmarks are **not** the production target — release builds are typically 2-4× faster. Benchmarks are a relative-improvement tool, not an absolute deadline gate.
3. Splitting benchmarks from unit tests lets each run independently with appropriate thresholds.

**Benchmark structure**:

```dart
@Tags(['benchmark'])
library;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stitch 20×(1920×1080) PNG export under loose budget', () async {
    // 1. Synthesize test inputs — don't depend on real files
    final stopwatch = Stopwatch()..start();
    final images = List.generate(20, (i) => _synthImage(1920, 1080, i));
    print('synth elapsed: ${stopwatch.elapsedMilliseconds} ms');

    // 2. Run the operation under test
    stopwatch.reset();
    final result = await renderer.render(images);
    print('render elapsed: ${stopwatch.elapsedMilliseconds} ms');
    print('output: ${result.length} bytes');

    // 3. Assert against a LOOSE budget (much higher than PRD target)
    //    Benchmark is a baseline tool, not a deadline gate.
    expect(stopwatch.elapsed.inSeconds, lessThan(30));
  });
}
```

The PRD target (e.g. 5s) is for **release build on a real device** — verified manually per the task's `manual-test-plan.md`, not in benchmark tests. The benchmark threshold is loose (30s) so the test passes even on a slow host; what matters is the per-stage `print` output.

**When to run**:
- Locally after a renderer-layer change, to confirm no regression vs the recorded baseline
- After a candidate optimization, to measure improvement
- **Not** in CI by default — the tag-skip prevents flaky CI failures from host variance

### Pattern: `dart:developer` Timeline markers in renderers

**What**: Wrap CPU-heavy stages in `Timeline.startSync(label) ... Timeline.finishSync()` (or `Timeline.timeSync` for synchronous regions). This makes the stage show up in DevTools Timeline view, so you can see exactly where time is spent without recompiling.

```dart
import 'dart:developer' show Timeline;

class StitchImageRenderer {
  Future<Uint8List> render(StitchRenderRequest request) async {
    Timeline.startSync('stitch.decode');
    final decoded = await _decodeAll(request.images);
    Timeline.finishSync();

    Timeline.startSync('stitch.compose');
    final composed = _compose(decoded, request.mode);
    Timeline.finishSync();

    Timeline.startSync('stitch.encode');
    final bytes = _encode(composed, request.format);
    Timeline.finishSync();

    return bytes;
  }
}
```

**Naming convention**: `<feature>.<stage>` (e.g. `stitch.decode`, `grid.cell-render`, `export.save`). The dot-separated form groups related stages together in DevTools.

**Why this is free in production**:

- `dart:developer` calls are **stripped in release builds** — no runtime cost, no measurement overhead.
- In debug / profile mode, Timeline events are recorded with very low overhead (microseconds per call).

**Use `try / finally` for async safety**:

```dart
Timeline.startSync('stitch.encode');
try {
  return await _encodeAsync(image);
} finally {
  Timeline.finishSync();  // never leaks an unmatched startSync
}
```

**Where to add markers**: the entry point of every async operation in `data/renderers/` and `data/repositories/` that takes >100 ms in the typical case. Don't pepper them everywhere — the value is in stage-level granularity (decode / compose / encode), not statement-level.

---

## Code Review Checklist

### Before Submitting PR

- [ ] `flutter analyze` passes with no warnings
- [ ] `dart format .` applied
- [ ] `flutter test` passes
- [ ] No `print()` statements (use logging)
- [ ] No hardcoded values (use theme/constants)
- [ ] No `// TODO` without issue reference
- [ ] New code has tests

### Reviewer Checklist

- [ ] Code follows directory structure guidelines
- [ ] Widgets use `const` constructors where possible
- [ ] Business logic is in providers, not widgets
- [ ] Error handling is complete
- [ ] Accessibility labels present
- [ ] Tests cover new functionality

---

## Pre-commit Workflow

```bash
# Before every commit
flutter pub get        # Ensure dependencies
dart format .          # Format code
flutter analyze        # Check for issues
flutter test           # Run tests

# If all pass
git add .
git commit -m "feat: your feature description"
```

---

## Best Practices

1. **Fix warnings immediately** - Don't accumulate tech debt
2. **Write tests first** - TDD for business logic
3. **Keep functions small** - Single responsibility
4. **Use meaningful names** - `fetchUser` not `getData`
5. **Document public APIs** - Use `///` doc comments
6. **Handle edge cases** - Empty states, errors, loading
