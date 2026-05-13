import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/usecases/compute_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Canvas 200x100, text 40x10, margin 16.
  const canvasW = 200;
  const canvasH = 100;
  const textW = 40;
  const textH = 10;
  const margin = 16;

  group('computeAnchor', () {
    test('topLeft anchors at (margin, margin)', () {
      final pos = computeAnchor(
        WatermarkAnchor.topLeft,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, margin);
      expect(pos.y, margin);
    });

    test('topCenter centers horizontally, top edge respects margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.topCenter,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, ((canvasW - textW) / 2).round()); // 80
      expect(pos.y, margin);
    });

    test('topRight aligns text right edge with canvas right edge − margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.topRight,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, canvasW - textW - margin); // 144
      expect(pos.y, margin);
    });

    test('middleLeft centers vertically, left edge respects margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.middleLeft,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, margin);
      expect(pos.y, ((canvasH - textH) / 2).round()); // 45
    });

    test('middleCenter centers on both axes', () {
      final pos = computeAnchor(
        WatermarkAnchor.middleCenter,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, ((canvasW - textW) / 2).round()); // 80
      expect(pos.y, ((canvasH - textH) / 2).round()); // 45
    });

    test('middleRight centers vertically, right edge respects margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.middleRight,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, canvasW - textW - margin); // 144
      expect(pos.y, ((canvasH - textH) / 2).round());
    });

    test('bottomLeft anchors at left+margin, bottom−textH−margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.bottomLeft,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, margin);
      expect(pos.y, canvasH - textH - margin); // 74
    });

    test('bottomCenter centers horizontally, bottom edge respects margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.bottomCenter,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, ((canvasW - textW) / 2).round());
      expect(pos.y, canvasH - textH - margin);
    });

    test('bottomRight anchors at right−textW−margin, bottom−textH−margin', () {
      final pos = computeAnchor(
        WatermarkAnchor.bottomRight,
        canvasW,
        canvasH,
        textW,
        textH,
        margin: margin,
      );
      expect(pos.x, canvasW - textW - margin);
      expect(pos.y, canvasH - textH - margin);
    });

    test('default margin matches PRD-spec 16px', () {
      final pos = computeAnchor(
        WatermarkAnchor.topLeft,
        canvasW,
        canvasH,
        textW,
        textH,
      );
      expect(pos.x, kDefaultWatermarkMargin);
      expect(pos.y, kDefaultWatermarkMargin);
      expect(kDefaultWatermarkMargin, 16);
    });
  });

  group('WatermarkAnchor row/column', () {
    test('row indices group anchors by vertical band', () {
      expect(WatermarkAnchor.topLeft.row, 0);
      expect(WatermarkAnchor.topRight.row, 0);
      expect(WatermarkAnchor.middleCenter.row, 1);
      expect(WatermarkAnchor.bottomRight.row, 2);
    });

    test('column indices group anchors by horizontal band', () {
      expect(WatermarkAnchor.topLeft.column, 0);
      expect(WatermarkAnchor.middleLeft.column, 0);
      expect(WatermarkAnchor.topCenter.column, 1);
      expect(WatermarkAnchor.bottomRight.column, 2);
    });
  });
}
