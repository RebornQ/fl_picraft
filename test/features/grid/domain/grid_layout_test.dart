import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'computeGridLayout — cell count matches GridType for all 5 variants',
    () {
      const expectedCells = <GridType, int>{
        GridType.g1x2: 2,
        GridType.g1x3: 3,
        GridType.g2x2: 4,
        GridType.g2x3: 6,
        GridType.g3x3: 9,
      };

      for (final entry in expectedCells.entries) {
        test('${entry.key.displayLabel} produces ${entry.value} cells', () {
          final layout = computeGridLayout(
            sourceWidth: 1200,
            sourceHeight: 1200,
            type: entry.key,
          );
          expect(layout.cellCount, entry.value);
          expect(layout.rows, entry.key.rows);
          expect(layout.cols, entry.key.cols);
        });
      }
    },
  );

  group('computeGridLayout — even divisions (no residual)', () {
    test('3x3 over 300x300 with no spacing yields 100x100 cells', () {
      final layout = computeGridLayout(
        sourceWidth: 300,
        sourceHeight: 300,
        type: GridType.g3x3,
      );
      expect(layout.rects, hasLength(9));
      for (final rect in layout.rects) {
        expect(rect.width, 100);
        expect(rect.height, 100);
      }
      // Spot-check positions: row-major order.
      expect(layout.rects[0].x, 0);
      expect(layout.rects[0].y, 0);
      expect(layout.rects[1].x, 100);
      expect(layout.rects[1].y, 0);
      expect(layout.rects[3].x, 0);
      expect(layout.rects[3].y, 100);
      expect(layout.rects[8].x, 200);
      expect(layout.rects[8].y, 200);
    });

    test('2x2 over 200x100 yields 100x50 cells in row-major order', () {
      final layout = computeGridLayout(
        sourceWidth: 200,
        sourceHeight: 100,
        type: GridType.g2x2,
      );
      expect(layout.rects, hasLength(4));
      expect(layout.rects[0].x, 0);
      expect(layout.rects[0].y, 0);
      expect(layout.rects[0].width, 100);
      expect(layout.rects[0].height, 50);
      expect(layout.rects[1].x, 100);
      expect(layout.rects[1].y, 0);
      expect(layout.rects[2].x, 0);
      expect(layout.rects[2].y, 50);
      expect(layout.rects[3].x, 100);
      expect(layout.rects[3].y, 50);
    });
  });

  group('computeGridLayout — spacing inserts gaps', () {
    test('3x3 spacing=10 yields cells with 10px gutters', () {
      // (300 - 2*10) / 3 = 93 each (integer divide). residual = 300 - 20 - 93*3
      // = 300 - 20 - 279 = 1 px → distributed to last col / last row.
      final layout = computeGridLayout(
        sourceWidth: 300,
        sourceHeight: 300,
        type: GridType.g3x3,
        spacing: 10,
      );
      // First col x = 0; second col x = 93 + 10 = 103; third col x = 103 + 93 + 10 = 206.
      expect(layout.rects[0].x, 0);
      expect(layout.rects[1].x, 103);
      expect(layout.rects[2].x, 206);
      // Last column gets the residual pixel (1 px).
      expect(layout.rects[2].width, 94);
      expect(layout.rects[1].width, 93);
      expect(layout.rects[0].width, 93);
    });
  });

  group('computeGridLayout — residual pixel distribution', () {
    test('non-divisible width sends residual to the last column', () {
      // 301 width, 3 cols, no spacing.
      // baseCellW = 301 ~/ 3 = 100, residualW = 1.
      // → cols: 100, 100, 101.
      final layout = computeGridLayout(
        sourceWidth: 301,
        sourceHeight: 300,
        type: GridType.g3x3,
      );
      expect(layout.rects[0].width, 100);
      expect(layout.rects[1].width, 100);
      expect(layout.rects[2].width, 101);
      // Row 1 still uses 100/100/101 widths.
      expect(layout.rects[3].width, 100);
      expect(layout.rects[5].width, 101);
    });

    test('non-divisible height sends residual to the last row', () {
      // 300 width, 302 height, 3 rows.
      // baseCellH = 302 ~/ 3 = 100, residualH = 2.
      // → rows: 100, 100, 102.
      final layout = computeGridLayout(
        sourceWidth: 300,
        sourceHeight: 302,
        type: GridType.g3x3,
      );
      expect(layout.rects[0].height, 100); // row 0
      expect(layout.rects[3].height, 100); // row 1
      expect(layout.rects[6].height, 102); // row 2 (last)
    });

    test('residual on both axes lands on bottom-right cell only', () {
      // 305 x 307, 3x3 → cols 101/101/103, rows 102/102/103.
      final layout = computeGridLayout(
        sourceWidth: 305,
        sourceHeight: 307,
        type: GridType.g3x3,
      );
      // baseCellW = 305 ~/ 3 = 101, residual = 305 - 303 = 2 → last col = 103.
      expect(layout.rects[0].width, 101);
      expect(layout.rects[1].width, 101);
      expect(layout.rects[2].width, 103);
      // baseCellH = 307 ~/ 3 = 102, residual = 307 - 306 = 1 → last row = 103.
      expect(layout.rects[6].height, 103);
      expect(layout.rects[3].height, 102);
    });

    test('layout covers every source pixel exactly (no gap, no overlap)', () {
      // Use an awkward source size that triggers residual distribution.
      final layout = computeGridLayout(
        sourceWidth: 1001,
        sourceHeight: 503,
        type: GridType.g3x3,
      );
      var totalW = 0;
      for (var c = 0; c < layout.cols; c++) {
        totalW += layout.rects[c].width;
      }
      expect(totalW, 1001);

      var totalH = 0;
      for (var r = 0; r < layout.rows; r++) {
        totalH += layout.rects[r * layout.cols].height;
      }
      expect(totalH, 503);
    });
  });

  group('computeGridLayout — degenerate sources', () {
    test('zero-sized source returns zero-sized rects', () {
      final layout = computeGridLayout(
        sourceWidth: 0,
        sourceHeight: 0,
        type: GridType.g3x3,
      );
      expect(layout.cellCount, 9);
      for (final r in layout.rects) {
        expect(r.width, 0);
        expect(r.height, 0);
      }
    });

    test('spacing larger than source clamps cells to zero', () {
      final layout = computeGridLayout(
        sourceWidth: 10,
        sourceHeight: 10,
        type: GridType.g3x3,
        spacing: 50,
      );
      // Every cell should be zero-width (spacing eats the whole axis).
      for (final r in layout.rects) {
        expect(r.width, 0);
        expect(r.height, 0);
      }
    });
  });

  group('GridTypeInfo', () {
    test('exposes correct rows/cols for every variant', () {
      expect(GridType.g1x2.rows, 1);
      expect(GridType.g1x2.cols, 2);
      expect(GridType.g2x3.rows, 2);
      expect(GridType.g2x3.cols, 3);
      expect(GridType.g3x3.rows, 3);
      expect(GridType.g3x3.cols, 3);
    });

    test('display label uses RxC notation', () {
      expect(GridType.g1x2.displayLabel, '1x2');
      expect(GridType.g3x3.displayLabel, '3x3');
      expect(GridType.g2x3.displayLabel, '2x3');
    });

    test('cellCount returns rows * cols', () {
      expect(GridType.g1x2.cellCount, 2);
      expect(GridType.g3x3.cellCount, 9);
      expect(GridType.g2x3.cellCount, 6);
    });

    test('displayTitle / displayDescription match the PRD 05-17 文案表', () {
      expect(GridType.g1x2.displayTitle, '二宫格');
      expect(GridType.g1x2.displayDescription, '横向两格，左右对照');
      expect(GridType.g1x3.displayTitle, '三宫格');
      expect(GridType.g1x3.displayDescription, '横向三格，长卷分屏');
      expect(GridType.g2x2.displayTitle, '四宫格');
      expect(GridType.g2x2.displayDescription, '方正四格，万能切片');
      expect(GridType.g2x3.displayTitle, '六宫格');
      expect(GridType.g2x3.displayDescription, '横向六格，时间轴友好');
      expect(GridType.g3x3.displayTitle, '九宫格');
      expect(GridType.g3x3.displayDescription, '朋友圈经典');
    });

    test('kGridTypeSelectorOrder lists exactly the 5 PRD 05-17 variants', () {
      expect(kGridTypeSelectorOrder, hasLength(5));
      // No duplicates.
      expect(kGridTypeSelectorOrder.toSet().length, 5);
      // Covers every enum value.
      expect(kGridTypeSelectorOrder.toSet(), GridType.values.toSet());
      // Order matches PRD R1.
      expect(kGridTypeSelectorOrder, <GridType>[
        GridType.g1x2,
        GridType.g1x3,
        GridType.g2x2,
        GridType.g2x3,
        GridType.g3x3,
      ]);
    });
  });
}
