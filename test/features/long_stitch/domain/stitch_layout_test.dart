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

  group('computeStitchLayout — movie-subtitle mode (PRD §3.3)', () {
    test(
      'first image full + subsequent images contribute bottom band only',
      () {
        // Three 100x300 images, band = 60. Width-normalize → all 100 wide.
        // First image's scaled height = 300 (full). Each subsequent image
        // contributes a 60px band. Canvas H = 300 + 60 + 60 = 420.
        final layout = computeStitchLayout(
          sizes: const [
            StitchImageSize(width: 100, height: 300),
            StitchImageSize(width: 100, height: 300),
            StitchImageSize(width: 100, height: 300),
          ],
          mode: StitchMode.vertical,
          spacing: 0,
          borderWidth: 0,
          subtitleOnlyMode: true,
          subtitleBandHeight: 60,
        );

        expect(layout.canvasWidth, 100);
        expect(layout.canvasHeight, 420);
        expect(layout.imageRects, hasLength(3));
        // First placed full at (0, 0).
        expect(layout.imageRects[0].y, 0);
        expect(layout.imageRects[0].height, 300);
        // Subsequent images: band height 60, abutting.
        expect(layout.imageRects[1].y, 300);
        expect(layout.imageRects[1].height, 60);
        expect(layout.imageRects[2].y, 360);
        expect(layout.imageRects[2].height, 60);

        // Source crops: null for first, bottom band of source for rest.
        expect(layout.srcCrops, isNotNull);
        expect(layout.srcCrops![0], isNull);
        // Each non-first source is 100x300 in source coords. The
        // dest band 60 maps back to a 60-pixel src crop (since the
        // source width matches the target width — no scaling).
        expect(layout.srcCrops![1]!.x, 0);
        expect(layout.srcCrops![1]!.width, 100);
        expect(layout.srcCrops![1]!.height, 60);
        expect(layout.srcCrops![1]!.y, 240); // 300 - 60
      },
    );

    test('image height < band height uses the full image (PRD edge case)', () {
      // Second image is shorter than the band. The layout should
      // place it at its scaled height, not stretch it.
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 40), // < 60 band
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
      );

      expect(layout.canvasWidth, 100);
      expect(layout.canvasHeight, 340); // 300 + 40
      expect(layout.imageRects[1].height, 40);
      // The whole short image is used (srcCrop spans full source).
      expect(layout.srcCrops![1]!.y, 0);
      expect(layout.srcCrops![1]!.height, 40);
    });

    test('width-normalization scales the band crop to source pixels', () {
      // First image 200x400 → targetWidth = 200.
      // Second image 100x400 (narrower) gets width-scaled to 200 → height
      // becomes 800. Band 100 (in scaled coords) maps to source-band 50.
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 200, height: 400),
          StitchImageSize(width: 100, height: 400),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 100,
      );

      expect(layout.canvasWidth, 200);
      expect(layout.canvasHeight, 500); // 400 + 100
      expect(layout.imageRects[1].height, 100);
      expect(layout.srcCrops![1]!.width, 100);
      // 100 (band) * 400 (srcH) / 800 (scaledH) = 50.
      expect(layout.srcCrops![1]!.height, 50);
      expect(layout.srcCrops![1]!.y, 350); // 400 - 50
    });

    test('single image with subtitle on degrades to plain vertical', () {
      // PRD edge case: nothing to overlay → plain vertical.
      final layout = computeStitchLayout(
        sizes: const [StitchImageSize(width: 100, height: 200)],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 80,
      );

      expect(layout.canvasWidth, 100);
      expect(layout.canvasHeight, 200);
      expect(layout.srcCrops, isNull); // no movie-subtitle path taken
    });

    test('horizontal + subtitle flag → flag ignored', () {
      // PRD edge case: subtitle mode only applies vertically.
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 100),
          StitchImageSize(width: 100, height: 100),
        ],
        mode: StitchMode.horizontal,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 50,
      );

      expect(layout.canvasHeight, 100);
      expect(layout.canvasWidth, 200);
      expect(layout.srcCrops, isNull);
    });

    test('border insets the subtitle layout', () {
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 200),
          StitchImageSize(width: 100, height: 200),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 5,
        subtitleOnlyMode: true,
        subtitleBandHeight: 50,
      );

      // First image full (200) + band (50) + 2*border (10) = 260
      expect(layout.canvasWidth, 110);
      expect(layout.canvasHeight, 260);
      expect(layout.imageRects[0].x, 5);
      expect(layout.imageRects[0].y, 5);
      expect(layout.imageRects[1].y, 205); // 5 + 200
    });
  });
}
