import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/datasources/batch_persist_adapter.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_batch_persist_adapter.dart';

/// Pull-based contract tests for [BatchPersistAdapter].
///
/// These tests assert the **public contract** every adapter must obey
/// regardless of its platform-specific persistence logic — i.e. the
/// repository can hand any conforming adapter the same `next(i)`
/// closure and expect consistent invocation semantics.
///
/// The platform adapters' per-target behavior (desktop dialog,
/// mobile gal, web zip) is tested in dedicated `*_persist_adapter_test.dart`
/// files.
void main() {
  group('BatchPersistAdapter contract — FakeBatchPersistAdapter', () {
    test('next(i) is NOT called before the adapter decides to pull', () async {
      // Pre-condition: configure the fake to pull 0 cells. Even though
      // `total = 3`, the adapter must not call `next` at all because
      // its own pull policy is "stop before any pull".
      final adapter = FakeBatchPersistAdapter(pullCount: 0);
      var nextCallCount = 0;

      await adapter.persistMany(
        total: 3,
        next: (i) async {
          nextCallCount++;
          return Uint8List.fromList([i]);
        },
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(
        nextCallCount,
        0,
        reason:
            'Adapter must not pull from `next` when its own pull '
            'policy decides to skip.',
      );
    });

    test('next(i) is called sequentially with indices 0..total-1', () async {
      final adapter = FakeBatchPersistAdapter();
      final indices = <int>[];

      await adapter.persistMany(
        total: 4,
        next: (i) async {
          indices.add(i);
          return Uint8List.fromList([i]);
        },
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(indices, equals([0, 1, 2, 3]));
      expect(
        adapter.nextCallIndices,
        equals([0, 1, 2, 3]),
        reason: 'Fake adapter must record every pull in invocation order.',
      );
    });

    test('next returning null is treated as end-of-input', () async {
      // The fake should stop pulling at the first null and treat the
      // landed count as `total - 1` (only the first 2 cells produced
      // bytes).
      final adapter = FakeBatchPersistAdapter();
      var nextCallCount = 0;

      final result = await adapter.persistMany(
        total: 5,
        next: (i) async {
          nextCallCount++;
          if (i == 2) return null;
          return Uint8List.fromList([i]);
        },
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(
        nextCallCount,
        3,
        reason:
            'Adapter must call next(0), next(1), next(2) — stops at '
            'the null return, never reaches indices 3 or 4.',
      );
      // The fake's default result mirrors the landed count (entries
      // where bytes != null) — should be 2.
      expect(result, isA<SaveSuccess>());
      expect((result as SaveSuccess).count, 2);
    });

    test(
      'persistMany passes (total, format, at) through to the adapter unchanged',
      () async {
        final adapter = FakeBatchPersistAdapter();
        final stamp = DateTime(2026, 5, 21, 12, 6, 7);

        await adapter.persistMany(
          total: 9,
          next: (i) async => Uint8List.fromList([0]),
          format: ExportFormat.jpg,
          at: stamp,
        );

        expect(adapter.lastTotal, 9);
        expect(adapter.lastFormat, ExportFormat.jpg);
        expect(adapter.lastAt, stamp);
        expect(adapter.callCount, 1);
      },
    );

    test('overrideResult is honored when configured', () async {
      final adapter = FakeBatchPersistAdapter(
        overrideResult: const SaveFailure('forced'),
      );

      final result = await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      expect((result as SaveFailure).message, 'forced');
    });

    test(
      'subsequent persistMany calls reset the recorded invocation log',
      () async {
        final adapter = FakeBatchPersistAdapter();
        await adapter.persistMany(
          total: 2,
          next: (i) async => Uint8List.fromList([i]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21),
        );
        expect(adapter.nextCallIndices, equals([0, 1]));

        await adapter.persistMany(
          total: 1,
          next: (i) async => Uint8List.fromList([i]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 22),
        );

        expect(
          adapter.nextCallIndices,
          equals([0]),
          reason:
              'Each persistMany call must clear the per-call log so '
              'assertions reflect the most recent invocation.',
        );
        expect(adapter.callCount, 2);
      },
    );
  });

  group('defaultBatchPersistAdapter()', () {
    test(
      'returns an instance that conforms to the BatchPersistAdapter interface',
      () {
        // Under flutter_test the default target platform is set by
        // the test binding (typically android / macos depending on host),
        // so we can't strictly assert which subclass we get — only that
        // the factory returns a non-null adapter.
        final adapter = defaultBatchPersistAdapter();
        expect(adapter, isA<BatchPersistAdapter>());
      },
    );
  });
}
