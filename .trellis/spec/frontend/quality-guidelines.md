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

### Pattern: Plain `test` over `testWidgets` for `AsyncNotifier`-only assertions

**Problem**: A test wants to assert provider-level behavior on an `AsyncNotifier` (family-instance isolation, `AsyncError` propagation across instances, `clear()` semantics). Wrapping it in `testWidgets` so you can `pumpWidget` introduces `FakeAsync` — and Riverpod's `AsyncNotifier` scheduler then complains about pending timers at teardown:

```
A Timer is still pending even after the widget tree was disposed.
```

This is **not** a bug in your code — it's the interaction between `FakeAsync` (which `testWidgets` installs) and the `AsyncNotifier` microtask scheduler. Pumping more (`tester.pumpAndSettle()`) doesn't always drain it because the scheduler can re-arm.

**Solution**: when the assertion target is the **provider's state**, not the widget tree, drop `testWidgets` and drive a manual `ProviderContainer` from a plain `test`:

```dart
test('stitch picks do not appear in grid session', () async {
  final container = ProviderContainer(overrides: [
    imageImportRepositoryProvider.overrideWithValue(_StubRepo()),
  ]);
  addTearDown(container.dispose);

  await container.read(
    imageImportControllerProvider(ImageImportSessionKind.stitch).future,
  );
  await container
      .read(imageImportControllerProvider(ImageImportSessionKind.stitch).notifier)
      .pickFromGallery();

  expect(
    container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
    hasLength(1),
  );
  expect(
    container.read(importedImagesProvider(ImageImportSessionKind.grid)),
    isEmpty,
  );
});
```

**When to use `testWidgets`**: the assertion target is the widget tree (a `SnackBar` surfaces, a button enables / disables, layout changes at a viewport size). The FakeAsync interaction is tolerable there because you're already pumping widgets and can `pumpAndSettle`.

**When to use plain `test` + `ProviderContainer`**:
- Family-instance isolation (provider A and provider B don't share state)
- `AsyncNotifier` state transitions in isolation (`AsyncLoading` → `AsyncError` → `AsyncData`)
- `Provider`-derived value sanity (`importedImagesProvider` reads correctly off the controller)
- Anything where the widget tree is incidental

**Where this lives** (current implementations):
- `test/features/image_import/presentation/cross_mode_isolation_test.dart` — cross-mode isolation uses plain `test` + `ProviderContainer`
- `test/features/image_import/presentation/image_import_controller_test.dart` — controller unit tests follow the same pattern

**Don't reach for `tester.pumpAndSettle()` to mask the timer leak** — it can pass on one machine and flake on CI. If the widget tree adds no value to the assertion, the right fix is dropping `testWidgets` entirely, not pumping harder.

### Pattern: Avoid `pumpAndSettle()` when the widget tree has an indefinite animation

**Problem**: A widget test wraps a tree that contains `CircularProgressIndicator`,
`LinearProgressIndicator`, an `AnimatedSwitcher` whose child cycles an indeterminate spinner,
or any other animation that loops forever. Calling `await tester.pumpAndSettle()` then **hangs
indefinitely** — it waits for frame quiescence, and an infinite animation never reaches it.
The test eventually times out with no useful failure message.

**Solution**: pump a **fixed duration** that covers all *finite* transitions you care about
(e.g. an `AnimatedSwitcher`'s 200 ms cross-fade) but does NOT try to wait for the indefinite
animation to stop:

```dart
// ❌ Hangs forever — PreviewSkeleton contains CircularProgressIndicator
await tester.pumpAndSettle();

// ✅ Drains the 200 ms AnimatedSwitcher cross-fade and any pending microtasks,
//    without waiting on the spinner that will never settle.
Future<void> _settleAnimatedSwitcher(WidgetTester tester) async {
  await tester.pump();                            // commit state change
  await tester.pump(const Duration(milliseconds: 250)); // > AnimatedSwitcher duration
}
```

**When the issue surfaces**:

- Sealed-state widgets where `PreviewLoading` / `LoadingChip` / a placeholder embeds a
  spinner that the production UI is meant to show during a render
- Any time a `Future.delayed` inside the widget never resolves under the test's
  `ProviderScope.overrides` (e.g. the fake renderer returns a `Completer().future`)
- `Hero` / page-transition tests where the route uses `AlwaysAnimating` transitions

**Heuristic**: if `pumpAndSettle()` hangs, search the widget tree under test for any
`Stream`-driven or repeating `AnimationController` (the Flutter built-ins like
`CircularProgressIndicator` are the usual suspects). Replace with `pump(fixedDuration)` keyed
to the longest finite transition you actually need to advance past.

**Reference**: `test/features/export/presentation/widgets/preview_card_test.dart` —
the `_settleAnimatedSwitcher` helper drains the 200 ms cross-fade without waiting on the
loading spinner that lives inside `PreviewSkeleton`.

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

**Refactor guardrail**: when a code path is restructured (e.g. extracted into an adapter, moved behind a new abstraction, batched into a stream), audit that every previously-instrumented stage still has its `Timeline.startSync(...)` marker on the **new** code path. The compiler can't catch a missing marker, but DevTools observability silently regresses — the most expensive path becomes invisible.

When the refactor introduces a new heavier sub-stage (e.g. ZIP compose in the Web batch adapter), add a nested marker following the `<feature>.<stage>` convention (e.g. `export.zip` nesting under `export.save`). The dot-grouping keeps related stages adjacent in DevTools.

```dart
// Example: batch-export-all (05-21) preserved `export.save` parity AND
// added `export.zip` for the new compose stage.
Future<SaveResult> persistMany(...) async {
  Timeline.startSync('export.save');
  try {
    final entries = await _pullAll(next, total, ...);
    Timeline.startSync('export.zip');
    final zipBytes = _composeZip(entries, rootFolder);
    Timeline.finishSync();
    return await _downloader(zipBytes, ...);
  } finally {
    Timeline.finishSync();
  }
}
```

**Required check** during code review of a refactor PR: `grep -RIn "Timeline.startSync" lib/features/<feature>/` before and after the refactor — every marker present in the "before" snapshot must still appear in the "after", on the new code path.

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
