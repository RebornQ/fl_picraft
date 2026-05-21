import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/usecases/suggested_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestedName', () {
    test('builds `flpicraft_<timestamp>.<ext>` for single export', () {
      final name = suggestedName(
        ExportFormat.png,
        at: DateTime(2026, 5, 14, 9, 8, 7),
      );
      expect(name, 'flpicraft_20260514_090807.png');
    });

    test('appends `_<index>` suffix for grid cells', () {
      final name = suggestedName(
        ExportFormat.jpg,
        at: DateTime(2026, 5, 14, 9, 8, 7),
        index: 5,
      );
      expect(name, 'flpicraft_20260514_090807_5.jpg');
    });

    test('uses the format extension', () {
      final pngName = suggestedName(ExportFormat.png, at: DateTime(2026, 1, 1));
      final jpgName = suggestedName(ExportFormat.jpg, at: DateTime(2026, 1, 1));
      expect(pngName.endsWith('.png'), isTrue);
      expect(jpgName.endsWith('.jpg'), isTrue);
    });

    test('zero-pads single-digit date / time fields', () {
      final name = suggestedName(
        ExportFormat.png,
        at: DateTime(2026, 1, 2, 3, 4, 5),
      );
      expect(name, 'flpicraft_20260102_030405.png');
    });

    test('default `at` falls back to DateTime.now()', () {
      final before = DateTime.now();
      final name = suggestedName(ExportFormat.png);
      final after = DateTime.now();
      // Sanity-check the name matches the expected shape; the
      // generated timestamp must fall within the [before, after]
      // window.
      expect(
        RegExp(r'^flpicraft_\d{8}_\d{6}\.png$').hasMatch(name),
        isTrue,
        reason: 'Expected timestamped filename, got "$name"',
      );
      final stampStr = name.substring(
        'flpicraft_'.length,
        name.length - '.png'.length,
      );
      final parsed = DateTime(
        int.parse(stampStr.substring(0, 4)),
        int.parse(stampStr.substring(4, 6)),
        int.parse(stampStr.substring(6, 8)),
        int.parse(stampStr.substring(9, 11)),
        int.parse(stampStr.substring(11, 13)),
        int.parse(stampStr.substring(13, 15)),
      );
      // Allow a 1s wiggle since DateTime.now() may tick mid-call.
      expect(
        parsed.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(parsed.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('suggestedZipName', () {
    test('builds `flpicraft_<timestamp>.zip` outer download name', () {
      final name = suggestedZipName(at: DateTime(2026, 5, 21, 12, 6, 7));
      expect(name, 'flpicraft_20260521_120607.zip');
    });

    test('zero-pads single-digit fields and ends with `.zip`', () {
      final name = suggestedZipName(at: DateTime(2026, 1, 2, 3, 4, 5));
      expect(name, 'flpicraft_20260102_030405.zip');
    });

    test('default `at` falls back to DateTime.now()', () {
      final name = suggestedZipName();
      expect(
        RegExp(r'^flpicraft_\d{8}_\d{6}\.zip$').hasMatch(name),
        isTrue,
        reason: 'Expected timestamped zip name, got "$name"',
      );
    });
  });

  group('suggestedZipFolderName', () {
    test(
      'builds `flpicraft_<timestamp>` inner folder name (no trailing slash)',
      () {
        final folder = suggestedZipFolderName(
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );
        expect(folder, 'flpicraft_20260521_120607');
        expect(folder.endsWith('/'), isFalse);
      },
    );

    test('shares the same timestamp formatting as suggestedZipName', () {
      final at = DateTime(2026, 5, 21, 12, 6, 7);
      final outer = suggestedZipName(at: at);
      final folder = suggestedZipFolderName(at: at);
      // outer is `<folder>.zip` — same stem.
      expect(outer, '$folder.zip');
    });
  });
}
