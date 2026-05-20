import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/export/presentation/providers/process_bytes_fn.dart';
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
        // debounce timer.
        container.read(previewControllerProvider);

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

        container.read(previewControllerProvider);
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(container.read(previewControllerProvider), isA<PreviewEmpty>());
        expect(fake.callCount, 0);
      });
    });
  });
}
