import 'dart:typed_data';

import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
import 'package:fl_picraft/features/export/presentation/providers/processed_bytes_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRU + cache-key contract tests for [ProcessedBytesCache] and
/// [computeProcessedBytesCacheKey].
///
/// Pure unit tests — no provider container needed because the cache
/// class is a plain Dart value with no Riverpod dependencies (the
/// notifier just exposes it).
void main() {
  Uint8List bytes(int seed) => Uint8List.fromList([seed]);

  group('ProcessedBytesCache — LRU semantics', () {
    test('write below capacity stores every entry', () {
      final cache = ProcessedBytesCache(capacity: 4);
      cache.write(1, [bytes(1)]);
      cache.write(2, [bytes(2)]);
      cache.write(3, [bytes(3)]);
      expect(cache.length, 3);
      expect(cache.read(1)?.first, bytes(1));
      expect(cache.read(2)?.first, bytes(2));
      expect(cache.read(3)?.first, bytes(3));
    });

    test('write beyond capacity evicts the oldest entry', () {
      final cache = ProcessedBytesCache(capacity: 3);
      cache.write(1, [bytes(1)]);
      cache.write(2, [bytes(2)]);
      cache.write(3, [bytes(3)]);
      cache.write(4, [bytes(4)]); // evict 1
      expect(cache.length, 3);
      expect(cache.read(1), isNull);
      expect(cache.read(2)?.first, bytes(2));
      expect(cache.read(3)?.first, bytes(3));
      expect(cache.read(4)?.first, bytes(4));
    });

    test('read promotes the entry to most-recently-used', () {
      final cache = ProcessedBytesCache(capacity: 3);
      cache.write(1, [bytes(1)]);
      cache.write(2, [bytes(2)]);
      cache.write(3, [bytes(3)]);
      // Touch 1 — it becomes MRU.
      cache.read(1);
      // Inserting a new entry should now evict 2 (the new LRU), not 1.
      cache.write(4, [bytes(4)]);
      expect(cache.read(2), isNull);
      expect(cache.read(1)?.first, bytes(1));
    });

    test('write to existing key updates value and refreshes recency', () {
      final cache = ProcessedBytesCache(capacity: 2);
      cache.write(1, [bytes(1)]);
      cache.write(2, [bytes(2)]);
      cache.write(1, [bytes(9)]); // overwrite + refresh
      cache.write(3, [bytes(3)]); // would evict the LRU
      expect(cache.read(2), isNull, reason: '2 was LRU after the refresh');
      expect(cache.read(1)?.first, bytes(9));
      expect(cache.read(3)?.first, bytes(3));
    });

    test('invalidate clears every entry', () {
      final cache = ProcessedBytesCache(capacity: 4);
      cache.write(1, [bytes(1)]);
      cache.write(2, [bytes(2)]);
      cache.invalidate();
      expect(cache.length, 0);
      expect(cache.read(1), isNull);
      expect(cache.read(2), isNull);
    });

    test('default capacity matches kProcessedBytesCacheCapacity', () {
      final cache = ProcessedBytesCache();
      for (var i = 0; i < kProcessedBytesCacheCapacity + 2; i++) {
        cache.write(i, [bytes(i)]);
      }
      expect(cache.length, kProcessedBytesCacheCapacity);
      // The earliest 2 entries (0, 1) should be gone.
      expect(cache.read(0), isNull);
      expect(cache.read(1), isNull);
    });
  });

  group('computeProcessedBytesCacheKey — equality semantics', () {
    final wmA = WatermarkConfig.initial();
    final wmB = wmA.copyWith(enabled: true, text: 'Hi');
    final wmC = wmA.copyWith(
      enabled: true,
      text: 'Hi',
      anchor: WatermarkAnchor.topLeft,
    );

    test('identical inputs produce identical keys', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      expect(k1, equals(k2));
    });

    test('different watermark changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmB,
        format: ExportFormat.png,
        quality: 85,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('different anchor changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmB,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmC,
        format: ExportFormat.png,
        quality: 85,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('different kind changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.grid,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('different format changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.jpg,
        quality: 85,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('different quality changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.jpg,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.jpg,
        quality: 90,
      );
      expect(k1, isNot(equals(k2)));
    });

    test('different editor state hash changes the key', () {
      final k1 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 123,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      final k2 = computeProcessedBytesCacheKey(
        kind: ExportSourceKind.stitch,
        editorStateHash: 456,
        watermark: wmA,
        format: ExportFormat.png,
        quality: 85,
      );
      expect(k1, isNot(equals(k2)));
    });
  });
}
