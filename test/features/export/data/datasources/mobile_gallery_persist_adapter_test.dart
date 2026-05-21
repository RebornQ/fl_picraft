import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/datasources/gallery_saver_datasource.dart';
import 'package:fl_picraft/features/export/data/datasources/mobile_gallery_persist_adapter.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-test substitute for [GallerySaverDataSource] — overrides
/// [save] so the per-call behavior can be scripted without touching
/// the real `gal` plugin channel.
class _FakeGallerySaverDataSource extends GallerySaverDataSource {
  _FakeGallerySaverDataSource({required this.behavior}) : super();

  /// Behavior per call index — returns the SaveResult to surface or
  /// throws if `behavior(i)` itself throws synchronously.
  final SaveResult Function(int callIndex) behavior;

  /// File names handed to [save] in invocation order — assertion
  /// material for the "no double-extension" rule and 1-based index
  /// naming.
  final List<String> calledFileNames = <String>[];
  int callCount = 0;

  @override
  Future<SaveResult> save(
    Uint8List bytes, {
    required String fileName,
    String? album = kGalleryAlbumName,
  }) async {
    final i = callCount;
    callCount++;
    calledFileNames.add(fileName);
    return behavior(i);
  }
}

void main() {
  group('MobileGalleryPersistAdapter', () {
    test('all-success batch returns SaveSuccess with count = total', () async {
      final gallery = _FakeGallerySaverDataSource(
        behavior: (_) => const SaveSuccess(location: 'Photos'),
      );
      final adapter = MobileGalleryPersistAdapter(gallery: gallery);

      final result = await adapter.persistMany(
        total: 3,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveSuccess>());
      final success = result as SaveSuccess;
      expect(success.count, 3);
      expect(success.location, 'Photos');
      expect(gallery.callCount, 3);
    });

    test(
      'Kth-cell failure returns partial SaveFailure with prior saves credited',
      () async {
        final gallery = _FakeGallerySaverDataSource(
          behavior: (i) => i == 2
              ? const SaveFailure('Permission denied')
              : const SaveSuccess(location: 'Photos'),
        );
        final adapter = MobileGalleryPersistAdapter(gallery: gallery);

        final result = await adapter.persistMany(
          total: 4,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        final failure = result as SaveFailure;
        expect(failure.message, contains('已保存 2 / 4'));
        expect(failure.message, contains('Permission denied'));
        // Adapter stopped at the failing cell — no calls past index 2.
        expect(gallery.callCount, 3);
      },
    );

    test(
      'first-cell failure returns plain SaveFailure (no partial prefix)',
      () async {
        final gallery = _FakeGallerySaverDataSource(
          behavior: (_) => const SaveFailure('Permission denied'),
        );
        final adapter = MobileGalleryPersistAdapter(gallery: gallery);

        final result = await adapter.persistMany(
          total: 3,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        final failure = result as SaveFailure;
        expect(
          failure.message,
          isNot(contains('已保存')),
          reason: 'No cells landed → no partial prefix.',
        );
        expect(failure.message, equals('Permission denied'));
      },
    );

    test('thrown exception mid-loop converts to partial SaveFailure', () async {
      final gallery = _FakeGallerySaverDataSource(
        behavior: (i) {
          if (i == 1) throw Exception('Channel error');
          return const SaveSuccess(location: 'Photos');
        },
      );
      final adapter = MobileGalleryPersistAdapter(gallery: gallery);

      final result = await adapter.persistMany(
        total: 4,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      final failure = result as SaveFailure;
      expect(failure.message, contains('已保存 1 / 4'));
      expect(failure.message, contains('Channel error'));
    });

    test(
      'strips the `.png` / `.jpg` extension before forwarding to gal',
      () async {
        final gallery = _FakeGallerySaverDataSource(
          behavior: (_) => const SaveSuccess(location: 'Photos'),
        );
        final adapter = MobileGalleryPersistAdapter(gallery: gallery);

        await adapter.persistMany(
          total: 2,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.jpg,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        // gal infers the file extension from the bytes' magic numbers and
        // appends its own — passing a `*.jpg`-suffixed name would
        // produce `foo.jpg.jpg` on Android. The adapter must strip the
        // extension before delegating.
        expect(gallery.calledFileNames, hasLength(2));
        for (final name in gallery.calledFileNames) {
          expect(
            name.endsWith('.png'),
            isFalse,
            reason:
                'Adapter must strip the extension before forwarding to '
                'gal — saw `$name`.',
          );
          expect(name.endsWith('.jpg'), isFalse);
        }
        expect(gallery.calledFileNames[0], 'flpicraft_20260521_120607_1');
        expect(gallery.calledFileNames[1], 'flpicraft_20260521_120607_2');
      },
    );

    test(
      'next returning null mid-stream stops cleanly with saved count',
      () async {
        final gallery = _FakeGallerySaverDataSource(
          behavior: (_) => const SaveSuccess(location: 'Photos'),
        );
        final adapter = MobileGalleryPersistAdapter(gallery: gallery);

        final result = await adapter.persistMany(
          total: 5,
          next: (i) async {
            if (i == 3) return null;
            return Uint8List.fromList([i + 1]);
          },
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveSuccess>());
        expect((result as SaveSuccess).count, 3);
        expect(gallery.callCount, 3);
      },
    );

    test('total = 0 short-circuits without touching gal', () async {
      final gallery = _FakeGallerySaverDataSource(
        behavior: (_) => const SaveSuccess(location: 'Photos'),
      );
      final adapter = MobileGalleryPersistAdapter(gallery: gallery);

      final result = await adapter.persistMany(
        total: 0,
        next: (i) async => null,
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      expect(gallery.callCount, 0);
    });

    test(
      'preserves the `at` timestamp across all per-cell filenames',
      () async {
        final gallery = _FakeGallerySaverDataSource(
          behavior: (_) => const SaveSuccess(location: 'Photos'),
        );
        final adapter = MobileGalleryPersistAdapter(gallery: gallery);

        await adapter.persistMany(
          total: 3,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        // All filenames must share the same timestamp prefix — proves
        // the adapter doesn't accidentally re-call DateTime.now() per
        // cell, which would let the timestamps drift.
        final timestamps = gallery.calledFileNames
            .map((name) => name.split('_').sublist(1, 3).join('_'))
            .toSet();
        expect(timestamps.length, 1);
        expect(timestamps.single, '20260521_120607');
      },
    );
  });
}
