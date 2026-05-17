import 'package:fl_picraft/features/long_stitch/domain/usecases/detect_letterbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _fillRect(
  img.Image image, {
  required int x1,
  required int y1,
  required int x2,
  required int y2,
  required img.Color color,
}) {
  img.fillRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: color);
  return image;
}

void main() {
  group('detectLetterbox', () {
    test('all-black image returns LetterboxInsets.zero (bail-out)', () {
      // A frame that's entirely dark gives the detector nothing to anchor
      // against — we bail out so the user can see the unmodified image
      // and realize the heuristic gave up.
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      expect(detectLetterbox(image), LetterboxInsets.zero);
    });

    test('all-white image returns LetterboxInsets.zero', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      expect(detectLetterbox(image), LetterboxInsets.zero);
    });

    test('top and bottom black bars return matching insets', () {
      // 100×100 image, rows 0–19 black, 20–79 white, 80–99 black.
      // Detector should report topPx=20, bottomPx=20.
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      _fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 99,
        y2: 19,
        color: img.ColorRgb8(0, 0, 0),
      );
      _fillRect(
        image,
        x1: 0,
        y1: 80,
        x2: 99,
        y2: 99,
        color: img.ColorRgb8(0, 0, 0),
      );

      expect(
        detectLetterbox(image),
        const LetterboxInsets(topPx: 20, bottomPx: 20),
      );
    });

    test('asymmetric bars: top 10 / bottom 30', () {
      final image = img.Image(width: 50, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      _fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 49,
        y2: 9,
        color: img.ColorRgb8(0, 0, 0),
      );
      _fillRect(
        image,
        x1: 0,
        y1: 70,
        x2: 49,
        y2: 99,
        color: img.ColorRgb8(0, 0, 0),
      );

      expect(
        detectLetterbox(image),
        const LetterboxInsets(topPx: 10, bottomPx: 30),
      );
    });

    test('single-pixel noise inside a black bar still counts as letterbox', () {
      // 1-pixel of noise in a row is below the rowDarkRatio threshold,
      // so the row is still considered dark — no early termination.
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      _fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 99,
        y2: 19,
        color: img.ColorRgb8(0, 0, 0),
      );
      // One bright pixel inside the otherwise-black top bar.
      image.setPixelRgb(50, 5, 255, 255, 255);

      // The default rowDarkRatio = 0.99 → 99/100 dark pixels still
      // qualifies as a dark row.
      expect(detectLetterbox(image).topPx, 20);
    });

    test('all-white frame with a single dark pixel returns zero (no bars)', () {
      // The dark pixel is well below the rowDarkRatio threshold, so no
      // row counts as dark and the detector reports no letterbox.
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      image.setPixelRgb(50, 5, 0, 0, 0);

      expect(detectLetterbox(image), LetterboxInsets.zero);
    });

    test('single-column / degenerate image returns zero', () {
      // 1×100 — height>1 but only one column. The detector should
      // still run and won't crash. (The bar would consume the whole
      // image if we let it; the bail-out keeps the output safe.)
      final image = img.Image(width: 1, height: 100);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      expect(detectLetterbox(image), LetterboxInsets.zero);
    });

    test('1-row image returns zero', () {
      final image = img.Image(width: 100, height: 1);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      expect(detectLetterbox(image), LetterboxInsets.zero);
    });

    test('LetterboxInsets equality / hashCode are value-based', () {
      const a = LetterboxInsets(topPx: 20, bottomPx: 30);
      const b = LetterboxInsets(topPx: 20, bottomPx: 30);
      const c = LetterboxInsets(topPx: 20, bottomPx: 40);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
