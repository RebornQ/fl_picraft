import 'dart:typed_data';

import 'package:fl_picraft/features/grid/data/renderers/grid_image_renderer.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// Builds a [width] x [height] PNG with a unique color per source
  /// quadrant so per-cell crops can be sanity-checked by decoding the
  /// output and probing its top-left pixel.
  Uint8List quadrantCanvas({int width = 200, int height = 200}) {
    final canvas = img.Image(width: width, height: height, numChannels: 4);
    // Top-left quadrant red, top-right green, bottom-left blue, bottom-right yellow.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final left = x < width / 2;
        final top = y < height / 2;
        if (top && left) {
          canvas.setPixelRgba(x, y, 255, 0, 0, 255);
        } else if (top && !left) {
          canvas.setPixelRgba(x, y, 0, 255, 0, 255);
        } else if (!top && left) {
          canvas.setPixelRgba(x, y, 0, 0, 255, 255);
        } else {
          canvas.setPixelRgba(x, y, 255, 255, 0, 255);
        }
      }
    }
    return Uint8List.fromList(img.encodePng(canvas));
  }

  group('GridImageRenderer', () {
    test('throws on empty source bytes', () {
      const renderer = GridImageRenderer();
      expect(
        () => renderer.render(
          GridRenderRequest(
            sourceBytes: Uint8List(0),
            gridType: GridType.g2x2,
            spacing: 0,
            cornerRadius: 0,
          ),
        ),
        throwsStateError,
      );
    });

    test('produces N cells in row-major order for 2x2', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: quadrantCanvas(),
          gridType: GridType.g2x2,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      expect(cells, hasLength(4));

      // Decode each cell and assert the dominant color (sampled center).
      final decoded = cells.map((b) => img.decodeImage(b)!).toList();
      // 200x200 → 4 cells of 100x100. Center pixel of each cell.
      final tl = decoded[0].getPixel(50, 50);
      final tr = decoded[1].getPixel(50, 50);
      final bl = decoded[2].getPixel(50, 50);
      final br = decoded[3].getPixel(50, 50);

      expect((tl.r, tl.g, tl.b), (255, 0, 0)); // top-left -> red
      expect((tr.r, tr.g, tr.b), (0, 255, 0)); // top-right -> green
      expect((bl.r, bl.g, bl.b), (0, 0, 255)); // bottom-left -> blue
      expect((br.r, br.g, br.b), (255, 255, 0)); // bottom-right -> yellow
    });

    test('cell dimensions match expected sizes for 3x3 even split', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: quadrantCanvas(width: 300, height: 300),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      expect(cells, hasLength(9));
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, 100);
        expect(decoded.height, 100);
      }
    });

    test('all 5 grid types complete without error', () async {
      const renderer = GridImageRenderer();
      final source = quadrantCanvas(width: 320, height: 320);
      for (final type in GridType.values) {
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: source,
            gridType: type,
            spacing: 0,
            cornerRadius: 0,
          ),
        );
        expect(
          cells,
          hasLength(type.cellCount),
          reason: '${type.name} should produce ${type.cellCount} cells',
        );
        // Every cell should be a valid PNG.
        for (final bytes in cells) {
          expect(img.decodeImage(bytes), isNotNull);
        }
      }
    });

    test('rounded corners punch alpha at the top-left pixel', () async {
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: quadrantCanvas(width: 200, height: 200),
          gridType: GridType.g2x2,
          spacing: 0,
          cornerRadius: 20,
        ),
      );
      // Top-left corner of cell[0] should be fully transparent.
      final decoded = img.decodeImage(cells[0])!;
      final corner = decoded.getPixel(0, 0);
      expect(corner.a, 0);
      // But the center should be opaque (red).
      final center = decoded.getPixel(50, 50);
      expect(center.a, 255);
    });
  });
}
