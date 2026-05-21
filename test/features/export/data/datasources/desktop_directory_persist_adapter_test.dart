import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/datasources/desktop_directory_persist_adapter.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DesktopDirectoryPersistAdapter', () {
    test(
      'getDirectoryPath returning null yields SaveCancelled and never pulls',
      () async {
        var nextCallCount = 0;
        var writeCallCount = 0;
        final adapter = DesktopDirectoryPersistAdapter(
          directoryPicker: ({String? dialogTitle}) async => null,
          fileWriter: (path, bytes) async => writeCallCount++,
        );

        final result = await adapter.persistMany(
          total: 3,
          next: (i) async {
            nextCallCount++;
            return Uint8List.fromList([i]);
          },
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveCancelled>());
        expect(
          nextCallCount,
          0,
          reason:
              'Adapter must not pull from `next` when the user '
              'dismisses the directory dialog.',
        );
        expect(writeCallCount, 0);
      },
    );

    test(
      'all-success batch writes every cell and returns SaveSuccess',
      () async {
        final writes = <(String, Uint8List)>[];
        final adapter = DesktopDirectoryPersistAdapter(
          directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
          fileWriter: (path, bytes) async => writes.add((path, bytes)),
        );

        final result = await adapter.persistMany(
          total: 3,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveSuccess>());
        final success = result as SaveSuccess;
        expect(success.count, 3);
        expect(success.location, '/tmp/exports');
        expect(writes.length, 3);
        // 1-based index suffixes; timestamp baked in from `at`.
        expect(
          writes[0].$1,
          p.join('/tmp/exports', 'flpicraft_20260521_120607_1.png'),
        );
        expect(
          writes[1].$1,
          p.join('/tmp/exports', 'flpicraft_20260521_120607_2.png'),
        );
        expect(
          writes[2].$1,
          p.join('/tmp/exports', 'flpicraft_20260521_120607_3.png'),
        );
        expect(writes[0].$2, equals(Uint8List.fromList([1])));
        expect(writes[2].$2, equals(Uint8List.fromList([3])));
      },
    );

    test(
      'Kth-cell write failure returns partial SaveFailure and retains earlier files',
      () async {
        final writes = <String>[];
        final adapter = DesktopDirectoryPersistAdapter(
          directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
          fileWriter: (path, bytes) async {
            writes.add(path);
            if (writes.length == 3) {
              throw Exception('Disk full');
            }
          },
        );

        final result = await adapter.persistMany(
          total: 4,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        final failure = result as SaveFailure;
        // partialSaveFailureMessage frame: "已保存 X / Y 张后失败：…".
        expect(failure.message, contains('已保存 2 / 4'));
        expect(failure.message, contains('Disk full'));
        // The first two writes "stuck" on disk (they're not rolled
        // back — PRD D8 mandates we keep partial files).
        expect(writes.length, 3);
      },
    );

    test(
      'first-cell write failure returns plain SaveFailure (no partial prefix)',
      () async {
        final adapter = DesktopDirectoryPersistAdapter(
          directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
          fileWriter: (path, bytes) async =>
              throw Exception('Permission denied'),
        );

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
          reason: 'Failing on the first cell means 0 cells landed.',
        );
        expect(failure.message, contains('Permission denied'));
      },
    );

    test(
      'next returning null mid-stream stops cleanly with saved count',
      () async {
        final writes = <String>[];
        final adapter = DesktopDirectoryPersistAdapter(
          directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
          fileWriter: (path, bytes) async => writes.add(path),
        );

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
        final success = result as SaveSuccess;
        expect(success.count, 3);
        expect(writes.length, 3);
      },
    );

    test('total = 0 returns SaveFailure without invoking the dialog', () async {
      var dialogCalls = 0;
      final adapter = DesktopDirectoryPersistAdapter(
        directoryPicker: ({String? dialogTitle}) async {
          dialogCalls++;
          return '/tmp/exports';
        },
        fileWriter: (path, bytes) async {},
      );

      final result = await adapter.persistMany(
        total: 0,
        next: (i) async => null,
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      expect(
        dialogCalls,
        0,
        reason:
            'Empty input should not bother the user with a directory '
            'dialog.',
      );
    });

    test('directory picker throwing rolls into SaveFailure', () async {
      final adapter = DesktopDirectoryPersistAdapter(
        directoryPicker: ({String? dialogTitle}) async =>
            throw Exception('Channel error'),
        fileWriter: (path, bytes) async {},
      );

      final result = await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      expect((result as SaveFailure).message, contains('Channel error'));
    });

    test('JPG format produces `.jpg`-suffixed filenames', () async {
      final writes = <String>[];
      final adapter = DesktopDirectoryPersistAdapter(
        directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
        fileWriter: (path, bytes) async => writes.add(path),
      );

      await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.jpg,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(writes[0], endsWith('flpicraft_20260521_120607_1.jpg'));
      expect(writes[1], endsWith('flpicraft_20260521_120607_2.jpg'));
    });

    test('uses the same timestamp `at` for every cell in a batch', () async {
      final writes = <String>[];
      final adapter = DesktopDirectoryPersistAdapter(
        directoryPicker: ({String? dialogTitle}) async => '/tmp/exports',
        fileWriter: (path, bytes) async => writes.add(path),
      );

      await adapter.persistMany(
        total: 3,
        next: (i) async => Uint8List.fromList([i]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      // Every filename must share the same `flpicraft_<ts>_<i>.<ext>`
      // timestamp prefix — if the adapter accidentally called
      // `DateTime.now()` internally, the timestamps would drift
      // by a millisecond and fail this equality.
      final timestamps = writes
          .map((path) => p.basename(path).split('_').sublist(1, 3).join('_'))
          .toSet();
      expect(
        timestamps.length,
        1,
        reason:
            'All cells in one batch must share the timestamp the '
            'repository computed at the start.',
      );
    });
  });
}
