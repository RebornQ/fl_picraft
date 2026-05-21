import 'package:flutter/foundation.dart';

import '../../domain/entities/export_format.dart';
import '../../domain/entities/save_result.dart';
import 'desktop_directory_persist_adapter.dart';
import 'mobile_gallery_persist_adapter.dart';
import 'web_zip_persist_adapter.dart';

/// Pull-based batch persistence contract.
///
/// Adapter MUST call [next] to obtain the i-th processed bytes
/// (0-based). Returning `null` signals end-of-input. The contract is
/// pull-based so the adapter decides memory shape:
///
///   * desktop / mobile: pull → write → discard, peak ~ 1 image
///   * web: pull all → zip in memory → blob download, peak ~ Σ bytes
///
/// Each platform's adapter handles its own per-cell partial-save
/// accounting so the repository can dispatch any grid / multi-image
/// batch through a single interface with zero platform branching.
///
/// The contract for [persistMany]:
///
///   * The adapter calls [next] sequentially with `index = 0, 1, …,
///     total - 1` (or earlier if a platform-side dialog / pre-flight
///     step is cancelled).
///   * [next] returning `null` is treated as end-of-input — the adapter
///     stops pulling. (In practice the repository's `next` callback
///     short-circuits to `null` when `index >= cells.length`, but the
///     adapter MUST NOT assume that all `index < total` produce
///     non-null bytes.)
///   * [next] may throw — the adapter MUST catch and roll into
///     partial-save accounting via [partialSaveFailureMessage].
///   * The adapter MUST NOT call [next] more than once for the same
///     index, and MUST NOT prefetch ahead of its actual persist step
///     (so a desktop adapter that cancels in the dialog never pulls).
///
/// See the platform impl files for per-target detail.
abstract class BatchPersistAdapter {
  const BatchPersistAdapter();

  /// Persist [total] processed images to the platform-native
  /// destination.
  ///
  /// * [total] — the number of cells the caller plans to provide;
  ///   serves as the upper bound when the adapter loops `next(i)`.
  /// * [next] — pull-based callback that produces the i-th image's
  ///   bytes. Returning `null` ends the batch early; throwing is
  ///   translated into a partial-save failure.
  /// * [format] — controls suggested filename extensions per
  ///   [suggestedName].
  /// * [at] — timestamp used for filenames; defaults to
  ///   `DateTime.now()` if not provided by the caller (repository
  ///   passes the value it stamped at the start of the batch so all
  ///   files share the same timestamp).
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  });
}

/// Pick the right [BatchPersistAdapter] for the running platform.
///
/// Dispatch table:
///
///   * `kIsWeb` → [WebZipPersistAdapter] (single ZIP download)
///   * Mobile (iOS / Android) → [MobileGalleryPersistAdapter]
///     (wrap the existing `gal` loop, unchanged behavior)
///   * Desktop (macOS / Windows / Linux) →
///     [DesktopDirectoryPersistAdapter] (one folder pick + batch
///     write)
///
/// Unsupported platforms fall through to a stub that returns
/// [SaveFailure] — the repository's stitch path remains the canonical
/// "what platform are we on?" error owner for non-grid flows, so this
/// stub is rarely user-visible.
BatchPersistAdapter defaultBatchPersistAdapter() {
  if (kIsWeb) return const WebZipPersistAdapter();
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return const MobileGalleryPersistAdapter();
  }
  if (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    return const DesktopDirectoryPersistAdapter();
  }
  return const _UnsupportedBatchPersistAdapter();
}

class _UnsupportedBatchPersistAdapter extends BatchPersistAdapter {
  const _UnsupportedBatchPersistAdapter();

  @override
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  }) async {
    return SaveFailure(
      '当前平台暂不支持批量保存（${kIsWeb ? "web" : defaultTargetPlatform}）',
    );
  }
}
