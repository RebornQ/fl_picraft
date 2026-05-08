import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImportedImage', () {
    test('value equality treats identical fields as equal', () {
      final a = ImportedImage(
        sourcePath: '/tmp/a.png',
        bytes: Uint8List.fromList(const [1, 2, 3, 4]),
        width: 16,
        height: 9,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 1, 1),
      );
      final b = ImportedImage(
        sourcePath: '/tmp/a.png',
        bytes: Uint8List.fromList(const [1, 2, 3, 4]),
        width: 16,
        height: 9,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 1, 1),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality treats different bytes as not equal', () {
      final base = ImportedImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        width: 1,
        height: 1,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 1, 1),
      );
      final differentBytes = ImportedImage(
        bytes: Uint8List.fromList(const [1, 2, 4]),
        width: 1,
        height: 1,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 1, 1),
      );

      expect(base, isNot(equals(differentBytes)));
    });

    test('copyWith preserves all unspecified fields', () {
      final original = ImportedImage(
        sourcePath: '/tmp/orig.png',
        bytes: Uint8List.fromList(const [1, 2, 3]),
        width: 100,
        height: 200,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 5, 9),
      );

      final updated = original.copyWith(width: 50);

      expect(updated.width, 50);
      expect(updated.height, original.height);
      expect(updated.bytes, original.bytes);
      expect(updated.sourcePath, original.sourcePath);
      expect(updated.mimeType, original.mimeType);
      expect(updated.importedAt, original.importedAt);
    });

    test('toString includes byte length, dimensions, and mime', () {
      final image = ImportedImage(
        bytes: Uint8List(42),
        width: 8,
        height: 6,
        mimeType: 'image/png',
        importedAt: DateTime.utc(2026, 1, 1),
      );

      final s = image.toString();
      expect(s, contains('42B'));
      expect(s, contains('8x6'));
      expect(s, contains('image/png'));
    });
  });
}
