# Error Handling

> How raw exceptions become user-facing messages.

---

## Overview

Two audiences for errors, two different requirements:

| Audience | Where | Requirement |
|---|---|---|
| **User** | snackbar / dialog | zh-CN sentence, no stack trace, no English exception class name |
| **Developer** | `debugPrint` / logger / `StateError` | full exception detail, English fine, retainable in dev tools |

The project enforces these via a single central translation table in `lib/core/errors/user_facing_messages.dart`. **Every snackbar / dialog string a user sees must go through a helper in this file.**

---

## Convention: User-facing strings live in `core/errors/`

**What**: Any `ScaffoldMessenger.showSnackBar(...)` / `showDialog(...)` / `SaveFailure(message: ...)` message that ends up in front of the user must be built via a helper in `lib/core/errors/user_facing_messages.dart`. No raw `'Export failed: $e'` interpolation at the callsite.

**Why**:

1. **Single translation point**. If the product rewrites all error copy ("导出失败：xxx" → "导出未完成，原因：xxx"), it's one file edit, not 14.
2. **No English leaks**. Raw `e.toString()` returns `"Exception: <message>"` or `"FormatException: bad header"` — both are English and have a `<ClassName>:` prefix the user doesn't understand. The helper strips the prefix and prepends the zh-CN frame.
3. **No stack trace bleed**. Truncation lives in the helper, not at callsites where someone will forget.

**How to apply**:

```dart
// ✅ Correct — single helper per failure shape
try {
  await _saveToDisk(bytes);
  return const SaveSuccess(count: 1);
} catch (e) {
  return SaveFailure(message: saveFailureMessage(e));
}

// ❌ Wrong — raw interpolation
catch (e) {
  return SaveFailure(message: 'Save failed: $e');
}

// ❌ Wrong — raw English exception class leaked
catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString())),
  );
}
```

The current helpers (extend as needed):

| Helper | When to use |
|---|---|
| `describeCause(error)` | Building block — strips `Exception: ` prefix, truncates to 120 chars, returns `'未知错误'` for null. Other helpers compose on top |
| `exportFailureMessage(cause)` | Compose / encode failed |
| `saveFailureMessage(cause)` | Generic disk / gallery / web download failure |
| `partialSaveFailureMessage(saved, total, cause)` | Grid loop where some cells already on disk |
| `importFailureMessage(cause)` | Image picker / camera / clipboard / drag-drop failure |
| `gallerySaveFailureMessage(GalException e)` | Plugin-specific: gal's `GalExceptionType.{accessDenied, notEnoughSpace, notSupportedFormat, unexpected}` enum |

---

## Convention: Developer-facing logs stay in English

**What**: `debugPrint`, `logger.severe`, `StateError(...)` messages, and any `UnsupportedError`/`assert` failures keep their original English wording. **Do not** wrap them in translation helpers.

**Why**: Developers reading these messages want grep-able, stable strings to match against. The user never sees them (they're stripped in release for `dart:developer` calls, and `StateError` only surfaces when an invariant is genuinely broken).

```dart
// ✅ Correct — dev-facing English
if (request.images.isEmpty) {
  throw StateError('GridImageRenderer called with empty grid');
}

// ❌ Wrong — translating internal invariants pollutes the user-facing table
if (request.images.isEmpty) {
  throw StateError(exportFailureMessage('empty grid'));
}
```

---

## Pattern: Plugin-specific translation tables

**Problem**: A plugin (`gal`, `image_picker`, `permission_handler`) throws an exception whose `.toString()` is an English enum name like `"GalException: accessDenied"`. Piping it through `saveFailureMessage(e)` gives the user `"保存失败：accessDenied"` — the enum word leaks.

**Solution**: Add a plugin-specific helper that switches on the plugin's typed error and returns a fully-localized sentence:

```dart
String gallerySaveFailureMessage(GalException e) {
  return switch (e.type) {
    GalExceptionType.accessDenied =>
      '保存失败：需要相册权限，请在设置中开启',
    GalExceptionType.notEnoughSpace =>
      '保存失败：存储空间不足',
    GalExceptionType.notSupportedFormat =>
      '保存失败：不支持的图片格式',
    GalExceptionType.unexpected =>
      '保存失败：${describeCause(e)}',
  };
}
```

The datasource catches the typed exception **before** the generic catch:

```dart
try {
  await Gal.putImage(path);
} on GalException catch (e) {
  return SaveFailure(message: gallerySaveFailureMessage(e));
} catch (e) {
  return SaveFailure(message: saveFailureMessage(e));
}
```

This is a deliberate **layer trade-off** — `core/` imports the plugin package (`package:gal/gal.dart`) so the translation table can match against the typed enum. See `guides/cross-layer-thinking-guide.md` → "When to break plugin layering for error translation" for the reasoning.

---

## Pattern: Sealed failure types should override `toString()`

When a sealed failure hierarchy (`sealed class ImageImportFailure { ... }`) carries zh-CN message logic, each variant should override `toString()` to return the user-facing sentence:

```dart
sealed class ImageImportFailure {
  const ImageImportFailure();
}

final class ImportCancelledByUser extends ImageImportFailure {
  const ImportCancelledByUser();
  @override
  String toString() => '已取消导入';
}

final class ImportUnsupportedFormat extends ImageImportFailure {
  const ImportUnsupportedFormat({required this.path});
  final String path;
  @override
  String toString() => '不支持的图片格式：$path';
}
// ... 4 more variants
```

This lets consumers do `importFailureMessage(failure)` or `failure.toString()` interchangeably — both yield the same zh-CN string. Tests assert on `toString()`; widgets call `importFailureMessage`.

---

## Pattern: `ref.listen` for `AsyncError` → snackbar

`AsyncValue` consumers typically use `valueOrNull` and silently drop errors. To surface errors as user-facing snackbars, attach a `ref.listen` in the **screen** that owns the import / save flow:

```dart
class _StitchEditorState extends ConsumerState<StitchEditorScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<ImportedImage>>>(
      imageImportControllerProvider,
      (previous, next) {
        if (next.hasError && !next.isLoading) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(importFailureMessage(next.error))),
          );
        }
      },
    );
    return /* ... */;
  }
}
```

**Where to attach**: One listen per consumer screen. Don't attach in every widget that calls `ref.watch` — duplicate snackbars. Don't attach in a provider's `build()` — `ref.listen` is widget-scoped.

---

## Common Mistakes

### Don't: catch and rethrow with English

```dart
// ❌ Wrong — the raw English `Exception` text propagates to a parent's
// generic catch and ends up in a snackbar
catch (e) {
  throw Exception('Failed to compose: $e');
}
```

Either don't catch (let the original exception propagate), or catch and convert to a typed failure (`SaveFailure(message: exportFailureMessage(e))`).

### Don't: re-wrap an already-translated `SaveFailure`

```dart
// ❌ Wrong — `WebBlobDownloadDataSource.save()` already returns a
// SaveFailure with a zh-CN frame (e.g. "保存失败：浏览器拒绝下载").
// Throwing its message back out, then catching at the outer layer and
// piping through `saveFailureMessage(e)` again, double-frames the
// snackbar copy as "保存失败：保存失败：浏览器拒绝下载".
Future<void> _wrap(...) async {
  final result = await ds.save(...);
  if (result is SaveFailure) throw Exception(result.message);  // ❌ unwraps
}

try {
  await _wrap(...);
} catch (e) {
  return SaveFailure(message: saveFailureMessage(e));  // ❌ re-wraps
}
```

**Why it's bad**: `core/errors/user_facing_messages.dart` helpers (`saveFailureMessage`, `exportFailureMessage`, `partialSaveFailureMessage`) prepend a zh-CN frame ("保存失败：…", "导出失败：…"). Threading an already-framed message through a second helper produces visible double prefixes on the user's snackbar.

**Instead**: keep `SaveResult` flowing as a typed value end-to-end. Wrappers that compose with downstream `SaveFailure` returns must forward them verbatim — only the outermost `try/catch` over **raw exceptions** (synchronous throws, plugin errors) calls a translation helper.

```dart
// ✅ Correct — typed result flows through; raw throws translate once.
typedef WebBlobDownloader = Future<SaveResult> Function(
  Uint8List bytes, {required String fileName, required String mimeType});

Future<SaveResult> persistMany(...) async {
  try {
    final bytes = composeZip(...);
    final result = await _downloader(bytes, fileName: name, mimeType: mime);
    return switch (result) {
      SaveSuccess() => SaveSuccess(location: 'Downloads', count: total),  // enrich
      SaveCancelled() => result,                                          // forward
      SaveFailure() => result,                                            // forward — no re-wrap
    };
  } catch (e) {
    // Only raw exceptions (composer OOM, JS interop throws) end up here.
    return SaveFailure(message: saveFailureMessage(e));
  }
}
```

**Rule**: if a callee's return type is `SaveResult` (or any sealed failure type), the caller MUST pattern-match and forward `SaveFailure` / `SaveCancelled` directly. Translation helpers are only for catching `Object` / `Exception` (raw throws).

**Required test**: per-adapter, inject a downloader / datasource stub that returns `SaveFailure(message: '保存失败：...')` and assert the surfaced `SaveFailure.message` contains exactly **one** "保存失败：" prefix.

### Don't: log AND show

```dart
// ❌ Wrong — duplicate noise; user gets snackbar AND debug log of same content
catch (e) {
  debugPrint('Export failed: $e');
  return SaveFailure(message: exportFailureMessage(e));
}
```

If the failure is already translated and surfaced via snackbar (the user sees it), there's no value in also `debugPrint`-ing it. The exception object will be visible in a debugger or `flutter run` console anyway when not caught.

### Gotcha: `describeCause` truncates at 120 chars

The helper truncates long causes (deeply-nested stack frames) to 120 chars + `…`. If a callsite needs a longer message, **don't** bypass the helper — extend the helper's `kMaxCauseLength` constant. Don't grow the constant casually; 120 fits a phone snackbar in one line.

---

## Where this lives

- `lib/core/errors/user_facing_messages.dart` — all helpers
- `lib/features/<feature>/data/datasources/*.dart` — catch and translate; never leak raw exceptions past the datasource boundary
- `lib/features/<feature>/data/repositories/*.dart` — same, plus partial-save composition
- `lib/features/<feature>/presentation/screens/*.dart` — `ref.listen` → snackbar bridges

## Required Tests

- Per helper: assert a representative input produces the expected zh-CN frame (e.g. `expect(saveFailureMessage(FormatException('bad')), '保存失败：FormatException: bad')`)
- Per sealed failure variant: assert `toString()` returns zh-CN
- Per datasource: feed it a stub that throws a typed plugin exception, assert the resulting `SaveFailure.message` is fully zh-CN (no enum name leakage)
