import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/domain/usecases/detect_letterbox.dart';
import 'package:fl_picraft/features/long_stitch/domain/usecases/stitch_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeStitchLayout — letterboxInsets back-compat', () {
    test('passing letterboxInsets: null is identical to omitting it', () {
      // The "no insets" path must be byte-identical to the legacy call so
      // existing callers (preview canvas, renderer without the flag)
      // are unaffected.
      final withoutArg = computeStitchLayout(
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
      final withNullArg = computeStitchLayout(
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
        letterboxInsets: null,
      );

      expect(withoutArg.canvasWidth, withNullArg.canvasWidth);
      expect(withoutArg.canvasHeight, withNullArg.canvasHeight);
      expect(withoutArg.imageRects, withNullArg.imageRects);
      expect(withoutArg.srcCrops, withNullArg.srcCrops);
    });

    test('length-mismatched insets list falls back to no-trim semantics', () {
      final ref = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
      );
      final mismatched = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
        letterboxInsets: const [
          LetterboxInsets(topPx: 10, bottomPx: 10),
        ], // length 1 vs sizes length 2
      );

      expect(mismatched.canvasHeight, ref.canvasHeight);
      expect(mismatched.imageRects, ref.imageRects);
    });
  });

  group('computeStitchLayout — letterboxInsets active', () {
    test('two-image subtitle mode trims first image fully on both ends', () {
      // First image 100×300 with top=20 / bottom=20 letterbox → usable
      // src height = 260. Band height = 60 for image 1.
      //
      // No-insets case:
      //   canvasH = 300 (full first) + 60 (band) = 360
      //
      // With insets case:
      //   First image: scaled height = 260 (full usable)
      //   Second image: scaledHeight uses effSrcHeight=260 (after trim)
      //     → 260 * 100 / 100 = 260
      //     effBand = min(260, 60) = 60
      //   canvasH = 260 + 60 = 320
      final noInsets = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
      );
      expect(noInsets.canvasHeight, 360);

      final withInsets = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
        letterboxInsets: const [
          LetterboxInsets(topPx: 20, bottomPx: 20),
          LetterboxInsets(topPx: 20, bottomPx: 20),
        ],
      );

      expect(withInsets.canvasHeight, 320);
      expect(withInsets.imageRects[0].height, 260); // first image (260)
      expect(withInsets.imageRects[1].height, 60); // band

      // First image gets a srcCrop that excludes the bars.
      expect(withInsets.srcCrops, isNotNull);
      expect(withInsets.srcCrops![0]!.y, 20);
      expect(withInsets.srcCrops![0]!.height, 260);

      // Second image's band crop anchors to the bottom of the usable
      // region (y = 280 - 60 = 220) — never inside the bottom bar.
      final secondCrop = withInsets.srcCrops![1]!;
      expect(secondCrop.height, lessThanOrEqualTo(60));
      // Top of crop must be at or above (300 - 20 - 60) = 220.
      expect(secondCrop.y, lessThanOrEqualTo(220));
      // Bottom of crop must be at or above (300 - 20) — i.e. above the
      // bottom letterbox bar.
      expect(secondCrop.y + secondCrop.height, lessThanOrEqualTo(280));
    });

    test('zero insets behave exactly like no insets', () {
      final noInsets = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
      );
      final zeroInsets = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: true,
        subtitleBandHeight: 60,
        letterboxInsets: const [LetterboxInsets.zero, LetterboxInsets.zero],
      );

      expect(zeroInsets.canvasHeight, noInsets.canvasHeight);
      expect(zeroInsets.imageRects, noInsets.imageRects);
      // The first crop falls back to null (no trim) in both cases.
      expect(zeroInsets.srcCrops![0], isNull);
      expect(noInsets.srcCrops![0], isNull);
    });

    test('plain-vertical path ignores letterboxInsets (subtitle flag off)', () {
      final layout = computeStitchLayout(
        sizes: const [
          StitchImageSize(width: 100, height: 300),
          StitchImageSize(width: 100, height: 300),
        ],
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        subtitleOnlyMode: false,
        letterboxInsets: const [
          LetterboxInsets(topPx: 50, bottomPx: 50),
          LetterboxInsets(topPx: 50, bottomPx: 50),
        ],
      );

      // Plain vertical: both images full-height, no srcCrops.
      expect(layout.canvasHeight, 600);
      expect(layout.srcCrops, isNull);
    });
  });
}
