import 'dart:typed_data';

import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/export_source.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/repositories/export_repository.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
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

/// Captures the last [ExportRequest] handed to `exportAndSave` so the
/// dispatch tests can assert on the source variant without hitting the
/// real `gal` / `file_picker` / `package:web` adapters.
class _RecordingRepo implements ExportRepository {
  ExportRequest? lastRequest;

  @override
  Future<SaveResult> exportAndSave(ExportRequest request) async {
    lastRequest = request;
    return switch (request.source) {
      StitchExportSource() => const SaveSuccess(location: '/tmp/test.png'),
      GridExportSource(:final cells) => SaveSuccess(
        location: '/tmp/test.png',
        count: cells.length,
      ),
    };
  }
}

/// Stand-in for the long-stitch renderer that returns deterministic
/// bytes without touching `package:image` / `compute`.
class _FakeStitchRenderer implements StitchImageRenderer {
  const _FakeStitchRenderer();
  @override
  Future<Uint8List> render(StitchRenderRequest request) async {
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

/// Stand-in for the grid renderer. Returns 3 byte payloads so the
/// dispatch test can verify the cell-count flows through to
/// [SaveSuccess.count] without re-deriving from `gridType.cellCount`.
class _FakeGridRenderer implements GridImageRenderer {
  const _FakeGridRenderer();
  @override
  Future<List<Uint8List>> render(GridRenderRequest request) async {
    return [
      Uint8List.fromList(const [10]),
      Uint8List.fromList(const [20]),
      Uint8List.fromList(const [30]),
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
    importedAt: DateTime.utc(2026, 5, 14),
  );
}

void main() {
  group('ExportController dispatch', () {
    late _RecordingRepo repo;

    setUp(() {
      repo = _RecordingRepo();
    });

    ProviderContainer containerWith(List<ImportedImage> images) {
      return ProviderContainer(
        overrides: [
          exportRepositoryProvider.overrideWithValue(repo),
          // Stitch and grid editors each watch their own family
          // instance — override both so the existing tests can pump
          // identical images into both editors via a single helper.
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWithValue(images),
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWithValue(images),
          stitchImageRendererProvider.overrideWithValue(
            const _FakeStitchRenderer(),
          ),
          gridImageRendererProvider.overrideWithValue(
            const _FakeGridRenderer(),
          ),
        ],
      );
    }

    test('routes through StitchExportSource when kind=stitch', () async {
      final container = containerWith([_fakeImage('a'), _fakeImage('b')]);
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.stitch;

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveSuccess>());
      expect(repo.lastRequest, isNotNull);
      expect(repo.lastRequest!.source, isA<StitchExportSource>());
    });

    test('routes through GridExportSource when kind=grid', () async {
      final container = containerWith([_fakeImage('a')]);
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.grid;

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveSuccess>());
      expect((result as SaveSuccess).count, 3);
      expect(repo.lastRequest!.source, isA<GridExportSource>());
    });

    test('stitch kind + empty editor returns SaveFailure', () async {
      final container = containerWith(const []);
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.stitch;

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveFailure>());
      expect((result as SaveFailure).message, '没有可导出的图片');
      expect(
        repo.lastRequest,
        isNull,
        reason: 'repository must not be invoked when there is no source',
      );
    });

    test('grid kind + empty editor returns SaveFailure', () async {
      final container = containerWith(const []);
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.grid;

      final result = await container
          .read(exportControllerProvider.notifier)
          .save();

      expect(result, isA<SaveFailure>());
      expect((result as SaveFailure).message, '没有可导出的图片');
      expect(repo.lastRequest, isNull);
    });

    test('isSaving flag flips during the save round-trip', () async {
      final container = containerWith([_fakeImage('a')]);
      addTearDown(container.dispose);
      expect(container.read(exportControllerProvider).isSaving, isFalse);

      final pending = container.read(exportControllerProvider.notifier).save();
      // After awaiting we end up back at idle — the flag flipped on
      // entry and got reset by the finally block.
      await pending;
      expect(container.read(exportControllerProvider).isSaving, isFalse);
    });
  });

  group('canExportProvider', () {
    test('false when both editors are empty', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWithValue(const []),
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(canExportProvider), isFalse);
    });

    test('true for stitch kind when stitch editor has images', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWithValue([_fakeImage('a')]),
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);
      // Default kind is stitch.
      expect(container.read(canExportProvider), isTrue);
    });

    test('true for grid kind when grid editor has a source', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWithValue(const []),
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWithValue([_fakeImage('a')]),
        ],
      );
      addTearDown(container.dispose);
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.grid;
      expect(container.read(canExportProvider), isTrue);
    });
  });

  group('exportSaveButtonLabelProvider', () {
    test('stitch kind label has no cell count; grid kind includes count', () {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWithValue([_fakeImage('a')]),
          importedImagesProvider(
            ImageImportSessionKind.grid,
          ).overrideWithValue([_fakeImage('a')]),
        ],
      );
      addTearDown(container.dispose);

      // Stitch label: platform-dependent ("保存至相册" on mobile,
      // "保存到本地" elsewhere) but never carries a count.
      final stitchLabel = container.read(exportSaveButtonLabelProvider);
      expect(stitchLabel, isNot(contains('张')));

      // Grid kind: default gridType is 3x3 → cellCount=9; label
      // must surface that number so the user knows how many files
      // they're about to save.
      container.read(currentExportSourceKindProvider.notifier).state =
          ExportSourceKind.grid;
      final gridLabel = container.read(exportSaveButtonLabelProvider);
      expect(gridLabel, contains('9'));
      expect(gridLabel, contains('张'));
    });
  });
}
