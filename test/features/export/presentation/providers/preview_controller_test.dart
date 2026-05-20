import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/export/presentation/providers/process_bytes_fn.dart';
import 'package:fl_picraft/features/export/presentation/providers/processed_bytes_cache.dart';
import 'package:fl_picraft/features/export/presentation/providers/watermark_config_provider.dart';
import 'package:fl_picraft/features/grid/data/renderers/grid_image_renderer.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_render_request.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/data/renderers/stitch_image_renderer.dart';
import 'package:fl_picraft/features/long_stitch/domain/usecases/stitch_render_request.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Provider-level unit tests for [PreviewController].
///
/// Drives the controller through a synchronous [ProcessBytesFn] override
/// — the production binding uses `compute()` which runs in a real
/// isolate and ignores `FakeAsync` ticks. Per PRD §D6 / §8.3 we test
/// debounce / cache / pause / refresh semantics by counting calls into
/// the fake instead of timing real renderer hops.
///
/// Plain `test` + manual `ProviderContainer` per
/// `quality-guidelines.md` → "Pattern: Plain `test` over `testWidgets`
/// for `AsyncNotifier`-only assertions" — there's no widget tree to
/// pump and the FakeAsync ↔ AsyncNotifier scheduler interaction would
/// produce flaky pending-timer teardown errors otherwise.

class _CountingProcessBytesFn {
  int callCount = 0;
  Object? errorToThrow;

  /// When set, the next call awaits this completer's future before
  /// returning. Used to pause the render mid-flight so tests can
  /// observe the controller's [PreviewLoading] state.
  Completer<void>? blockUntil;

  Future<Uint8List> call({
    required Uint8List source,
    required dynamic watermark,
    required ExportFormat format,
    required int quality,
  }) async {
    callCount++;
    final pause = blockUntil;
    if (pause != null) {
      blockUntil = null;
      await pause.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return Uint8List.fromList([source.length & 0xFF, callCount & 0xFF]);
  }
}

class _FakeStitchRenderer implements StitchImageRenderer {
  const _FakeStitchRenderer();
  @override
  Future<Uint8List> render(StitchRenderRequest request) async {
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

class _FakeGridRenderer implements GridImageRenderer {
  const _FakeGridRenderer();
  @override
  Future<List<Uint8List>> render(GridRenderRequest request) async {
    return [
      Uint8List.fromList(const [10]),
      Uint8List.fromList(const [20]),
    ];
  }
}

ImportedImage _fakeImage(String path) {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 4)),
  );
  return ImportedImage(
    sourcePath: path,
    bytes: bytes,
    width: 4,
    height: 4,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 20),
  );
}

ProviderContainer _makeContainer({
  required _CountingProcessBytesFn fake,
  List<ImportedImage> stitchImages = const [],
  List<ImportedImage> gridImages = const [],
}) {
  return ProviderContainer(
    overrides: [
      processBytesFnProvider.overrideWithValue(fake.call),
      stitchImageRendererProvider.overrideWithValue(
        const _FakeStitchRenderer(),
      ),
      gridImageRendererProvider.overrideWithValue(const _FakeGridRenderer()),
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWithValue(stitchImages),
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWithValue(gridImages),
    ],
  );
}

/// Pin the autoDispose [previewControllerProvider] alive for the
/// duration of the test by subscribing to it. Returns the subscription
/// so a test can later `.close()` it (e.g. to verify autoDispose
/// actually fires).
///
/// Why every existing test needs this: as of the 2026-05-21 leak fix
/// the provider is `AutoDisposeNotifierProvider`. `container.read(...)`
/// triggers `build()` but does NOT add a subscriber, so the controller
/// gets disposed on the next microtask flush (any `async.elapse(...)`).
/// A disposed controller has no `ref.listen` callbacks left, so the
/// debounce-based tests stop seeing the watermark / format changes
/// fire `_scheduleRender`. Subscribing once after [_makeContainer]
/// keeps the controller alive throughout the test body.
ProviderSubscription<PreviewState> _keepPreviewAlive(
  ProviderContainer container,
) {
  return container.listen<PreviewState>(previewControllerProvider, (_, _) {});
}

void main() {
  group('PreviewController — debounce', () {
    test('5 config changes within 300 ms trigger exactly one render', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);

        // Mount the controller. The initial schedule starts the
        // debounce timer. autoDispose requires an active subscription
        // for the controller to survive past the next microtask flush.
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        // Fire 5 watermark changes within the debounce window.
        for (var i = 0; i < 5; i++) {
          container
              .read(watermarkConfigProvider.notifier)
              .setOpacity(0.3 + (i * 0.05));
          async.elapse(const Duration(milliseconds: 40));
        }
        // Total elapsed: 200 ms — still inside the 300 ms window.
        expect(fake.callCount, 0, reason: 'no render should have run yet');

        // Wait out the rest of the window plus enough time for the
        // async chain to settle.
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();

        expect(
          fake.callCount,
          1,
          reason: '5 debounced changes should collapse to a single render',
        );
        expect(container.read(previewControllerProvider), isA<PreviewReady>());
      });
    });
  });

  group('PreviewController — result cache', () {
    test('second render with identical inputs hits cache (no fake call)', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        container.read(previewControllerProvider);
        // First render.
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(fake.callCount, 1);

        // Trigger a re-evaluation with identical inputs by flipping
        // watermark to a new value, then back. Net inputs unchanged →
        // cache hit on the second settle.
        final initialOpacity = container.read(watermarkConfigProvider).opacity;
        container
            .read(watermarkConfigProvider.notifier)
            .setOpacity(initialOpacity == 0.9 ? 0.8 : 0.9);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(fake.callCount, 2, reason: 'changed value triggers render');

        // Back to original.
        container
            .read(watermarkConfigProvider.notifier)
            .setOpacity(initialOpacity);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(
          fake.callCount,
          2,
          reason: 'identical-input re-evaluation must be a cache hit',
        );
      });
    });
  });

  group('PreviewController — pause-while-saving gate', () {
    test('config changes during isSaving=true do not trigger render', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        // Initial render.
        container.read(previewControllerProvider);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(fake.callCount, 1);

        // Simulate save in progress by flipping isSaving on the
        // export state directly through the notifier's internal copy.
        // We can't call `save()` because it would invoke the
        // repository — instead we use the notifier-state mechanism
        // exposed by Riverpod.
        final exportNotifier = container.read(
          exportControllerProvider.notifier,
        );
        exportNotifier.state = exportNotifier.state.copyWith(isSaving: true);
        async.flushMicrotasks();

        // Change config while saving.
        container.read(watermarkConfigProvider.notifier).setOpacity(0.25);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(
          fake.callCount,
          1,
          reason: 'pause gate must skip the render schedule',
        );

        // Unpause — controller should auto-fire because cache key
        // changed.
        exportNotifier.state = exportNotifier.state.copyWith(isSaving: false);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(
          fake.callCount,
          2,
          reason: 'auto re-render after unpause when inputs changed',
        );
      });
    });
  });

  group('PreviewController — error propagation', () {
    test('fake throw → state becomes PreviewError', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn()
          ..errorToThrow = StateError('boom');
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        container.read(previewControllerProvider);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        final s = container.read(previewControllerProvider);
        expect(s, isA<PreviewError>());
        expect((s as PreviewError).message, contains('boom'));
        expect(fake.callCount, 1);
      });
    });

    test('error after a successful render carries stale bytes', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        container.read(previewControllerProvider);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        final ready = container.read(previewControllerProvider) as PreviewReady;
        expect(ready.bytes.isNotEmpty, isTrue);

        // Now arm the fake to throw and trigger a new render.
        fake.errorToThrow = StateError('boom2');
        container.read(watermarkConfigProvider.notifier).setOpacity(0.4);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        final s = container.read(previewControllerProvider);
        expect(s, isA<PreviewError>());
        expect((s as PreviewError).staleBytes, isNotNull);
        expect(s.staleBytes!.first, equals(ready.bytes.first));
      });
    });
  });

  group('PreviewController — refresh() semantics', () {
    test('refresh() during PreviewLoading is ignored', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        // Pause the first fakeFn call so the controller stays in
        // PreviewLoading while we attempt the refresh().
        final pause = Completer<void>();
        fake.blockUntil = pause;
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        final notifier = container.read(previewControllerProvider.notifier);
        // Run the debounce timer to start the render. It's now
        // suspended at the fakeFn await.
        async.elapse(const Duration(milliseconds: 350));
        async.flushMicrotasks();
        expect(fake.callCount, 1);
        expect(
          container.read(previewControllerProvider),
          isA<PreviewLoading>(),
        );

        // refresh() during Loading should be a no-op.
        notifier.refresh();
        async.flushMicrotasks();
        expect(
          fake.callCount,
          1,
          reason: 'refresh() must not enqueue a second render during Loading',
        );

        // Let the first render finish so test teardown is clean.
        pause.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();
        expect(fake.callCount, 1);
      });
    });

    test('refresh() in PreviewReady bypasses cache and re-renders', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        final notifier = container.read(previewControllerProvider.notifier);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(fake.callCount, 1);
        expect(container.read(previewControllerProvider), isA<PreviewReady>());

        // refresh() should fire immediately (no debounce wait) and
        // bypass the cache.
        notifier.refresh();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();
        expect(
          fake.callCount,
          2,
          reason: 'refresh() must skip cache and re-invoke the fake',
        );
      });
    });

    test('refresh() in PreviewEmpty is ignored', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          // No images for either editor — state is PreviewEmpty.
        );
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        final notifier = container.read(previewControllerProvider.notifier);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(container.read(previewControllerProvider), isA<PreviewEmpty>());
        expect(fake.callCount, 0);

        notifier.refresh();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();
        expect(
          fake.callCount,
          0,
          reason: 'refresh() in Empty has nothing to render',
        );
      });
    });
  });

  group('PreviewController — empty / source switching', () {
    test('no images → PreviewEmpty, fake never called', () {
      fakeAsync((async) {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(fake: fake);
        addTearDown(container.dispose);
        final sub = _keepPreviewAlive(container);
        addTearDown(sub.close);

        container.read(previewControllerProvider);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(container.read(previewControllerProvider), isA<PreviewEmpty>());
        expect(fake.callCount, 0);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Bug-fix regression coverage — "stale Ready frame flashes before
  // Loading on /export re-mount". See
  // [PreviewController.build] / [PreviewController._scheduleRender]
  // comments for the root cause and approach.
  //
  // The new contract:
  //   * First build() returns the cache-aware initial state — never
  //     [PreviewEmpty] when the editor has content but the cache has
  //     no entry; never the leftover [PreviewReady] from a prior page
  //     visit when the inputs have moved on.
  //   * [_scheduleRender] synchronously pre-transitions to
  //     [PreviewLoading] the moment the input key differs from
  //     [_lastRenderedKey] — does NOT wait 300 ms.
  // ─────────────────────────────────────────────────────────────────────

  group('PreviewController — initial-state cache-awareness (bug fix)', () {
    test(
      'cache-hit on first build → first emitted state is PreviewReady (no Empty/Loading flash)',
      () {
        fakeAsync((async) {
          final fake = _CountingProcessBytesFn();
          final container = _makeContainer(
            fake: fake,
            stitchImages: [_fakeImage('a')],
          );
          addTearDown(container.dispose);

          // Pre-warm the cache by computing the exact key the
          // controller will derive on its first build(), then writing
          // bytes under that key. Reading the dep providers first
          // initializes them — the controller's build() reads the
          // same providers and resolves to the same hashes / values.
          final kind = container.read(currentExportSourceKindProvider);
          final editorHash = container
              .read(stitchEditorControllerProvider)
              .hashCode;
          final watermark = container.read(watermarkConfigProvider);
          final exportState = container.read(exportControllerProvider);
          final cacheKey = computeProcessedBytesCacheKey(
            kind: kind,
            editorStateHash: editorHash,
            watermark: watermark,
            format: exportState.format,
            quality: exportState.quality,
          );
          final precachedBytes = [
            Uint8List.fromList(const [99, 100, 101]),
          ];
          container
              .read(processedBytesCacheProvider.notifier)
              .write(cacheKey, precachedBytes);

          // Pin the autoDispose controller alive across the `async.elapse`
          // calls below — without an active subscriber autoDispose fires
          // on the next microtask and the controller is recreated before
          // each assertion, which would invalidate the contract under
          // test.
          final sub = _keepPreviewAlive(container);
          addTearDown(sub.close);

          // First read of the controller — build() should return
          // Ready synchronously, no Empty/Loading flash.
          final initialState = container.read(previewControllerProvider);
          expect(
            initialState,
            isA<PreviewReady>(),
            reason: 'build() must surface cache hit synchronously',
          );
          final ready = initialState as PreviewReady;
          expect(ready.bytes, equals(precachedBytes));
          expect(ready.totalSizeBytes, equals(3));

          // The fake processFn should never be invoked — cache hit
          // short-circuits the render pipeline entirely. Drain the
          // debounce window to be sure nothing got queued either.
          async.elapse(const Duration(milliseconds: 400));
          async.flushMicrotasks();
          expect(
            fake.callCount,
            0,
            reason: 'cache hit must skip the isolate hop',
          );
          expect(
            container.read(previewControllerProvider),
            isA<PreviewReady>(),
          );
        });
      },
    );

    test(
      'no source on first build → first emitted state is PreviewEmpty (sanity)',
      () {
        fakeAsync((async) {
          final fake = _CountingProcessBytesFn();
          final container = _makeContainer(fake: fake /* no images */);
          addTearDown(container.dispose);
          final sub = _keepPreviewAlive(container);
          addTearDown(sub.close);

          // First read — synchronous Empty, no Loading flash.
          final initial = container.read(previewControllerProvider);
          expect(initial, isA<PreviewEmpty>());

          // Drain to confirm nothing got queued either.
          async.elapse(const Duration(milliseconds: 400));
          async.flushMicrotasks();
          expect(
            container.read(previewControllerProvider),
            isA<PreviewEmpty>(),
          );
          expect(fake.callCount, 0);
        });
      },
    );

    test(
      'has source + cache miss on first build → first emitted state is PreviewLoading (NOT Empty)',
      () {
        fakeAsync((async) {
          final fake = _CountingProcessBytesFn();
          final container = _makeContainer(
            fake: fake,
            stitchImages: [_fakeImage('a')],
          );
          addTearDown(container.dispose);
          final sub = _keepPreviewAlive(container);
          addTearDown(sub.close);

          // First read — must be Loading immediately, not Empty.
          // Pre-fix behavior: Empty for 300 ms, then Loading.
          final initial = container.read(previewControllerProvider);
          expect(
            initial,
            isA<PreviewLoading>(),
            reason:
                'first frame must show a skeleton, not flash Empty for 300 ms',
          );
          expect(
            fake.callCount,
            0,
            reason: 'render is queued but not yet invoked (inside debounce)',
          );

          // The render still runs through the normal debounce window.
          async.elapse(const Duration(milliseconds: 400));
          async.flushMicrotasks();
          expect(
            container.read(previewControllerProvider),
            isA<PreviewReady>(),
          );
          expect(fake.callCount, 1);
        });
      },
    );
  });

  group(
    'PreviewController — synchronous pre-transition to Loading (bug fix)',
    () {
      test(
        'input key change after PreviewReady immediately transitions to PreviewLoading (no 300 ms wait)',
        () {
          fakeAsync((async) {
            final fake = _CountingProcessBytesFn();
            final container = _makeContainer(
              fake: fake,
              stitchImages: [_fakeImage('a')],
            );
            addTearDown(container.dispose);
            final sub = _keepPreviewAlive(container);
            addTearDown(sub.close);

            // Settle to Ready first.
            container.read(previewControllerProvider);
            async.elapse(const Duration(milliseconds: 400));
            async.flushMicrotasks();
            expect(
              container.read(previewControllerProvider),
              isA<PreviewReady>(),
            );
            expect(fake.callCount, 1);

            final notifier = container.read(previewControllerProvider.notifier);
            final keyBefore = notifier.debugLastRenderedKey;
            expect(keyBefore, isNotNull);

            // Mutate a dep — the listener will fire and `_scheduleRender`
            // should synchronously transition to Loading rather than
            // wait for the 300 ms debounce window. NO `async.elapse`
            // between the mutation and the assertion — only a
            // microtask flush so the Riverpod listener callback
            // dispatches.
            container.read(watermarkConfigProvider.notifier).setOpacity(0.4);
            async.flushMicrotasks();
            expect(
              container.read(previewControllerProvider),
              isA<PreviewLoading>(),
              reason:
                  'state must pre-transition to Loading synchronously, '
                  'before the 300 ms debounce timer fires',
            );
            // Sanity: the debounce timer is queued but the fake hasn't
            // run yet — the pre-transition does NOT call the fake.
            expect(fake.callCount, 1);

            // After the debounce + microtask flush, the render completes
            // normally — the debounce contract is preserved.
            async.elapse(const Duration(milliseconds: 350));
            async.flushMicrotasks();
            expect(
              container.read(previewControllerProvider),
              isA<PreviewReady>(),
            );
            expect(fake.callCount, 2);
          });
        },
      );
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Bug-fix regression coverage — leak audit Scenario A + F (silent
  // background isolate render after the user pops `/export`).
  //
  // Before the fix `previewControllerProvider` was a plain
  // [NotifierProvider]; the controller's `ref.listen` callbacks
  // (watermark / format / saving / stitch+grid editors), debounce
  // timer, `_cachedSource`, and `_lastRenderedKey` outlived the
  // [PreviewCard] widget. Adjusting a slider in the editor screen
  // after closing `/export` re-fired `_scheduleRender` → `_runRender`
  // → `compute()` isolate hop → wrote into
  // [processedBytesCacheProvider]. Result: 25-100 MB resident memory
  // and silent background CPU burn the user could not see.
  //
  // The fix flips the controller to [AutoDisposeNotifierProvider]
  // (and [previewBytesProvider] to `Provider.autoDispose` to match)
  // while leaving [processedBytesCacheProvider] non-autoDispose so the
  // re-mount cache-hit path from PRD §D6 still works.
  //
  // This regression test exercises a "first visit + drop subscriber +
  // second visit" cycle, asserting (a) the second-visit controller is
  // a fresh instance (proves autoDispose actually fired), and (b) the
  // cached bytes survive across the dispose so the second visit's
  // first emitted state is [PreviewReady] without invoking `processFn`.
  // ─────────────────────────────────────────────────────────────────────

  group('PreviewController — autoDispose leak fix', () {
    test(
      'controller is released on unmount and cache survives — re-mount returns '
      'PreviewReady from cache without invoking processFn',
      () async {
        final fake = _CountingProcessBytesFn();
        final container = _makeContainer(
          fake: fake,
          stitchImages: [_fakeImage('a')],
        );
        addTearDown(container.dispose);

        // Pre-warm the processed-bytes cache with the exact key the
        // controller's first build() will derive. Reading the dep
        // providers initializes them so the key derivation matches
        // what build() sees.
        final kind = container.read(currentExportSourceKindProvider);
        final editorHash = container
            .read(stitchEditorControllerProvider)
            .hashCode;
        final watermark = container.read(watermarkConfigProvider);
        final exportState = container.read(exportControllerProvider);
        final cacheKey = computeProcessedBytesCacheKey(
          kind: kind,
          editorStateHash: editorHash,
          watermark: watermark,
          format: exportState.format,
          quality: exportState.quality,
        );
        final precachedBytes = [
          Uint8List.fromList(const [42, 43, 44]),
        ];
        container
            .read(processedBytesCacheProvider.notifier)
            .write(cacheKey, precachedBytes);

        // ─── First "visit" — simulates the user opening /export. ────
        final sub1 = container.listen<PreviewState>(
          previewControllerProvider,
          (_, _) {},
        );
        final notifier1 = container.read(previewControllerProvider.notifier);
        final state1 = container.read(previewControllerProvider);
        expect(
          state1,
          isA<PreviewReady>(),
          reason: 'first visit: cache hit short-circuits to Ready',
        );
        expect(
          (state1 as PreviewReady).bytes,
          equals(precachedBytes),
          reason: 'first visit: bytes come from the pre-warmed cache',
        );
        expect(
          fake.callCount,
          0,
          reason: 'first visit: cache hit must skip the isolate hop',
        );

        // ─── User leaves /export — drop the only subscriber. ───────
        sub1.close();
        // Yield to the event loop so Riverpod's autoDispose microtask
        // runs and the controller actually tears down.
        await Future<void>.delayed(Duration.zero);

        // ─── Second "visit" — simulates the user returning to /export.
        final sub2 = container.listen<PreviewState>(
          previewControllerProvider,
          (_, _) {},
        );
        addTearDown(sub2.close);
        final notifier2 = container.read(previewControllerProvider.notifier);
        final state2 = container.read(previewControllerProvider);

        // (a) Controller identity changed → autoDispose actually fired
        //     between the two visits. If autoDispose had not been
        //     applied this would still be `notifier1` and the listener
        //     callbacks would keep running for an offscreen page.
        expect(
          identical(notifier1, notifier2),
          isFalse,
          reason:
              'controller must have been disposed and recreated — '
              'proves autoDispose released the listeners + timer + '
              '_cachedSource of the first instance',
        );

        // (b) The second-visit controller hits the surviving cache
        //     synchronously in `build()` → first emitted state is
        //     PreviewReady, no Empty/Loading flash, no isolate hop.
        expect(
          state2,
          isA<PreviewReady>(),
          reason:
              're-mount must hit the surviving processedBytesCacheProvider '
              'and emit Ready synchronously (PRD §D6 contract)',
        );
        expect(
          (state2 as PreviewReady).bytes,
          equals(precachedBytes),
          reason: 're-mounted controller serves the same cached bytes',
        );
        expect(
          fake.callCount,
          0,
          reason:
              'processedBytesCacheProvider is intentionally NOT autoDispose; '
              'cache survives the controller dispose and the re-mounted '
              'controller never invokes processFn',
        );
      },
    );
  });
}
