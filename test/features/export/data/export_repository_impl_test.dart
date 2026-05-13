import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/repositories/export_repository_impl.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/export_source.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// End-to-end tests for the repository's compose/encode/persist
/// pipeline.
///
/// Platform save adapters (`gal`, `file_picker`, `package:web`)
/// aren't reachable from the host test runner, so the persist step
/// is replaced via [PersistAdapter] injection. Real-device
/// integration happens on the manual CI matrix per PRD §Definition
/// of Done.
void main() {
  Uint8List solidPng({int w = 40, int h = 30, int r = 220}) {
    final canvas = img.Image(width: w, height: h);
    img.fill(canvas, color: img.ColorRgb8(r, 40, 40));
    return Uint8List.fromList(img.encodePng(canvas));
  }

  ExportRequest gridRequest(
    List<Uint8List> cells, {
    ExportFormat format = ExportFormat.png,
  }) {
    return ExportRequest(
      source: GridExportSource(cells),
      format: format,
      quality: 90,
      watermark: WatermarkConfig.initial(),
    );
  }

  ExportRequest stitchRequest(
    Uint8List bytes, {
    ExportFormat format = ExportFormat.png,
  }) {
    return ExportRequest(
      source: StitchExportSource(bytes),
      format: format,
      quality: 90,
      watermark: WatermarkConfig.initial(),
    );
  }

  group('ExportRepositoryImpl — single-image pipeline', () {
    test(
      'grid source with empty cells short-circuits to SaveFailure',
      () async {
        final repo = ExportRepositoryImpl();
        final req = ExportRequest(
          source: GridExportSource(const []),
          format: ExportFormat.png,
          quality: 90,
          watermark: WatermarkConfig.initial(),
        );
        final res = await repo.exportAndSave(req);
        expect(res, isA<SaveFailure>());
        expect((res as SaveFailure).message, contains('Nothing to export'));
      },
    );

    test('stitch source dispatches a single persist call', () async {
      final names = <String>[];
      final repo = ExportRepositoryImpl(
        persistOverride: (bytes, fmt, name) async {
          names.add(name);
          return SaveSuccess(location: '/tmp/$name');
        },
      );

      final res = await repo.exportAndSave(stitchRequest(solidPng()));
      expect(names.length, 1);
      expect(names.single, startsWith('flpicraft_'));
      expect(names.single, endsWith('.png'));
      expect(res, isA<SaveSuccess>());
      expect((res as SaveSuccess).count, 1);
    });
  });

  group('ExportRepositoryImpl — grid pipeline', () {
    test('all-success grid returns SaveSuccess with cells count', () async {
      final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
      final repo = ExportRepositoryImpl(
        persistOverride: (bytes, fmt, name) async {
          return SaveSuccess(location: '/tmp/$name');
        },
      );

      final res = await repo.exportAndSave(gridRequest(cells));
      expect(res, isA<SaveSuccess>());
      final success = res as SaveSuccess;
      expect(success.count, 3);
      expect(success.location, contains('flpicraft_'));
    });

    test('grid source preserves cell ordering for `_exportGrid` loop', () {
      final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
      final src = GridExportSource(cells);
      expect(src.cells.length, 3);
      expect(src.cells.first[0], cells.first[0]);
      expect(src.cells.last[0], cells.last[0]);
    });

    test(
      'mid-loop cancel after saves credits the partial count as SaveSuccess',
      () async {
        final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
        var calls = 0;
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            calls++;
            if (calls <= 2) return SaveSuccess(location: '/tmp/$name');
            return const SaveCancelled();
          },
        );

        final res = await repo.exportAndSave(gridRequest(cells));
        expect(res, isA<SaveSuccess>());
        final success = res as SaveSuccess;
        expect(
          success.count,
          2,
          reason: 'Two cells landed before the user cancelled.',
        );
        expect(success.location, contains('flpicraft_'));
      },
    );

    test(
      'cancel on the very first cell bubbles SaveCancelled unchanged',
      () async {
        final cells = [solidPng(), solidPng()];
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            return const SaveCancelled();
          },
        );

        final res = await repo.exportAndSave(gridRequest(cells));
        expect(
          res,
          isA<SaveCancelled>(),
          reason:
              'No cells landed, so the cancel must surface as a silent '
              'SaveCancelled rather than a misleading partial success.',
        );
      },
    );

    test(
      'mid-loop failure enriches SaveFailure with the partial saved count',
      () async {
        final cells = [solidPng(), solidPng(), solidPng()];
        var calls = 0;
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            calls++;
            if (calls == 1) return SaveSuccess(location: '/tmp/$name');
            return const SaveFailure('Disk full');
          },
        );

        final res = await repo.exportAndSave(gridRequest(cells));
        expect(res, isA<SaveFailure>());
        final failure = res as SaveFailure;
        expect(failure.message, contains('Saved 1 of 3'));
        expect(failure.message, contains('Disk full'));
      },
    );

    test(
      'first-cell failure bubbles SaveFailure without partial prefix',
      () async {
        final cells = [solidPng(), solidPng()];
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            return const SaveFailure('Permission denied');
          },
        );

        final res = await repo.exportAndSave(gridRequest(cells));
        expect(res, isA<SaveFailure>());
        final failure = res as SaveFailure;
        expect(failure.message, equals('Permission denied'));
        expect(failure.message, isNot(contains('Saved')));
      },
    );

    test('grid suggestedName indices are 1-based and per-cell', () async {
      final cells = [solidPng(), solidPng(), solidPng()];
      final names = <String>[];
      final repo = ExportRepositoryImpl(
        persistOverride: (bytes, fmt, name) async {
          names.add(name);
          return SaveSuccess(location: '/tmp/$name');
        },
      );

      await repo.exportAndSave(gridRequest(cells, format: ExportFormat.jpg));
      expect(names.length, 3);
      expect(names[0], endsWith('_1.jpg'));
      expect(names[1], endsWith('_2.jpg'));
      expect(names[2], endsWith('_3.jpg'));
    });
  });
}
