import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/image_encoder.dart';
import 'package:fl_picraft/features/export/data/preview_renderer.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Contract tests for [processExportBytes].
///
/// The function is the public renaming of the legacy `_processOneInIsolate`
/// — its contract is that the produced bytes are byte-identical to the
/// composition of `applyWatermark` + `encodeForExport`.
///
/// We don't drive the isolate path here (`compute` falls through to a
/// synchronous run in test environments where the Flutter binding's
/// isolate manager is unavailable). The `export_repository_impl_test`
/// already covers the compute-hop end-to-end.
void main() {
  Uint8List solidPng({int w = 40, int h = 30, int r = 220}) {
    final canvas = img.Image(width: w, height: h);
    img.fill(canvas, color: img.ColorRgb8(r, 40, 40));
    return Uint8List.fromList(img.encodePng(canvas));
  }

  group('processExportBytes — watermark disabled', () {
    test(
      'PNG output matches encodeForExport directly when watermark off',
      () async {
        final src = solidPng();
        final wm = WatermarkConfig.initial(); // enabled=false
        final actual = await processExportBytes(
          source: src,
          watermark: wm,
          format: ExportFormat.png,
          quality: 90,
        );
        final expected = encodeForExport(src, ExportFormat.png, quality: 90);
        expect(actual, equals(expected));
      },
    );

    test(
      'JPG output matches encodeForExport directly when watermark off',
      () async {
        final src = solidPng();
        final wm = WatermarkConfig.initial();
        final actual = await processExportBytes(
          source: src,
          watermark: wm,
          format: ExportFormat.jpg,
          quality: 75,
        );
        final expected = encodeForExport(src, ExportFormat.jpg, quality: 75);
        expect(actual, equals(expected));
      },
    );
  });

  group('processExportBytes — watermark enabled', () {
    test(
      'JPG with watermark: output is valid JPG of source dimensions',
      () async {
        final src = solidPng(w: 200, h: 150);
        final wm = WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Hi',
          anchor: WatermarkAnchor.bottomRight,
        );
        final out = await processExportBytes(
          source: src,
          watermark: wm,
          format: ExportFormat.jpg,
          quality: 85,
        );
        final decoded = img.decodeImage(out);
        expect(decoded, isNotNull);
        expect(decoded!.width, 200);
        expect(decoded.height, 150);
        // JPG magic bytes: 0xFF 0xD8 0xFF
        expect(out[0], 0xFF);
        expect(out[1], 0xD8);
        expect(out[2], 0xFF);
      },
    );

    test('PNG with watermark: differs from no-watermark byte stream', () async {
      final src = solidPng(w: 200, h: 150);
      final wmOn = WatermarkConfig.initial().copyWith(
        enabled: true,
        text: 'Hi',
      );
      final wmOff = WatermarkConfig.initial(); // enabled=false
      final withMark = await processExportBytes(
        source: src,
        watermark: wmOn,
        format: ExportFormat.png,
        quality: 100,
      );
      final withoutMark = await processExportBytes(
        source: src,
        watermark: wmOff,
        format: ExportFormat.png,
        quality: 100,
      );
      expect(
        withMark,
        isNot(equals(withoutMark)),
        reason: 'watermark should produce a different PNG byte stream',
      );
    });

    test(
      'identical inputs produce byte-identical outputs (deterministic)',
      () async {
        final src = solidPng();
        final wm = WatermarkConfig.initial().copyWith(
          enabled: true,
          text: 'Hi',
        );
        final a = await processExportBytes(
          source: src,
          watermark: wm,
          format: ExportFormat.png,
          quality: 90,
        );
        final b = await processExportBytes(
          source: src,
          watermark: wm,
          format: ExportFormat.png,
          quality: 90,
        );
        expect(a, equals(b));
      },
    );
  });
}
