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
          final layout = computeGridLayout(cellSide: 100, type: entry.key);
          expect(layout.cellCount, entry.value);
          expect(layout.rows, entry.key.rows);
          expect(layout.cols, entry.key.cols);
        });
      }
    },
  );

  group('computeGridLayout — every cell is a square of side cellSide', () {
    test('3x3 with cellSide=100 yields nine 100x100 cells (no spacing)', () {
      final layout = computeGridLayout(cellSide: 100, type: GridType.g3x3);
      expect(layout.rects, hasLength(9));
      for (final rect in layout.rects) {
        expect(rect.width, 100);
        expect(rect.height, 100);
        expect(rect.width, rect.height);
      }
      // Spot-check positions in row-major order.
      expect(layout.rects[0].x, 0);
      expect(layout.rects[0].y, 0);
      expect(layout.rects[1].x, 100);
      expect(layout.rects[1].y, 0);
      expect(layout.rects[3].x, 0);
      expect(layout.rects[3].y, 100);
      expect(layout.rects[8].x, 200);
      expect(layout.rects[8].y, 200);
    });

    test('2x3 (rows=2, cols=3) lays out 6 equal squares', () {
      final layout = computeGridLayout(cellSide: 60, type: GridType.g2x3);
      expect(layout.rects, hasLength(6));
      for (final rect in layout.rects) {
        expect(rect.width, 60);
        expect(rect.height, 60);
      }
      // Row 0: 3 cells at y=0 with x = 0, 60, 120.
      expect(layout.rects[0].x, 0);
      expect(layout.rects[1].x, 60);
      expect(layout.rects[2].x, 120);
      // Row 1: 3 cells at y=60 with x = 0, 60, 120.
      expect(layout.rects[3].x, 0);
      expect(layout.rects[3].y, 60);
      expect(layout.rects[5].x, 120);
      expect(layout.rects[5].y, 60);
    });

    test('1x2 has two cells side by side (row=0)', () {
      final layout = computeGridLayout(cellSide: 80, type: GridType.g1x2);
      expect(layout.rects, hasLength(2));
      expect(layout.rects[0].x, 0);
      expect(layout.rects[0].y, 0);
      expect(layout.rects[1].x, 80);
      expect(layout.rects[1].y, 0);
      for (final rect in layout.rects) {
        expect(rect.width, 80);
        expect(rect.height, 80);
      }
    });
  });

  group('computeGridLayout — spacing inserts gaps but keeps cells square', () {
    test('3x3 spacing=10 leaves 10 px gutters between rows / cols', () {
      final layout = computeGridLayout(
        cellSide: 100,
        type: GridType.g3x3,
        spacing: 10,
      );
      expect(layout.rects, hasLength(9));
      // First col x = 0; second col x = 100 + 10 = 110; third col x = 220.
      expect(layout.rects[0].x, 0);
      expect(layout.rects[1].x, 110);
      expect(layout.rects[2].x, 220);
      // Same on the y axis.
      expect(layout.rects[3].y, 110);
      expect(layout.rects[6].y, 220);
      // Cells stay square regardless of spacing.
      for (final rect in layout.rects) {
        expect(rect.width, 100);
        expect(rect.height, 100);
      }
    });

    test('2x3 spacing=5 keeps every cell at the cellSide', () {
      final layout = computeGridLayout(
        cellSide: 50,
        type: GridType.g2x3,
        spacing: 5,
      );
      expect(layout.rects[0].x, 0);
      expect(layout.rects[1].x, 55);
      expect(layout.rects[2].x, 110);
      expect(layout.rects[3].y, 55);
      for (final rect in layout.rects) {
        expect(rect.width, 50);
        expect(rect.height, 50);
      }
    });
  });

  group('computeGridLayout — degenerate inputs', () {
    test('cellSide <= 0 collapses every cell to 0 area', () {
      final layout = computeGridLayout(cellSide: 0, type: GridType.g3x3);
      expect(layout.cellCount, 9);
      for (final rect in layout.rects) {
        expect(rect.width, 0);
        expect(rect.height, 0);
      }
    });

    test('negative cellSide is treated as zero', () {
      final layout = computeGridLayout(cellSide: -10, type: GridType.g2x2);
      for (final rect in layout.rects) {
        expect(rect.width, 0);
        expect(rect.height, 0);
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
      expect(kGridTypeSelectorOrder.toSet().length, 5);
      expect(kGridTypeSelectorOrder.toSet(), GridType.values.toSet());
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
