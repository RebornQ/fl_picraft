import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/domain/usecases/stitch_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeStitchLayout — vertical mode', () {
    test('empty input produces a zero-sized layout', () {
      final layout = computeStitchLayout(
        sizes: const [],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
      );
      expect(layout.canvasWidth, 0);
      expect(layout.canvasHeight, 0);
      expect(layout.imageRects, isEmpty);
    });

    test(
      'canvas width matches the first image and height sums scaled rows',
      () {
        // 100x50 (target W=100), 200x100 (scaled to 100x50), 50x50 (scaled to
        // 100x100). Heights: 50 + 50 + 100 = 200. Spacing 0, no border.
        final layout = computeStitchLayout(
          sizes: const [
            StitchImageSize(width: 100, height: 50),
            StitchImageSize(width: 200, height: 100),
            StitchImageSize(width: 50, height: 50),
          ],
          mode: StitchMode.vertical,
          spacing: 0,
          borderWidth: 0,
        );

        expect(layout.canvasWidth, 100);
        expect(layout.canvasHeight, 200);
        expect(layout.imageRects, hasLength(3));
        expect(layout.imageRects[0].width, 100);
        expect(layout.imageRects[0].height, 50);
        expect(layout.imageRects[0].y, 0);
        expect(layout.imageRects[1].y, 50);
        expect(layout.imageRects[1].height, 50);
        expect(layout.imageRects[2].y, 100);
        expect(layout.imageRects[2].height, 100);
      },
    );

    test('spacing inserts gaps between adjacent images only', () {
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 100),
          StitchImageSize(width: 100, height: 100),
        ],
        mode: StitchMode.vertical,
        spacing: 20,
        borderWidth: 0,
      );

      expect(layout.canvasWidth, 100);
      // 100 + 20 (gap) + 100 = 220, no trailing gap.
      expect(layout.canvasHeight, 220);
      expect(layout.imageRects[1].y, 120);
    });

    test('border insets every image and grows the canvas', () {
      final layout = computeStitchLayout(
        sizes: const [StitchImageSize(width: 100, height: 100)],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 5,
      );

      expect(layout.canvasWidth, 110);
      expect(layout.canvasHeight, 110);
      expect(layout.imageRects.single.x, 5);
      expect(layout.imageRects.single.y, 5);
      expect(layout.imageRects.single.width, 100);
      expect(layout.imageRects.single.height, 100);
    });
  });

  group('computeStitchLayout — horizontal mode', () {
    test(
      'canvas height matches the first image and width sums scaled cols',
      () {
        // First H=100. Image 100x100 → 100x100. Image 50x100 → 50x100.
        // Image 200x50 (aspect 4) scaled to H=100 → 400x100. Total W=550.
        final layout = computeStitchLayout(
          sizes: const [
            StitchImageSize(width: 100, height: 100),
            StitchImageSize(width: 50, height: 100),
            StitchImageSize(width: 200, height: 50),
          ],
          mode: StitchMode.horizontal,
          spacing: 0,
          borderWidth: 0,
        );

        expect(layout.canvasWidth, 550);
        expect(layout.canvasHeight, 100);
        expect(layout.imageRects[0].x, 0);
        expect(layout.imageRects[0].width, 100);
        expect(layout.imageRects[1].x, 100);
        expect(layout.imageRects[1].width, 50);
        expect(layout.imageRects[2].x, 150);
        expect(layout.imageRects[2].width, 400);
      },
    );

    test('spacing + border together for horizontal layout', () {
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 100),
          StitchImageSize(width: 100, height: 100),
        ],
        mode: StitchMode.horizontal,
        spacing: 10,
        borderWidth: 4,
      );

      // canvasW = 4 + 100 + 10 + 100 + 4 = 218
      // canvasH = 100 + 2*4 = 108
      expect(layout.canvasWidth, 218);
      expect(layout.canvasHeight, 108);
      expect(layout.imageRects[0].x, 4);
      expect(layout.imageRects[1].x, 114);
      expect(layout.imageRects.first.y, 4);
    });
  });

  test(
    'StitchModeLabel exposes the Chinese display label expected by the UI',
    () {
      expect(StitchMode.vertical.displayLabel, '竖向');
      expect(StitchMode.horizontal.displayLabel, '横向');
    },
  );
}
