import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/datasources/batch_persist_adapter.dart';
import 'package:fl_picraft/features/export/data/repositories/export_repository_impl.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/export_source.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'datasources/fake_batch_persist_adapter.dart';

/// End-to-end tests for the repository's compose/encode/persist
/// pipeline.
///
/// Platform save adapters (`gal`, `file_picker`, `package:web`)
/// aren't reachable from the host test runner, so:
///   * Single-file (stitch) tests inject via [PersistAdapter].
///   * Grid / multi-image tests inject a [BatchPersistAdapter] via
///     [FakeBatchPersistAdapter] — partial-save accounting itself
///     is verified in the dedicated platform-adapter test files.
///
/// Real-device integration happens on the manual CI matrix per PRD
/// §Definition of Done.
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
        final repo = ExportRepositoryImpl(
          batchAdapter: FakeBatchPersistAdapter(),
        );
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

  group(
    'ExportRepositoryImpl — grid pipeline (BatchPersistAdapter delegation)',
    () {
      test('delegates the batch to the injected adapter (3 cells)', () async {
        final adapter = FakeBatchPersistAdapter();
        final repo = ExportRepositoryImpl(batchAdapter: adapter);
        final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];

        final res = await repo.exportAndSave(gridRequest(cells));

        expect(res, isA<SaveSuccess>());
        final success = res as SaveSuccess;
        expect(success.count, 3);
        expect(
          adapter.callCount,
          1,
          reason: 'Repo must call persistMany once.',
        );
        expect(adapter.lastTotal, 3);
        expect(adapter.lastFormat, ExportFormat.png);
        // Adapter pulled every cell in order via `next`.
        expect(adapter.nextCallIndices, equals([0, 1, 2]));
      });

      test('passes the requested format through to the adapter', () async {
        final adapter = FakeBatchPersistAdapter();
        final repo = ExportRepositoryImpl(batchAdapter: adapter);
        final cells = [solidPng(), solidPng()];

        await repo.exportAndSave(gridRequest(cells, format: ExportFormat.jpg));
        expect(adapter.lastFormat, ExportFormat.jpg);
      });

      test(
        'the same `at` timestamp is shared across one batch (no per-cell drift)',
        () async {
          // The `at` parameter is set inside the repo via `DateTime.now()`
          // at the start of `_exportGrid`. We only check it was passed
          // through to the adapter (the actual stability check lives in
          // per-platform adapter tests).
          final adapter = FakeBatchPersistAdapter();
          final repo = ExportRepositoryImpl(batchAdapter: adapter);
          await repo.exportAndSave(gridRequest([solidPng(), solidPng()]));
          expect(adapter.lastAt, isNotNull);
        },
      );

      test(
        'adapter returning SaveFailure surfaces unchanged from the repo',
        () async {
          final adapter = FakeBatchPersistAdapter(
            overrideResult: const SaveFailure('forced from adapter'),
          );
          final repo = ExportRepositoryImpl(batchAdapter: adapter);

          final res = await repo.exportAndSave(
            gridRequest([solidPng(), solidPng()]),
          );

          expect(res, isA<SaveFailure>());
          expect((res as SaveFailure).message, 'forced from adapter');
        },
      );

      test(
        'adapter returning SaveCancelled surfaces unchanged from the repo',
        () async {
          final adapter = FakeBatchPersistAdapter(
            overrideResult: const SaveCancelled(),
          );
          final repo = ExportRepositoryImpl(batchAdapter: adapter);

          final res = await repo.exportAndSave(
            gridRequest([solidPng(), solidPng()]),
          );

          expect(res, isA<SaveCancelled>());
        },
      );

      test('grid source preserves cell ordering for the adapter loop', () {
        final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
        final src = GridExportSource(cells);
        expect(src.cells.length, 3);
        expect(src.cells.first[0], cells.first[0]);
        expect(src.cells.last[0], cells.last[0]);
      });
    },
  );

  group('ExportRepositoryImpl.persistOnly — multi-cell shortcut', () {
    test(
      'persistOnly with empty bytes returns SaveFailure without invoking adapter',
      () async {
        final adapter = FakeBatchPersistAdapter();
        final repo = ExportRepositoryImpl(batchAdapter: adapter);
        final res = await repo.persistOnly(const [], ExportFormat.png);
        expect(res, isA<SaveFailure>());
        expect(adapter.callCount, 0);
      },
    );

    test('persistOnly with a single byte payload uses the single-cell shortcut '
        '(stitch cache hit)', () async {
      // The stitch cache hit path MUST NOT touch the batch adapter
      // — PRD §4 mandates the stitch single-cell shortcut stays
      // identical to its pre-refactor behavior.
      final adapter = FakeBatchPersistAdapter();
      final names = <String>[];
      final repo = ExportRepositoryImpl(
        batchAdapter: adapter,
        persistOverride: (bytes, fmt, name) async {
          names.add(name);
          return SaveSuccess(location: '/tmp/$name');
        },
      );

      final res = await repo.persistOnly([
        Uint8List.fromList(const [1, 2, 3]),
      ], ExportFormat.png);

      expect(res, isA<SaveSuccess>());
      expect(names.length, 1);
      expect(
        adapter.callCount,
        0,
        reason:
            'Single-cell shortcut must bypass the batch adapter so '
            'stitch cache hits stay byte-identical to pre-refactor.',
      );
    });

    test(
      'persistOnly with multiple byte payloads routes through the batch adapter',
      () async {
        final adapter = FakeBatchPersistAdapter();
        final repo = ExportRepositoryImpl(batchAdapter: adapter);
        final bytes = [
          Uint8List.fromList(const [1]),
          Uint8List.fromList(const [2]),
          Uint8List.fromList(const [3]),
        ];

        final res = await repo.persistOnly(bytes, ExportFormat.jpg);

        expect(res, isA<SaveSuccess>());
        expect(adapter.callCount, 1);
        expect(adapter.lastTotal, 3);
        expect(adapter.lastFormat, ExportFormat.jpg);
        // Adapter pulled all three cells, and the bytes are the very
        // same Uint8Lists the caller passed in (no re-encode).
        expect(adapter.pulledBytes, hasLength(3));
        expect(adapter.pulledBytes[0], same(bytes[0]));
        expect(adapter.pulledBytes[1], same(bytes[1]));
        expect(adapter.pulledBytes[2], same(bytes[2]));
      },
    );
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
    // their output is captured via the `persistOverride` (stitch path) or
    // the FakeBatchPersistAdapter (grid path) seams — proving the pipeline
    // returns identical bytes whether the hop runs in a worker or on the
    // same isolate.

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
      // Capture the processed bytes via a recording fake adapter so we
      // can assert that each cell ran through the isolate-callable
      // `_processOne` and produced a decodable image.
      final cells = [solidPng(r: 10), solidPng(r: 100), solidPng(r: 200)];
      final adapter = FakeBatchPersistAdapter();
      final repo = ExportRepositoryImpl(batchAdapter: adapter);

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
      expect(adapter.pulledBytes, hasLength(3));
      // Each pulled cell must round-trip as a decodable image — the
      // isolate hop ran three times without truncating the output.
      for (final bytes in adapter.pulledBytes) {
        expect(bytes, isNotNull);
        final decoded = img.decodeImage(bytes!);
        expect(decoded, isNotNull);
        expect(decoded!.width, 40);
        expect(decoded.height, 30);
      }
    });
  });
}
