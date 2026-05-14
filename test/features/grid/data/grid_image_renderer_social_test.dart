import 'dart:typed_data';

import 'package:fl_picraft/features/grid/data/renderers/grid_image_renderer.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/compute_center_transform.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// 300x300 source with each of the 9 cells (3x3 split) a distinct color.
  /// Layout (row-major): the center cell (index 4) is cyan.
  Uint8List sourceWithDistinctCells() {
    final canvas = img.Image(width: 300, height: 300, numChannels: 4);
    final colors = <(int, int, int)>[
      (255, 0, 0), // 0: red
      (0, 255, 0), // 1: green
      (0, 0, 255), // 2: blue
      (255, 255, 0), // 3: yellow
      (0, 255, 255), // 4: cyan (center)
      (255, 0, 255), // 5: magenta
      (128, 0, 0), // 6: dark red
      (0, 128, 0), // 7: dark green
      (0, 0, 128), // 8: dark blue
    ];
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 300; x++) {
        final row = y ~/ 100;
        final col = x ~/ 100;
        final idx = row * 3 + col;
        final (r, g, b) = colors[idx];
        canvas.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return Uint8List.fromList(img.encodePng(canvas));
  }

  /// 100x100 solid-white replacement image — easy to spot against the
  /// cyan center of the source.
  Uint8List whiteReplacement() {
    final canvas = img.Image(width: 100, height: 100, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
    return Uint8List.fromList(img.encodePng(canvas));
  }

  group('GridImageRenderer — nine-grid-social mode', () {
    test('without center replacement keeps the original 5th cell', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      expect(cells, hasLength(9));
      // The 5th cell (index 4) should be cyan from the source.
      final centerCell = img.decodeImage(cells[4])!;
      final px = centerCell.getPixel(50, 50);
      expect((px.r, px.g, px.b), (0, 255, 255));
    });

    test(
      'with center replacement, cell[4] is the replacement (white)',
      () async {
        const renderer = GridImageRenderer();
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: sourceWithDistinctCells(),
            gridType: GridType.g3x3,
            spacing: 0,
            cornerRadius: 0,
            centerImageBytes: whiteReplacement(),
          ),
        );
        expect(cells, hasLength(9));
        // Cell 4 should now be solid white from the replacement image.
        final centerCell = img.decodeImage(cells[4])!;
        final px = centerCell.getPixel(50, 50);
        expect((px.r, px.g, px.b), (255, 255, 255));
        // The other cells should be unchanged. Spot-check cell 0 (red).
        final topLeft = img.decodeImage(cells[0])!;
        final cornerPx = topLeft.getPixel(50, 50);
        expect((cornerPx.r, cornerPx.g, cornerPx.b), (255, 0, 0));
      },
    );

    test('center replacement is ignored when grid type is not 3x3', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g2x2,
          spacing: 0,
          cornerRadius: 0,
          centerImageBytes: whiteReplacement(),
        ),
      );
      // 2x2 means 4 cells, no center-replacement branch.
      expect(cells, hasLength(4));
      // No cell should be the replacement white.
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        final px = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
        expect(
          (px.r, px.g, px.b),
          isNot((255, 255, 255)),
          reason: 'replacement should be ignored outside 3x3',
        );
      }
    });

    test('cell[4] dimensions match other cells regardless of replacement '
        'image native size', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          centerImageBytes: whiteReplacement(), // 100x100
        ),
      );
      final centerCell = img.decodeImage(cells[4])!;
      // Source 300x300 / 3 = 100x100 cell.
      expect(centerCell.width, 100);
      expect(centerCell.height, 100);
    });

    test('scale=2 zooms into the replacement image', () async {
      // Build a replacement image with a colored quadrant pattern so
      // the zoom-in is observable: 100x100 with the inner 50x50 (the
      // part the renderer crops at scale=2) all yellow.
      final replacement = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(replacement, color: img.ColorRgba8(0, 0, 0, 255));
      // Inner 50x50 yellow.
      for (var y = 25; y < 75; y++) {
        for (var x = 25; x < 75; x++) {
          replacement.setPixelRgba(x, y, 255, 255, 0, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(replacement));

      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          centerImageBytes: bytes,
          centerScale: 2,
        ),
      );
      // At scale=2 the renderer should crop just the inner 50x50 of
      // the replacement and resize to the cell, so the center cell is
      // entirely yellow.
      final centerCell = img.decodeImage(cells[4])!;
      final px = centerCell.getPixel(50, 50);
      expect((px.r, px.g, px.b), (255, 255, 0));
    });

    test('user-supplied offset shifts the visible crop of the replacement '
        'image', () async {
      // Replacement image: 200x100 with the **left half** red and the
      // **right half** green. At scale=1 (cover-fit) only one half is
      // visible (cell is 100x100 → 100x100 slice from the 200x100
      // image). Default offset 0 → centered slice (x=50..150) which
      // straddles the red/green boundary; offsetting positively in dx
      // should shift the slice **leftward** in source coords, exposing
      // more red.
      final replacement = img.Image(width: 200, height: 100, numChannels: 4);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 200; x++) {
          if (x < 100) {
            replacement.setPixelRgba(x, y, 255, 0, 0, 255);
          } else {
            replacement.setPixelRgba(x, y, 0, 255, 0, 255);
          }
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(replacement));

      const renderer = GridImageRenderer();
      // dx = +50 in cell-target pixels. cover scale for 200x100 image
      // on 100x100 cell is 1.0 (height-limited). effectiveScale = 1.0.
      // source shift = -50/1 = -50, so slice center is 100 - 50 = 50.
      // slice = 0..100 — entirely red.
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          centerImageBytes: bytes,
          centerOffset: const CenterOffset(50, 0),
        ),
      );
      // Wait — 50/100 cover ratio means cover=1.0. But for a 100×100
      // cell with offset.dx = +50, the clamp lower bound is
      // half-surplus = (imageW * cover - cellW) / 2 = (200 - 100) / 2 = 50.
      // 50 is exactly at the limit so it should pass.
      final centerCell = img.decodeImage(cells[4])!;
      final px = centerCell.getPixel(50, 50);
      // Should be predominantly red (the right-shifted slice is the
      // left half of the source image).
      expect(px.r > px.g, true);
    });

    test('cellCount for 3x3 hits the isolate threshold; sync fallback still '
        'produces the expected 9 cells with replacement', () async {
      // Sanity: a 3x3 = 9 cells triggers the isolate threshold. The
      // sync fallback should still produce identical output. (Under
      // `flutter_test` the `compute` path generally fails to spawn an
      // isolate and the renderer falls back to the sync code path; this
      // test verifies that fallback round-trips correctly with a
      // replacement image.)
      const renderer = GridImageRenderer();
      expect(GridType.g3x3.cellCount, kIsolateCellCountThreshold);
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: sourceWithDistinctCells(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          centerImageBytes: whiteReplacement(),
        ),
      );
      expect(cells, hasLength(9));
      final center = img.decodeImage(cells[4])!;
      final px = center.getPixel(50, 50);
      expect((px.r, px.g, px.b), (255, 255, 255));
    });
  });

  group('GridImageRenderer — social-mode source crop (PRD §4.2 step 1)', () {
    /// 600×300 landscape source split into 3×3. Without the social-mode
    /// crop the cells would be 200×100 each (non-square); with the crop
    /// they should be 100×100 (square).
    Uint8List landscapeSource() {
      final canvas = img.Image(width: 600, height: 300, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(80, 80, 80, 255));
      return Uint8List.fromList(img.encodePng(canvas));
    }

    test('socialMode=true on a non-square source produces 9 square cells '
        'matching the shorter-side / 3 dimension', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: landscapeSource(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          nineGridSocialMode: true,
        ),
      );
      expect(cells, hasLength(9));
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, decoded.height, reason: 'cells must be square');
        // shortSide(600, 300) / 3 = 100.
        expect(decoded.width, 100);
      }
    });

    test('socialMode=false on the same non-square source preserves the '
        'non-square 200×100 cell shape (regular 3x3 behaviour)', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: landscapeSource(),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          // nineGridSocialMode defaults to false.
        ),
      );
      expect(cells, hasLength(9));
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, 200);
        expect(decoded.height, 100);
      }
    });

    test(
      'socialMode=true on a square source is a no-op (cells unchanged)',
      () async {
        const renderer = GridImageRenderer();
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: sourceWithDistinctCells(),
            gridType: GridType.g3x3,
            spacing: 0,
            cornerRadius: 0,
            nineGridSocialMode: true,
          ),
        );
        expect(cells, hasLength(9));
        // The crop is a no-op on a square source, so the centre cell is
        // still the cyan one from the original layout.
        final centerCell = img.decodeImage(cells[4])!;
        final px = centerCell.getPixel(50, 50);
        expect((px.r, px.g, px.b), (0, 255, 255));
      },
    );
  });

  group('GridRenderRequest.hasCenterReplacement', () {
    test('true only when grid type is 3x3 and bytes non-empty', () {
      // Wrong grid type.
      final r1 = GridRenderRequest(
        sourceBytes: Uint8List.fromList([1, 2, 3]),
        gridType: GridType.g2x2,
        spacing: 0,
        cornerRadius: 0,
        centerImageBytes: Uint8List.fromList([1]),
      );
      expect(r1.hasCenterReplacement, false);

      // Right grid type but no bytes.
      final r2 = GridRenderRequest(
        sourceBytes: Uint8List.fromList([1, 2, 3]),
        gridType: GridType.g3x3,
        spacing: 0,
        cornerRadius: 0,
      );
      expect(r2.hasCenterReplacement, false);

      // Right grid type + non-empty bytes.
      final r3 = GridRenderRequest(
        sourceBytes: Uint8List.fromList([1, 2, 3]),
        gridType: GridType.g3x3,
        spacing: 0,
        cornerRadius: 0,
        centerImageBytes: Uint8List.fromList([1]),
      );
      expect(r3.hasCenterReplacement, true);

      // Right grid type + empty bytes.
      final r4 = GridRenderRequest(
        sourceBytes: Uint8List.fromList([1, 2, 3]),
        gridType: GridType.g3x3,
        spacing: 0,
        cornerRadius: 0,
        centerImageBytes: Uint8List(0),
      );
      expect(r4.hasCenterReplacement, false);
    });
  });

  group('GridRenderRequest defaults', () {
    test('nineGridSocialMode defaults to false', () {
      final r = GridRenderRequest(
        sourceBytes: Uint8List.fromList([1, 2, 3]),
        gridType: GridType.g3x3,
        spacing: 0,
        cornerRadius: 0,
      );
      expect(r.nineGridSocialMode, false);
    });

    test(
      'explicit nineGridSocialMode is preserved through the constructor',
      () {
        final r = GridRenderRequest(
          sourceBytes: Uint8List.fromList([1, 2, 3]),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          nineGridSocialMode: true,
        );
        expect(r.nineGridSocialMode, true);
      },
    );
  });
}
