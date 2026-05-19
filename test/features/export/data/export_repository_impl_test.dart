import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/repositories/export_repository_impl.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/export_source.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
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
        expect((res as SaveFailure).message, contains('没有可导出'));
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
        expect(failure.message, contains('已保存 1 / 3'));
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
        expect(failure.message, isNot(contains('已保存')));
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

  group('ExportRepositoryImpl — isolate-hop (`_processOne` via compute)', () {
    // These tests cover the spec validation requirement from
    // `.trellis/spec/frontend/directory-structure.md` →
    // "Pattern: Isolate-safe rasterizer in `data/`":
    //   "Add a test that calls the function via `await compute(fn, input)` —
    //   not just `await fn(input)`. Many `dart:ui` failures only surface on
    //   the isolate path."
    //
    // Under `flutter_test`, `compute` either spawns a real isolate (VM
    // platforms) or falls back to synchronous execution (web / no-binding
    // environments). Either way the watermark + encode stages execute and
    // their output is captured via the `persistOverride` seam — proving the
    // pipeline returns identical bytes whether the hop runs in a worker or
    // on the same isolate.

    ExportRequest watermarkedStitch(
      Uint8List bytes, {
      ExportFormat format = ExportFormat.png,
    }) {
      return ExportRequest(
        source: StitchExportSource(bytes),
        format: format,
        quality: 90,
        watermark: WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Hi',
          anchor: WatermarkAnchor.bottomRight,
        ),
      );
    }

    test(
      'stitch with watermark enabled returns SaveSuccess (exercises compute path)',
      () async {
        Uint8List? captured;
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            captured = bytes;
            return SaveSuccess(location: '/tmp/$name');
          },
        );

        final res = await repo.exportAndSave(watermarkedStitch(solidPng()));
        expect(res, isA<SaveSuccess>());
        expect(captured, isNotNull);
        // Output must still decode as a valid PNG of the source dimensions
        // — i.e. the isolate-hop did not corrupt the bytes.
        final decoded = img.decodeImage(captured!);
        expect(decoded, isNotNull);
        expect(decoded!.width, 40);
        expect(decoded.height, 30);
      },
    );

    test(
      'same input + config produces deterministic bytes across two invocations',
      () async {
        final fixture = solidPng();
        final captures = <Uint8List>[];
        final repo = ExportRepositoryImpl(
          persistOverride: (bytes, fmt, name) async {
            captures.add(bytes);
            return SaveSuccess(location: '/tmp/$name');
          },
        );

        await repo.exportAndSave(watermarkedStitch(fixture));
        await repo.exportAndSave(watermarkedStitch(fixture));

        expect(captures.length, 2);
        // Watermark composite + PNG encode is deterministic — the two
        // pipeline runs must yield byte-identical output regardless of
        // whether the isolate hop is real or synthetic.
        expect(captures[0], equals(captures[1]));
      },
    );

    test('grid path also flows through the isolate hop per cell', () async {
      final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
      final captured = <Uint8List>[];
      final repo = ExportRepositoryImpl(
        persistOverride: (bytes, fmt, name) async {
          captured.add(bytes);
          return SaveSuccess(location: '/tmp/$name');
        },
      );

      final req = ExportRequest(
        source: GridExportSource(cells),
        format: ExportFormat.png,
        quality: 90,
        watermark: WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Hi',
        ),
      );

      final res = await repo.exportAndSave(req);
      expect(res, isA<SaveSuccess>());
      expect(captured.length, 3);
      // Each captured cell must round-trip as a decodable image — the
      // isolate hop ran three times without truncating the output.
      for (final bytes in captured) {
        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 40);
        expect(decoded.height, 30);
      }
    });
  });
}
