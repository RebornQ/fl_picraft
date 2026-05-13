import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportFormat', () {
    test('exposes file extension + MIME type for each variant', () {
      expect(ExportFormat.png.extension, 'png');
      expect(ExportFormat.png.mimeType, 'image/png');
      expect(ExportFormat.jpg.extension, 'jpg');
      expect(ExportFormat.jpg.mimeType, 'image/jpeg');
    });

    test('supportsQuality is true for JPG only', () {
      expect(ExportFormat.png.supportsQuality, isFalse);
      expect(ExportFormat.jpg.supportsQuality, isTrue);
    });

    test('label matches the mockup copy', () {
      expect(ExportFormat.png.label, 'PNG');
      expect(ExportFormat.jpg.label, 'JPG');
    });
  });

  group('clampExportQuality', () {
    test('passes through values inside [1, 100]', () {
      expect(clampExportQuality(1), 1);
      expect(clampExportQuality(50), 50);
      expect(clampExportQuality(100), 100);
    });

    test('clamps below 1 to 1', () {
      expect(clampExportQuality(0), 1);
      expect(clampExportQuality(-25), 1);
    });

    test('clamps above 100 to 100', () {
      expect(clampExportQuality(101), 100);
      expect(clampExportQuality(9999), 100);
    });
  });
}
