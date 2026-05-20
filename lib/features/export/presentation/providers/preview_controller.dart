import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../grid/presentation/providers/grid_editor_provider.dart';
import '../../../long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'export_controller.dart';
import 'export_dispatch.dart';
import 'preview_state.dart';
import 'process_bytes_fn.dart';
import 'processed_bytes_cache.dart';
import 'watermark_config_provider.dart';

/// Window after a config change before the preview re-renders.
///
/// Matches PRD §1.6 — keeps slider-drag from triggering 30+ isolate
/// hops per second.
const Duration kPreviewDebounce = Duration(milliseconds: 300);

/// Controller for the export-page preview.
///
/// Owns:
/// * Debounce timer (300 ms) so slider drags don't churn the isolate
/// * `_cachedSource` + `_cachedEditorStateHash` — source bytes are
///   re-rendered from the editor only when the editor's state hash
///   changes, so re-evaluations triggered by watermark / format /
///   quality changes reuse the same source.
/// * `_inFlightToken` — single-flight guard. Each scheduled render
///   bumps the token so a stale completion can't overwrite a newer
///   state.
///
/// Exposes [PreviewState] (sealed) — not `AsyncValue<PreviewState>` —
/// per PRD §D1: the sealed variants already cover loading / ready /
/// error / empty exhaustively, so wrapping in `AsyncValue` would force
/// consumers to handle a 4×4 product of UI cases.
///
/// **AutoDispose ownership**: the controller is autoDispose so that
/// once the consumer ([PreviewCard]) is unmounted (user pops
/// `/export` back to `/stitch` or `/grid`), the 6 `ref.listen`
/// callbacks, the debounce timer, `_cachedSource`, and the
/// `_lastRenderedKey` bookkeeping are all released. Without
/// autoDispose, slider changes in the editors would keep firing the
/// controller's listeners (silently re-running the expensive
/// `stitch/gridEditorControllerProvider.render()` + isolate hop in
/// the background) for an offscreen page. `processedBytesCacheProvider`
/// is intentionally NOT autoDispose so a re-visit can still hit the
/// cache and return [PreviewReady] immediately — see the provider
/// dartdoc on [previewControllerProvider] for the full rationale.
class PreviewController extends AutoDisposeNotifier<PreviewState> {
  Timer? _debounce;
  int _inFlightToken = 0;

  // ---- source-bytes cache (`editor.state.hashCode` → bytes) -------------

  /// Bytes pulled from the active editor's renderer. Keyed by the
  /// editor state's `hashCode` so re-evaluations for non-editor
  /// changes (watermark / format / quality) reuse the same source
  /// instead of re-running the (expensive) stitch / grid render.
  List<Uint8List>? _cachedSource;
  int? _cachedEditorStateHash;
  ExportSourceKind? _cachedSourceKind;

  /// Cache key of the last successfully rendered output. Lets the
  /// "save-paused → unpaused" flow decide whether to re-render or
  /// stay put.
  int? _lastRenderedKey;

  @override
  PreviewState build() {
    // Listen to every input the render depends on. Each subsequent
    // change schedules a debounced render via [_scheduleRender].
    ref.listen(currentExportSourceKindProvider, (_, _) => _scheduleRender());
    ref.listen(watermarkConfigProvider, (_, _) => _scheduleRender());
    ref.listen(
      exportControllerProvider.select((s) => (s.format, s.quality)),
      (_, _) => _scheduleRender(),
    );
    ref.listen(
      exportControllerProvider.select((s) => s.isSaving),
      _onIsSavingChanged,
    );
    ref.listen(stitchEditorControllerProvider, (_, _) => _scheduleRender());
    ref.listen(gridEditorControllerProvider, (_, _) => _scheduleRender());

    ref.onDispose(() {
      _debounce?.cancel();
      _debounce = null;
    });

    // Synchronously decide the initial state from the editor + cache.
    //
    // Why: the controller is autoDispose so it's re-created on every
    // `/export` re-mount. On re-mount, the consumer's first read of
    // `previewControllerProvider` must NOT show the wrong state for
    // a frame before the debounce-driven render kicks in. Two failure
    // modes a naive `return const PreviewEmpty()` would cause:
    //   1. Even with autoDispose, the [processedBytesCacheProvider]
    //      survives across visits (it's intentionally NOT autoDispose
    //      so re-visits hit the cache). Returning Empty here would
    //      flash Empty for 300 ms before the real Ready arrived even
    //      when the cache held a perfect match.
    //   2. When the cache holds NO entry but the editor has content,
    //      Empty would flash for 300 ms before transitioning to
    //      Loading — also a regression.
    //
    // Fix: inspect the [processedBytesCacheProvider] synchronously.
    //   - cache hit  → return [PreviewReady] directly, skip the
    //     isolate hop entirely
    //   - cache miss with source → enter [PreviewLoading] immediately
    //     so the UI shows a skeleton, then queue the real render
    //     via the debounce timer to do the real work
    //   - no editor source → [PreviewEmpty]
    //
    // Counterpart fix in [_scheduleRender] handles the re-mount /
    // dep-change path where `state` already exists but the inputs
    // have moved on.
    final initial = _initialStateFromCache();
    if (initial is PreviewLoading) {
      // Has source but cache miss — queue the real render directly.
      // We avoid [_scheduleRender] here because it reads `state` to
      // decide whether to pre-transition to Loading, but `state` is
      // not yet initialized during [build]; the initial value will be
      // [PreviewLoading] (from our return below) anyway, so no
      // pre-transition is needed. Honor the pause-gate so a save in
      // flight doesn't get preempted on first mount.
      if (!ref.read(exportControllerProvider).isSaving) {
        _debounce?.cancel();
        _debounce = Timer(kPreviewDebounce, _runRender);
      }
    }
    return initial;
  }

  /// Synchronously inspect the editor + processed-bytes cache to decide
  /// the FIRST state the consumer should see. Counterpart to
  /// [_scheduleRender]'s async path — see [build]'s comment for why
  /// this is necessary.
  PreviewState _initialStateFromCache() {
    final key = _currentInputKey();
    if (key == null) return const PreviewEmpty();
    final cached = ref.read(processedBytesCacheProvider.notifier).read(key);
    if (cached != null) {
      _lastRenderedKey = key;
      return PreviewReady(bytes: cached, totalSizeBytes: _sumLengths(cached));
    }
    // Has source but cache miss → enter Loading immediately so the UI
    // shows a skeleton without first flashing whatever state lived on
    // from a prior session (or [PreviewEmpty] on first mount).
    return const PreviewLoading();
  }

  // ---- public API -------------------------------------------------------

  /// Force a re-render, bypassing both the editor-state cache (re-pull
  /// source) and the result cache (re-run watermark + encode). Skips
  /// the 300 ms debounce — fires immediately.
  ///
  /// Per PRD §5 (refresh semantics) ignored when:
  /// * State is [PreviewLoading] — avoids stacking isolate tasks.
  /// * State is [PreviewEmpty] — there's no source to refresh.
  ///
  /// Intended for the "重试" button surfaced by [PreviewError].
  void refresh() {
    final s = state;
    if (s is PreviewLoading || s is PreviewEmpty) return;
    // Invalidate both caches before firing.
    _cachedSource = null;
    _cachedEditorStateHash = null;
    _cachedSourceKind = null;
    ref.read(processedBytesCacheProvider.notifier).invalidate();
    _lastRenderedKey = null;
    _debounce?.cancel();
    _runRender();
  }

  // ---- internal -------------------------------------------------------

  void _onIsSavingChanged(bool? prev, bool next) {
    if (!next && prev == true) {
      // Save just finished. If the current input no longer matches
      // the last rendered key, fire a render so the preview catches
      // up with anything the user changed during the pause window.
      final key = _currentInputKey();
      if (key != null && key != _lastRenderedKey) {
        _scheduleRender();
      }
    }
  }

  void _scheduleRender() {
    // Pause gate: skip while a save is in flight to keep CPU available
    // for the save's isolate hop.
    if (ref.read(exportControllerProvider).isSaving) return;

    // Synchronously pre-transition to Loading the moment the inputs
    // differ from the last rendered key, instead of waiting for the
    // 300 ms debounce window. This kills the "stale Ready frame
    // flashes before Loading" UX bug on page re-mount: the consumer
    // sees Loading immediately on the next rebuild rather than the
    // leftover [PreviewReady] from before the dep change.
    //
    // Idempotent: if the state is already [PreviewLoading] we skip
    // the re-assignment so consumers don't see redundant rebuilds
    // (the AnimatedSwitcher keys by sealed-variant identity, so the
    // visual would be the same anyway, but skipping keeps Riverpod
    // listeners tidy).
    final key = _currentInputKey();
    if (key == null) {
      // Editor lost its source (e.g. user cleared the image list while
      // a render was pending). Cancel any pending render and surface
      // Empty immediately.
      _debounce?.cancel();
      if (state is! PreviewEmpty) state = const PreviewEmpty();
      return;
    }
    if (key != _lastRenderedKey && state is! PreviewLoading) {
      state = PreviewLoading(staleBytes: _staleBytesFromState(state));
    }

    _debounce?.cancel();
    _debounce = Timer(kPreviewDebounce, _runRender);
  }

  /// Compute the cache key for the current set of inputs. Returns
  /// `null` when the editor has nothing to render — caller should
  /// transition to [PreviewEmpty].
  int? _currentInputKey() {
    final kind = ref.read(currentExportSourceKindProvider);
    final editorHash = _activeEditorStateHash(kind);
    if (editorHash == null) return null;
    final watermark = ref.read(watermarkConfigProvider);
    final exportState = ref.read(exportControllerProvider);
    return computeProcessedBytesCacheKey(
      kind: kind,
      editorStateHash: editorHash,
      watermark: watermark,
      format: exportState.format,
      quality: exportState.quality,
    );
  }

  int? _activeEditorStateHash(ExportSourceKind kind) {
    switch (kind) {
      case ExportSourceKind.stitch:
        final editor = ref.read(stitchEditorControllerProvider);
        if (!editor.hasImages) return null;
        return editor.hashCode;
      case ExportSourceKind.grid:
        final editor = ref.read(gridEditorControllerProvider);
        if (!editor.hasSource) return null;
        return editor.hashCode;
    }
  }

  Future<void> _runRender() async {
    final token = ++_inFlightToken;
    final kind = ref.read(currentExportSourceKindProvider);
    final editorHash = _activeEditorStateHash(kind);
    if (editorHash == null) {
      state = const PreviewEmpty();
      return;
    }
    final watermark = ref.read(watermarkConfigProvider);
    final exportState = ref.read(exportControllerProvider);
    final format = exportState.format;
    final quality = exportState.quality;
    final cacheKey = computeProcessedBytesCacheKey(
      kind: kind,
      editorStateHash: editorHash,
      watermark: watermark,
      format: format,
      quality: quality,
    );

    // Result cache hit — emit Ready synchronously, skip the isolate
    // hop entirely.
    final cached = ref
        .read(processedBytesCacheProvider.notifier)
        .read(cacheKey);
    if (cached != null) {
      _lastRenderedKey = cacheKey;
      state = PreviewReady(bytes: cached, totalSizeBytes: _sumLengths(cached));
      return;
    }

    // Enter loading, preserving stale bytes for crossfade.
    state = PreviewLoading(staleBytes: _staleBytesFromState(state));

    final List<Uint8List> sourceBytes;
    try {
      sourceBytes = await _resolveSourceBytes(kind, editorHash);
    } catch (e) {
      if (token != _inFlightToken) return;
      state = PreviewError(
        message: e.toString(),
        staleBytes: _staleBytesFromState(state),
      );
      return;
    }
    if (token != _inFlightToken) return;

    final processFn = ref.read(processBytesFnProvider);
    final processed = <Uint8List>[];
    try {
      for (final src in sourceBytes) {
        // Per PRD §7: the preview path tags its renderer hop with
        // `export.preview` so DevTools can attribute time spent to the
        // preview vs. save (`export.process`) call site.
        // [processExportBytes] itself intentionally does NOT add a
        // marker — the wrapping is owned by each caller.
        Timeline.startSync('export.preview');
        final Uint8List out;
        try {
          out = await processFn(
            source: src,
            watermark: watermark,
            format: format,
            quality: quality,
          );
        } finally {
          Timeline.finishSync();
        }
        if (token != _inFlightToken) return;
        processed.add(out);
      }
    } catch (e) {
      if (token != _inFlightToken) return;
      state = PreviewError(
        message: e.toString(),
        staleBytes: _staleBytesFromState(state),
      );
      return;
    }

    if (token != _inFlightToken) return;
    ref.read(processedBytesCacheProvider.notifier).write(cacheKey, processed);
    _lastRenderedKey = cacheKey;
    state = PreviewReady(
      bytes: processed,
      totalSizeBytes: _sumLengths(processed),
    );
  }

  /// Pull source bytes from the active editor, reusing `_cachedSource`
  /// when the editor's state hash hasn't changed.
  Future<List<Uint8List>> _resolveSourceBytes(
    ExportSourceKind kind,
    int editorHash,
  ) async {
    if (_cachedSource != null &&
        _cachedEditorStateHash == editorHash &&
        _cachedSourceKind == kind) {
      return _cachedSource!;
    }
    final List<Uint8List> bytes;
    switch (kind) {
      case ExportSourceKind.stitch:
        final composite = await ref
            .read(stitchEditorControllerProvider.notifier)
            .render();
        bytes = [composite];
      case ExportSourceKind.grid:
        bytes = await ref
            .read(gridEditorControllerProvider.notifier)
            .renderCells();
    }
    _cachedSource = bytes;
    _cachedEditorStateHash = editorHash;
    _cachedSourceKind = kind;
    return bytes;
  }

  static List<Uint8List>? _staleBytesFromState(PreviewState s) {
    return switch (s) {
      PreviewReady(:final bytes) => bytes,
      PreviewLoading(:final staleBytes) => staleBytes,
      PreviewError(:final staleBytes) => staleBytes,
      PreviewEmpty() => null,
    };
  }

  static int _sumLengths(List<Uint8List> bytes) {
    var sum = 0;
    for (final b in bytes) {
      sum += b.length;
    }
    return sum;
  }

  // ---- debug-only handles for tests -----------------------------------

  @visibleForTesting
  int? get debugLastRenderedKey => _lastRenderedKey;

  @visibleForTesting
  bool get debugHasPendingDebounce => _debounce?.isActive ?? false;
}

/// Public provider.
///
/// Type: `AutoDisposeNotifierProvider<PreviewController, PreviewState>`
/// — NOT `AsyncNotifierProvider`. See PRD §D1 / `preview_state.dart`
/// for the reasoning on the sealed-state-instead-of-AsyncValue choice.
///
/// **Why autoDispose**: the controller registers 6 `ref.listen`
/// callbacks against the watermark / format / quality / saving-flag
/// and the two editor controllers. Without autoDispose, once the user
/// pops `/export` back to `/stitch` or `/grid`, the controller (and
/// those listeners) stays alive — any slider drag in the editors
/// re-fires the debounced render in the background, running the
/// expensive `stitch/gridEditorControllerProvider.notifier.render()`
/// + `compute()` isolate hop for an invisible page and growing
/// `processedBytesCacheProvider` resident memory by up to ~25-100 MB
/// per session. autoDispose releases the controller (its timer,
/// listeners, `_cachedSource`, and `_lastRenderedKey`) the moment the
/// last consumer is unmounted.
///
/// **Why [processedBytesCacheProvider] is intentionally NOT
/// autoDispose**: dropping the cache on every `/export` un-mount
/// would defeat the "mount 不闪 stale" contract from PRD §D6 — a
/// user who pops back into `/export` with the same inputs should
/// immediately see a [PreviewReady] frame from the cache instead of
/// flashing [PreviewLoading] for 300 ms while the cache re-warms.
/// [_initialStateFromCache] reads the cache synchronously on every
/// new controller `build()`, so the cross-visit cache hit is what
/// makes re-mount feel instant.
final previewControllerProvider =
    AutoDisposeNotifierProvider<PreviewController, PreviewState>(
      PreviewController.new,
    );

/// Hint to consumers (Subtask B's UI) that need a flat list of
/// preview bytes. Returns an empty list outside [PreviewReady] so
/// callers can do a single `ref.watch` without an extra `switch`.
///
/// Kept here so the controller stays focused on state transitions —
/// derived projections live as separate providers. autoDispose to
/// match [previewControllerProvider] (a non-autoDispose derived
/// projection would silently keep the controller alive via Riverpod's
/// dependency tracking and defeat the leak fix).
final previewBytesProvider = Provider.autoDispose<List<Uint8List>>((ref) {
  final s = ref.watch(previewControllerProvider);
  return switch (s) {
    PreviewReady(:final bytes) => bytes,
    PreviewLoading() || PreviewError() || PreviewEmpty() => const [],
  };
});
