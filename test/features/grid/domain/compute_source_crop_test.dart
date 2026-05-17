import 'package:fl_picraft/features/grid/domain/usecases/compute_source_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSourceCropRect — cover-fit (scale=1, offset=(0.5,0.5))', () {
    test('square source @ targetAspect=1 returns the full image', () {
      final rect = computeSourceCropRect(
        sourceWidth: 300,
        sourceHeight: 300,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.x, 0);
      expect(rect.y, 0);
      expect(rect.width, 300);
      expect(rect.height, 300);
    });

    test('landscape source @ targetAspect=1 returns centered square', () {
      final rect = computeSourceCropRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 300);
      expect(rect.height, 300);
      // Center of 300x300 inside 600x300 → x=(600-300)/2=150.
      expect(rect.x, 150);
      expect(rect.y, 0);
    });

    test('portrait source @ targetAspect=1 returns centered square', () {
      final rect = computeSourceCropRect(
        sourceWidth: 300,
        sourceHeight: 600,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 300);
      expect(rect.height, 300);
      expect(rect.x, 0);
      expect(rect.y, 150);
    });
  });

  group('computeSourceCropRect — targetAspect != 1', () {
    test(
      'square source @ targetAspect=2 (1×2 grid) returns full-width strip',
      () {
        // sourceAspect = 1, targetAspect = 2 → source is "taller" relative
        // to target → width-bound. baseW=300, baseH=150.
        final rect = computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 1.0,
          targetAspect: 2.0,
        );
        expect(rect, isNotNull);
        expect(rect!.width, 300);
        expect(rect.height, 150);
        // Centered vertically.
        expect(rect.x, 0);
        expect(rect.y, 75);
      },
    );

    test(
      'landscape 600x300 @ targetAspect=3 (1×3 grid) returns full width',
      () {
        // sourceAspect = 2, targetAspect = 3 → source is taller → width-bound.
        // baseW = 600, baseH = 200.
        final rect = computeSourceCropRect(
          sourceWidth: 600,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 1.0,
          targetAspect: 3.0,
        );
        expect(rect, isNotNull);
        expect(rect!.width, 600);
        expect(rect.height, 200);
        expect(rect.x, 0);
        expect(rect.y, 50);
      },
    );

    test('landscape 600x300 @ targetAspect=1.5 (2×3 grid) returns 450x300', () {
      // sourceAspect = 2, targetAspect = 1.5 → sourceAspect >= target →
      // height-bound. baseH = 300, baseW = 300 * 1.5 = 450.
      final rect = computeSourceCropRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: kDefaultSourceOffset,
        scale: 1.0,
        targetAspect: 1.5,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 450);
      expect(rect.height, 300);
      // Center crop horizontally: x = (600-450)/2 = 75.
      expect(rect.x, 75);
      expect(rect.y, 0);
    });
  });

  group('computeSourceCropRect — scale > 1 shrinks the rect', () {
    test('scale=2 on 400x400 @ aspect=1 → 200x200 from center', () {
      final rect = computeSourceCropRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 2.0,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 200);
      expect(rect.height, 200);
      expect(rect.x, 100);
      expect(rect.y, 100);
    });

    test('scale=2 on 400x400 @ aspect=2 → 200x100 from center', () {
      final rect = computeSourceCropRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 2.0,
        targetAspect: 2.0,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 200);
      expect(rect.height, 100);
      // Centered.
      expect(rect.x, 100);
      expect(rect.y, 150);
    });

    test('scale clamped above 4.0', () {
      final rect = computeSourceCropRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 10.0,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 100);
      expect(rect.height, 100);
    });

    test('scale clamped below 1.0', () {
      final rect = computeSourceCropRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 0.5,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 400);
      expect(rect.height, 400);
    });
  });

  group('computeSourceCropRect — offset shifts the crop', () {
    test('landscape 600x300 + offset.dx=0 (left-most) → x=0', () {
      final rect = computeSourceCropRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: const SourceOffset(0, 0.5),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 300);
      expect(rect.x, 0);
      expect(rect.y, 0);
    });

    test('landscape 600x300 + offset.dx=1.0 (right-most) → x=300', () {
      final rect = computeSourceCropRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: const SourceOffset(1.0, 0.5),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.width, 300);
      expect(rect.x, 300);
      expect(rect.y, 0);
    });
  });

  group('computeSourceCropRect — degenerate inputs', () {
    test('zero width returns null', () {
      expect(
        computeSourceCropRect(
          sourceWidth: 0,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 1.0,
        ),
        isNull,
      );
    });

    test('zero height returns null', () {
      expect(
        computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 0,
          offset: kDefaultSourceOffset,
          scale: 1.0,
        ),
        isNull,
      );
    });

    test('zero scale returns null', () {
      expect(
        computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 0,
        ),
        isNull,
      );
    });

    test('NaN scale returns null', () {
      expect(
        computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: double.nan,
        ),
        isNull,
      );
    });

    test('zero / negative targetAspect returns null', () {
      expect(
        computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 1.0,
          targetAspect: 0,
        ),
        isNull,
      );
      expect(
        computeSourceCropRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: 1.0,
          targetAspect: -1.0,
        ),
        isNull,
      );
    });
  });

  group('clampSourceOffset — targetAspect=1 (default)', () {
    test('square source at scale=1 forces center', () {
      final offset = clampSourceOffset(
        offset: const SourceOffset(0.0, 0.0),
        scale: 1.0,
        sourceAspect: 1.0,
      );
      expect(offset, const SourceOffset(0.5, 0.5));
    });

    test('landscape source at scale=1 allows horizontal pan only', () {
      final left = clampSourceOffset(
        offset: const SourceOffset(0.0, 0.0),
        scale: 1.0,
        sourceAspect: 2.0, // 600x300
      );
      expect(left.dx, 0.25);
      expect(left.dy, 0.5);
      final right = clampSourceOffset(
        offset: const SourceOffset(1.0, 1.0),
        scale: 1.0,
        sourceAspect: 2.0,
      );
      expect(right.dx, 0.75);
      expect(right.dy, 0.5);
    });

    test('portrait source at scale=1 allows vertical pan only', () {
      final top = clampSourceOffset(
        offset: const SourceOffset(0.0, 0.0),
        scale: 1.0,
        sourceAspect: 9.0 / 16.0,
      );
      expect(top.dx, 0.5);
      expect(top.dy, closeTo(0.28125, 1e-9));
    });

    test('scale=2 expands the legal offset range', () {
      final offset = clampSourceOffset(
        offset: const SourceOffset(0.0, 0.0),
        scale: 2.0,
        sourceAspect: 2.0,
      );
      expect(offset.dx, 0.125);
      expect(offset.dy, 0.25);
    });

    test('degenerate aspect returns default', () {
      expect(
        clampSourceOffset(
          offset: const SourceOffset(0.1, 0.1),
          scale: 1.0,
          sourceAspect: 0,
        ),
        kDefaultSourceOffset,
      );
    });
  });

  group('clampSourceOffset — targetAspect != 1', () {
    test('square source @ targetAspect=2 (1×2 grid) allows vertical pan', () {
      // sourceAspect = 1, targetAspect = 2 → source is taller → width-bound.
      // cropNormX = 1, cropNormY = 1/2 → only dy can move.
      final offset = clampSourceOffset(
        offset: const SourceOffset(0.0, 0.0),
        scale: 1.0,
        sourceAspect: 1.0,
        targetAspect: 2.0,
      );
      expect(offset.dx, 0.5); // pinned (halfX=0.5)
      expect(offset.dy, 0.25); // halfY = 1/4 → clamp to 0.25
    });

    test(
      'landscape 600x300 (aspect=2) @ targetAspect=1.5 (2×3) allows horizontal pan',
      () {
        // sourceAspect >= targetAspect → height-bound.
        // cropNormX = 1.5 / 2 = 0.75; halfX = 0.375. cropNormY = 1; halfY = 0.5.
        final left = clampSourceOffset(
          offset: const SourceOffset(0.0, 0.0),
          scale: 1.0,
          sourceAspect: 2.0,
          targetAspect: 1.5,
        );
        expect(left.dx, 0.375);
        expect(left.dy, 0.5);
      },
    );

    test('square source @ targetAspect=3 (1×3) gives a thin strip', () {
      // sourceAspect=1, targetAspect=3 → width-bound. cropNormY = 1/3.
      // halfY = 1/6.
      final offset = clampSourceOffset(
        offset: const SourceOffset(0.5, 0.0),
        scale: 1.0,
        sourceAspect: 1.0,
        targetAspect: 3.0,
      );
      expect(offset.dx, 0.5);
      expect(offset.dy, closeTo(1.0 / 6.0, 1e-9));
    });

    test('targetAspect=0 yields default offset (degenerate)', () {
      expect(
        clampSourceOffset(
          offset: const SourceOffset(0.1, 0.1),
          scale: 1.0,
          sourceAspect: 1.0,
          targetAspect: 0,
        ),
        kDefaultSourceOffset,
      );
    });
  });

  group('clampSourceScale', () {
    test('values inside the range pass through', () {
      expect(clampSourceScale(1.0), 1.0);
      expect(clampSourceScale(2.5), 2.5);
      expect(clampSourceScale(4.0), 4.0);
    });

    test('values below 1.0 clamp to 1.0', () {
      expect(clampSourceScale(0.5), 1.0);
      expect(clampSourceScale(-3), 1.0);
    });

    test('values above 4.0 clamp to 4.0', () {
      expect(clampSourceScale(10), 4.0);
    });

    test('NaN / infinity collapse to the default', () {
      expect(clampSourceScale(double.nan), kDefaultSourceScale);
      expect(clampSourceScale(double.infinity), kDefaultSourceScale);
    });
  });
}
