import 'package:fl_picraft/features/grid/domain/usecases/compute_cell_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coverScaleFactor', () {
    test('returns 1.0 for equal image and cell dimensions', () {
      final cover = coverScaleFactor(
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(cover, 1);
    });

    test('returns the larger axis ratio when image smaller than cell', () {
      // 100x100 image on 300x300 cell → need to upscale 3x on both axes.
      final cover = coverScaleFactor(
        imageWidth: 100,
        imageHeight: 100,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(cover, 3);
    });

    test('uses the wider-axis ratio when aspect ratios differ', () {
      // 200x100 image on 300x300 cell → height needs 3x, width needs 1.5x.
      // We must cover both, so pick the larger (3x for height).
      final cover = coverScaleFactor(
        imageWidth: 200,
        imageHeight: 100,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(cover, 3);
    });

    test('returns sub-1.0 for image larger than cell', () {
      // 1000x1000 image on 500x500 cell → downscale to 0.5x.
      final cover = coverScaleFactor(
        imageWidth: 1000,
        imageHeight: 1000,
        cellWidth: 500,
        cellHeight: 500,
      );
      expect(cover, 0.5);
    });

    test('returns 1.0 for any zero or negative dimension', () {
      expect(
        coverScaleFactor(
          imageWidth: 0,
          imageHeight: 100,
          cellWidth: 100,
          cellHeight: 100,
        ),
        1,
      );
      expect(
        coverScaleFactor(
          imageWidth: 100,
          imageHeight: 100,
          cellWidth: 0,
          cellHeight: 100,
        ),
        1,
      );
    });
  });

  group('clampUserScale', () {
    test('clamps below cover-fit to 1.0 (PRD edge case)', () {
      expect(clampUserScale(0.5), 1);
      expect(clampUserScale(0.0), 1);
      expect(clampUserScale(-1), 1);
    });

    test('preserves values inside [1.0, 2.0]', () {
      expect(clampUserScale(1.0), 1.0);
      expect(clampUserScale(1.5), 1.5);
      expect(clampUserScale(2.0), 2.0);
    });

    test('clamps above 2.0 to 2.0 (PRD ceiling)', () {
      expect(clampUserScale(2.5), 2);
      expect(clampUserScale(10), 2);
    });
  });

  group('clampCellOffset', () {
    test('pins offset to (0,0) when scaled image equals cell on both axes', () {
      // userScale=1.0 + same dims = no surplus = no allowed pan.
      final clamped = clampCellOffset(
        offset: const CellOffset(50, 50),
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 1,
      );
      expect(clamped.dx, 0);
      expect(clamped.dy, 0);
    });

    test(
      'allows offset within half-surplus when scaled image exceeds cell',
      () {
        // 300x300 image, 300x300 cell, userScale=2.0 → effective extent
        // 600x600, surplus 300, half-surplus 150 on each axis.
        final clamped = clampCellOffset(
          offset: const CellOffset(100, -50),
          imageWidth: 300,
          imageHeight: 300,
          cellWidth: 300,
          cellHeight: 300,
          userScale: 2,
        );
        expect(clamped.dx, 100);
        expect(clamped.dy, -50);
      },
    );

    test('clamps overshoot back to ±half-surplus', () {
      // Same setup as above; offset 200 exceeds half-surplus 150.
      final clamped = clampCellOffset(
        offset: const CellOffset(200, -200),
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 2,
      );
      expect(clamped.dx, 150);
      expect(clamped.dy, -150);
    });

    test('asymmetric scaled-image surplus clamps per-axis independently', () {
      // 100x300 image → cover for 300x300 cell is 3.0 (width-limited).
      // At userScale=1.0 effective extent is 300x900 — y surplus 600,
      // half-surplus 300; x surplus 0, half-surplus 0.
      final clamped = clampCellOffset(
        offset: const CellOffset(50, 200),
        imageWidth: 100,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 1,
      );
      expect(clamped.dx, 0, reason: 'no x surplus → pinned to 0');
      expect(clamped.dy, 200, reason: 'y has 300 of allowed offset');
    });

    test('zero/negative dims short-circuit to (0, 0)', () {
      expect(
        clampCellOffset(
          offset: const CellOffset(100, 100),
          imageWidth: 0,
          imageHeight: 100,
          cellWidth: 100,
          cellHeight: 100,
          userScale: 1,
        ),
        kCellOffsetZero,
      );
    });
  });

  group('clampCellTransform', () {
    test('applies scale clamp before offset clamp', () {
      // userScale=0.5 → clamped to 1.0 cover-fit. Offset 100 with
      // 300x300/300x300/1.0 = 0 surplus → pinned to 0.
      final clamped = clampCellTransform(
        scale: 0.5,
        offset: const CellOffset(100, 100),
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(clamped.scale, 1);
      expect(clamped.offset.dx, 0);
      expect(clamped.offset.dy, 0);
    });

    test('preserves valid (scale, offset) pairs unchanged', () {
      const input = CellOffset(50, -25);
      final clamped = clampCellTransform(
        scale: 1.5,
        offset: input,
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(clamped.scale, 1.5);
      // At scale 1.5 effective extent 450, surplus 150, half 75 — 50/-25 inside.
      expect(clamped.offset.dx, 50);
      expect(clamped.offset.dy, -25);
    });

    test('over-zoomed scale clamps to 2.0 ceiling', () {
      final clamped = clampCellTransform(
        scale: 5,
        offset: const CellOffset(1000, 0),
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
      );
      expect(clamped.scale, 2);
      // At scale 2 effective extent 600, surplus 300, half-surplus 150.
      // 1000 → clamps to 150.
      expect(clamped.offset.dx, 150);
    });
  });

  group('computeCellSourceRect', () {
    test('cover-fit (scale=1) on aspect-matching image picks full image', () {
      final rect = computeCellSourceRect(
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 1,
        offset: kCellOffsetZero,
      );
      expect(rect, isNotNull);
      expect(rect!.x, 0);
      expect(rect.y, 0);
      expect(rect.width, 300);
      expect(rect.height, 300);
    });

    test('zoom-in (scale=2) on cover-fit image crops the center half', () {
      // userScale=2 → effective=2 → slice = cell / 2 → 150x150 from center.
      final rect = computeCellSourceRect(
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 2,
        offset: kCellOffsetZero,
      );
      expect(rect, isNotNull);
      expect(rect!.x, 75);
      expect(rect.y, 75);
      expect(rect.width, 150);
      expect(rect.height, 150);
    });

    test('non-zero offset shifts the slice in source coords', () {
      // userScale=2, offset.dx=30 → source shift = -30 / 2 = -15.
      // Slice center moves 15 to the left, so x = 75 - 15 = 60.
      final rect = computeCellSourceRect(
        imageWidth: 300,
        imageHeight: 300,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 2,
        offset: const CellOffset(30, 0),
      );
      expect(rect, isNotNull);
      expect(rect!.x, 60);
      expect(rect.y, 75);
      expect(rect.width, 150);
      expect(rect.height, 150);
    });

    test('image with different aspect ratio still produces square slice', () {
      // 200x100 image, 300x300 cell, scale=1 → cover=3.0, effective=3.0.
      // sliceW = 300 / 3 = 100. Image width is 200 — slice spans the
      // middle 100 horizontally (50..150). Vertically image height is
      // 100, slice height = 300 / 3 = 100 — full image height.
      final rect = computeCellSourceRect(
        imageWidth: 200,
        imageHeight: 100,
        cellWidth: 300,
        cellHeight: 300,
        userScale: 1,
        offset: kCellOffsetZero,
      );
      expect(rect, isNotNull);
      expect(rect!.x, 50);
      expect(rect.y, 0);
      expect(rect.width, 100);
      expect(rect.height, 100);
    });

    test('returns null on degenerate inputs', () {
      expect(
        computeCellSourceRect(
          imageWidth: 0,
          imageHeight: 100,
          cellWidth: 100,
          cellHeight: 100,
          userScale: 1,
          offset: kCellOffsetZero,
        ),
        isNull,
      );
      expect(
        computeCellSourceRect(
          imageWidth: 100,
          imageHeight: 100,
          cellWidth: 100,
          cellHeight: 100,
          userScale: 0,
          offset: kCellOffsetZero,
        ),
        isNull,
      );
    });
  });

  group('CellOffset value semantics', () {
    test('equality and hashCode follow value semantics', () {
      const a = CellOffset(1, 2);
      const b = CellOffset(1, 2);
      const c = CellOffset(3, 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith preserves unspecified axis', () {
      const a = CellOffset(10, 20);
      expect(a.copyWith(dx: 50), const CellOffset(50, 20));
      expect(a.copyWith(dy: -5), const CellOffset(10, -5));
    });
  });

  group('ClampedCellTransform', () {
    test('equality covers both scale and offset', () {
      const a = ClampedCellTransform(scale: 1.5, offset: CellOffset(10, 20));
      const b = ClampedCellTransform(scale: 1.5, offset: CellOffset(10, 20));
      const c = ClampedCellTransform(scale: 1.5, offset: CellOffset(11, 20));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
