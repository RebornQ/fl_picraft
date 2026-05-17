import 'package:fl_picraft/features/grid/domain/usecases/compute_source_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSourceSquareRect — cover-fit (scale=1, offset=(0.5,0.5))', () {
    test('square source returns the full image', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 300,
        sourceHeight: 300,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.x, 0);
      expect(rect.y, 0);
      expect(rect.side, 300);
    });

    test('landscape source returns the centered shortest-side square', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      // Center of 300x300 inside 600x300 → x=(600-300)/2=150.
      expect(rect.x, 150);
      expect(rect.y, 0);
    });

    test('portrait source returns the centered shortest-side square', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 300,
        sourceHeight: 600,
        offset: kDefaultSourceOffset,
        scale: kDefaultSourceScale,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      expect(rect.x, 0);
      expect(rect.y, 150);
    });
  });

  group('computeSourceSquareRect — scale > 1 shrinks the square', () {
    test('scale=2 on 400x400 → 200x200 from center', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 2.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 200);
      expect(rect.x, 100); // (400-200)/2
      expect(rect.y, 100);
    });

    test('scale=4 on 400x400 → 100x100 from center', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 4.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 100);
      expect(rect.x, 150);
      expect(rect.y, 150);
    });

    test('scale clamped above 4.0', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 10.0,
      );
      expect(rect, isNotNull);
      // Stays at scale=4 → side=100.
      expect(rect!.side, 100);
    });

    test('scale clamped below 1.0', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 400,
        sourceHeight: 400,
        offset: kDefaultSourceOffset,
        scale: 0.5,
      );
      expect(rect, isNotNull);
      // Stays at scale=1 → side=400.
      expect(rect!.side, 400);
    });
  });

  group('computeSourceSquareRect — offset shifts the crop', () {
    test('landscape 600x300 + offset.dx=0 (left-most) → x=0', () {
      // At scale=1 on landscape, halfX = 0.25 so dx=0 clamps to 0.25,
      // putting the crop's center at x=150 → x=0 (left-aligned).
      final rect = computeSourceSquareRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: const SourceOffset(0, 0.5),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      expect(rect.x, 0);
      expect(rect.y, 0);
    });

    test('landscape 600x300 + offset.dx=1.0 (right-most) → x=300', () {
      // Symmetric to the left-aligned case; dx clamps to 0.75 → center
      // at x=450 → x=300 (right-aligned).
      final rect = computeSourceSquareRect(
        sourceWidth: 600,
        sourceHeight: 300,
        offset: const SourceOffset(1.0, 0.5),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      expect(rect.x, 300);
      expect(rect.y, 0);
    });

    test('portrait 300x600 + offset.dy=0 (top-most) → y=0', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 300,
        sourceHeight: 600,
        offset: const SourceOffset(0.5, 0.0),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      expect(rect.x, 0);
      expect(rect.y, 0);
    });

    test('portrait 300x600 + offset.dy=1.0 (bottom-most) → y=300', () {
      final rect = computeSourceSquareRect(
        sourceWidth: 300,
        sourceHeight: 600,
        offset: const SourceOffset(0.5, 1.0),
        scale: 1.0,
      );
      expect(rect, isNotNull);
      expect(rect!.side, 300);
      expect(rect.x, 0);
      expect(rect.y, 300);
    });
  });

  group('computeSourceSquareRect — degenerate inputs', () {
    test('zero width returns null', () {
      expect(
        computeSourceSquareRect(
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
        computeSourceSquareRect(
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
        computeSourceSquareRect(
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
        computeSourceSquareRect(
          sourceWidth: 300,
          sourceHeight: 300,
          offset: kDefaultSourceOffset,
          scale: double.nan,
        ),
        isNull,
      );
    });
  });

  group('clampSourceOffset', () {
    test('square source at scale=1 forces center', () {
      // At scale=1 on a square, the crop already covers the source so
      // the only legal offset is the center.
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
      expect(left.dy, 0.5); // halfY = 0.5, only legal value
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
        sourceAspect: 9.0 / 16.0, // 9:16 portrait
      );
      expect(top.dx, 0.5);
      // halfY = aspect/2 = 0.28125
      expect(top.dy, closeTo(0.28125, 1e-9));
    });

    test('scale=2 expands the legal offset range', () {
      // At scale=2 on landscape aspect 2.0, cropNormX=0.25, halfX=0.125;
      // cropNormY=0.5, halfY=0.25.
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
