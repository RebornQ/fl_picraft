import 'dart:typed_data';

import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/export_source.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/repositories/export_repository.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
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

/// Tests for the save-path cache-hit optimization
/// (PRD §6 + §8.4 of `05-20-preview-renderer-infra/prd.md`).
///
/// When the preview controller has already processed identical bytes,
/// [ExportController.save] must read them from
/// [processedBytesCacheProvider] and route through
/// [ExportRepository.persistOnly] instead of the full `exportAndSave`
/// pipeline (which would redo the 1~2 s isolate hop).
///
/// Plain `test` + manual `ProviderContainer` — the assertions target
/// provider state and repository invocation counts, not widget output.

class _CountingRepo implements ExportRepository {
  int exportAndSaveCalls = 0;
  int persistOnlyCalls = 0;
  ExportRequest? lastRequest;
  List<Uint8List>? lastPersistOnlyBytes;
  ExportFormat? lastPersistOnlyFormat;

  @override
  Future<SaveResult> exportAndSave(ExportRequest request) async {
    exportAndSaveCalls++;
    lastRequest = request;
    return switch (request.source) {
      StitchExportSource() => const SaveSuccess(location: '/tmp/test.png'),
      GridExportSource(:final cells) => SaveSuccess(
        location: '/tmp/test.png',
        count: cells.length,
      ),
    };
  }

  @override
  Future<SaveResult> persistOnly(
    List<Uint8List> processed,
    ExportFormat format,
  ) async {
    persistOnlyCalls++;
    lastPersistOnlyBytes = processed;
    lastPersistOnlyFormat = format;
    return SaveSuccess(location: '/tmp/test.png', count: processed.length);
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
  required _CountingRepo repo,
  List<ImportedImage> stitchImages = const [],
  List<ImportedImage> gridImages = const [],
}) {
  return ProviderContainer(
    overrides: [
      exportRepositoryProvider.overrideWithValue(repo),
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
  group('ExportController.save() — cache-hit fast path', () {
    test('cache hit skips exportAndSave and calls persistOnly', () async {
      final repo = _CountingRepo();
      final container = _makeContainer(
        repo: repo,
        stitchImages: [_fakeImage('a')],
      );
      addTearDown(container.dispose);

      // Compute the key for the current input and pre-populate the
      // cache as if the preview controller had already rendered.
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.stitch;
      final editor = container.read(stitchEditorControllerProvider);
      final watermark = container.read(watermarkConfigProvider);
      final exportState = container.read(exportControllerProvider);

      final key = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: editor.hashCode,
        watermark: watermark,
        format: exportState.format,
        quality: exportState.quality,
      );
      final cachedBytes = [
        Uint8List.fromList(const [9, 9, 9, 9]),
      ];
      container
          .read(processedBytesCacheProvider.notifier)
          .write(key, cachedBytes);

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveSuccess>());
      expect(
        repo.persistOnlyCalls,
        1,
        reason: 'cache hit must go through persistOnly',
      );
      expect(
        repo.exportAndSaveCalls,
        0,
        reason: 'cache hit must skip exportAndSave entirely',
      );
      expect(repo.lastPersistOnlyBytes, equals(cachedBytes));
      expect(repo.lastPersistOnlyFormat, exportState.format);
    });

    test('cache miss falls through to exportAndSave', () async {
      final repo = _CountingRepo();
      final container = _makeContainer(
        repo: repo,
        stitchImages: [_fakeImage('a')],
      );
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.stitch;

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveSuccess>());
      expect(
        repo.exportAndSaveCalls,
        1,
        reason: 'cache miss must invoke the full pipeline',
      );
      expect(repo.persistOnlyCalls, 0);
      expect(repo.lastRequest!.source, isA<StitchExportSource>());
    });

    test('cache hit honors current format even if cache key differs', () async {
      // Sanity guard: if the controller used the wrong key derivation
      // (e.g. forgot to read the current format), the cache write
      // below wouldn't hit and persistOnly would be skipped.
      final repo = _CountingRepo();
      final container = _makeContainer(
        repo: repo,
        stitchImages: [_fakeImage('a')],
      );
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.stitch;
      // Switch to JPG so the key derivation depends on format.
      container
          .read(exportControllerProvider.notifier)
          .setFormat(ExportFormat.jpg);

      final editor = container.read(stitchEditorControllerProvider);
      final watermark = container.read(watermarkConfigProvider);
      final exportState = container.read(exportControllerProvider);
      final key = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: editor.hashCode,
        watermark: watermark,
        format: exportState.format,
        quality: exportState.quality,
      );
      container.read(processedBytesCacheProvider.notifier).write(key, [
        Uint8List.fromList(const [1]),
      ]);

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();
      expect(result, isA<SaveSuccess>());
      expect(repo.persistOnlyCalls, 1);
      expect(repo.lastPersistOnlyFormat, ExportFormat.jpg);
    });

    test('grid kind cache hit also routes through persistOnly', () async {
      final repo = _CountingRepo();
      final container = _makeContainer(
        repo: repo,
        gridImages: [_fakeImage('a')],
      );
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.grid;

      final editor = container.read(gridEditorControllerProvider);
      final watermark = container.read(watermarkConfigProvider);
      final exportState = container.read(exportControllerProvider);
      final key = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.grid,
        editorStateHash: editor.hashCode,
        watermark: watermark,
        format: exportState.format,
        quality: exportState.quality,
      );
      final cachedBytes = [
        Uint8List.fromList(const [1, 2]),
        Uint8List.fromList(const [3, 4]),
      ];
      container
          .read(processedBytesCacheProvider.notifier)
          .write(key, cachedBytes);

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveSuccess>());
      expect((result as SaveSuccess).count, 2);
      expect(repo.persistOnlyCalls, 1);
      expect(repo.exportAndSaveCalls, 0);
      expect(repo.lastPersistOnlyBytes, equals(cachedBytes));
    });
  });
}
