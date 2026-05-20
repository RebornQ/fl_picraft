import 'dart:typed_data';

/// UI-facing snapshot of the export-screen preview pipeline.
///
/// Sealed so the preview widget can exhaustively switch on the variant
/// in a single layer — there's no `AsyncValue` wrapper around the state
/// because `AsyncValue.loading` / `AsyncValue.error` would duplicate the
/// loading and error variants below, forcing UI to handle a 4×4 product
/// of cases (see PRD §D1 for the trade-off).
///
/// Lives in `presentation/providers/` because it's part of the
/// preview controller's published contract; the renderer itself
/// (`data/preview_renderer.dart`) does not depend on this type.
sealed class PreviewState {
  const PreviewState();
}

/// Initial / cleared state — no editor source is available so the
/// preview surface has nothing to show. UI typically renders the
/// "请先在编辑器中导入图片" copy here.
class PreviewEmpty extends PreviewState {
  const PreviewEmpty();
}

/// A render is in flight.
///
/// [staleBytes] carries the previously-rendered frame when the
/// controller transitions from [PreviewReady] (or [PreviewError]) into
/// loading — UI can fade through the stale frame instead of flashing
/// back to the widget canvas skeleton. `null` on the very first load
/// (no previous frame exists yet).
class PreviewLoading extends PreviewState {
  const PreviewLoading({this.staleBytes});

  /// The previously-rendered bytes (one per cell for grid, single
  /// element for stitch). `null` on first entry.
  final List<Uint8List>? staleBytes;
}

/// Render succeeded — [bytes] holds one [Uint8List] per output file
/// (single element for stitch, one per cell for grid).
///
/// [totalSizeBytes] is the sum of `bytes[i].length` across cells so the
/// UI's "约 X.X MB" estimate label can read it directly without
/// re-summing on every rebuild.
class PreviewReady extends PreviewState {
  const PreviewReady({required this.bytes, required this.totalSizeBytes});

  final List<Uint8List> bytes;
  final int totalSizeBytes;
}

/// Render failed — UI shows an error placeholder + "重试" button that
/// calls `previewControllerProvider.notifier.refresh()`.
///
/// [staleBytes] is preserved so the UI's retry placeholder can keep
/// the last good frame visible behind the error overlay. `null` when
/// the failure happened on the first load.
class PreviewError extends PreviewState {
  const PreviewError({required this.message, this.staleBytes});

  /// Developer-facing English message; the UI wraps it in a zh-CN
  /// frame like `"预览暂不可用：<message>"`.
  final String message;

  /// Previously-rendered bytes, when available — same contract as
  /// [PreviewLoading.staleBytes].
  final List<Uint8List>? staleBytes;
}
