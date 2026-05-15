/// User-facing zh-CN error message helpers.
///
/// Centralizes the "raw `Exception` → human-readable Chinese sentence"
/// mapping so feature code never has to embed `'Export failed: $e'`-
/// style strings (which leak English + stack trace details to the
/// user). Use [exportFailureMessage] / [saveFailureMessage] /
/// [importFailureMessage] when building [SaveFailure] payloads or
/// surfacing snackbars.
///
/// The [gallerySaveFailureMessage] helper additionally translates the
/// `gal` plugin's `GalExceptionType` enum (which carries English
/// `message` strings baked into the plugin) into zh-CN copy — keeps
/// the plugin-specific knowledge in one place so the gallery
/// datasource can stay focused on its happy path.
library;

import 'package:gal/gal.dart';

/// Default ellipsis appended to truncated cause strings so the toast
/// stays readable on a narrow phone.
const String _kMaxCauseLength = '…';

/// Coerce any error / object into a short, user-friendly cause string.
///
/// * Strips the leading `Exception:` prefix that Dart's default
///   `toString()` injects.
/// * Truncates to ~120 chars so a deeply-nested stack frame doesn't
///   blow out the snackbar height.
String describeCause(Object? error) {
  if (error == null) return '未知错误';
  var text = error.toString();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
  text = text.trim();
  if (text.isEmpty) return '未知错误';
  const max = 120;
  if (text.length <= max) return text;
  return '${text.substring(0, max)}$_kMaxCauseLength';
}

/// Snackbar copy for a failed export pipeline (compose + encode).
///
/// Example: "导出失败：FormatException: bad header"
String exportFailureMessage(Object? cause) => '导出失败：${describeCause(cause)}';

/// Snackbar copy for a failed persist step (writing to disk / gallery
/// / download).
///
/// Example: "保存失败：Photos permission denied"
String saveFailureMessage(Object? cause) => '保存失败：${describeCause(cause)}';

/// Snackbar copy for a mid-grid-loop failure where some cells were
/// already on disk before the error.
String partialSaveFailureMessage({
  required int saved,
  required int total,
  required Object? cause,
}) {
  return '已保存 $saved / $total 张后失败：${describeCause(cause)}';
}

/// Snackbar copy for a failed import flow.
String importFailureMessage(Object? cause) => '导入失败：${describeCause(cause)}';

/// Snackbar copy for a [GalException] surfaced from the `gal` plugin
/// during a Photos / gallery save attempt.
///
/// `GalException.type.message` is baked-in English copy from the
/// plugin (e.g. "Permission to access the gallery is denied."), so
/// feeding it through [saveFailureMessage] yields zh-CN/EN mixed
/// strings. This helper maps the enum to zh-CN sentences instead,
/// falling back to [describeCause] for the catch-all `unexpected`
/// variant where the underlying platform message is the best signal
/// we have.
String gallerySaveFailureMessage(GalException e) {
  return switch (e.type) {
    GalExceptionType.accessDenied => '保存失败：相册权限被拒绝，请在系统设置中开启后重试',
    GalExceptionType.notEnoughSpace => '保存失败：存储空间不足',
    GalExceptionType.notSupportedFormat => '保存失败：图片格式不被相册支持',
    GalExceptionType.unexpected => '保存失败：${describeCause(e)}',
  };
}
