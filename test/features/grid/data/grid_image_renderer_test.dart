import 'dart:typed_data';

import 'package:fl_picraft/features/grid/data/renderers/grid_image_renderer.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/compute_cell_transform.dart';
import 'package:fl_picraft/features/grid/domain/usecases/compute_source_crop.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// Builds a [width] x [height] PNG with a unique color per source
  /// quadrant so per-cell crops can be sanity-checked by decoding the
  /// output and probing its top-left pixel.
  Uint8List quadrantCanvas({int width = 200, int height = 200}) {
    final canvas = img.Image(width: width, height: height, numChannels: 4);
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

    test('2x2 produces N cells in row-major order with square cells', () async {
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

      // Decode each cell and assert it is square + matches the source quadrant.
      final decoded = cells.map((b) => img.decodeImage(b)!).toList();
      for (final cell in decoded) {
        expect(cell.width, cell.height, reason: 'every cell must be square');
      }
      // 200x200 → 4 cells of 100x100. Center pixel of each cell.
      final tl = decoded[0].getPixel(50, 50);
      final tr = decoded[1].getPixel(50, 50);
      final bl = decoded[2].getPixel(50, 50);
      final br = decoded[3].getPixel(50, 50);

      expect((tl.r, tl.g, tl.b), (255, 0, 0));
      expect((tr.r, tr.g, tr.b), (0, 255, 0));
      expect((bl.r, bl.g, bl.b), (0, 0, 255));
      expect((br.r, br.g, br.b), (255, 255, 0));
    });

    test('3x3 even split yields 100x100 square cells', () async {
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
        expect(decoded.width, decoded.height);
        expect(decoded.width, 100);
        expect(decoded.height, 100);
      }
    });

    test('1x2 grid on landscape source produces 2 square cells', () async {
      // 600x300 source with targetAspect = 1×2 = 2 → width-bound crop:
      // baseW=600, baseH=300 (so crop = full source). cellSide = 600/2 = 300.
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: quadrantCanvas(width: 600, height: 300),
          gridType: GridType.g1x2,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      expect(cells, hasLength(2));
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, decoded.height);
        expect(decoded.width, 300);
      }
    });

    test(
      '2x3 grid on a landscape source crops to aspect 1.5 and outputs squares',
      () async {
        // 600x300 source @ targetAspect 1.5 → height-bound crop: baseW=450,
        // baseH=300. cellSide = 450 / 3 = 150.
        const renderer = GridImageRenderer();
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: quadrantCanvas(width: 600, height: 300),
            gridType: GridType.g2x3,
            spacing: 0,
            cornerRadius: 0,
          ),
        );
        expect(cells, hasLength(6));
        for (final bytes in cells) {
          final decoded = img.decodeImage(bytes)!;
          expect(decoded.width, decoded.height);
          expect(decoded.width, 150);
        }
      },
    );

    test(
      'all 5 grid types complete without error and produce squares',
      () async {
        const renderer = GridImageRenderer();
        final source = quadrantCanvas(width: 600, height: 360);
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
          // Every cell should be a valid PNG and a square.
          for (final bytes in cells) {
            final decoded = img.decodeImage(bytes);
            expect(decoded, isNotNull);
            expect(decoded!.width, decoded.height);
          }
        }
      },
    );

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
      final decoded = img.decodeImage(cells[0])!;
      final corner = decoded.getPixel(0, 0);
      expect(corner.a, 0);
      final center = decoded.getPixel(50, 50);
      expect(center.a, 255);
    });

    test(
      'sourceOffset propagates: 1×2 left-aligned crop selects the left half',
      () {
        // 600x300 source @ 1×2: cover-fit crop is the full source. With
        // a custom sourceOffset.dx=0 it stays left-aligned (still full
        // width because aspect matches). Use a 3×3 narrow crop instead.
      },
      skip: 'covered by compute_source_crop_test',
    );

    test('cell count for 3x3 hits the isolate threshold', () async {
      const renderer = GridImageRenderer();
      expect(GridType.g3x3.cellCount, kIsolateCellCountThreshold);
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: quadrantCanvas(width: 300, height: 300),
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      expect(cells, hasLength(9));
    });

    test(
      'sourceOffset (0, 0.5) on landscape 600x300 @ 3×3 selects left square',
      () async {
        // Build a 600×300 source with the left third red, middle green, right
        // blue. At targetAspect=1, crop side = 300. Default centered crop
        // picks x=150..450; left-aligned (dx=0) picks x=0..300. With 3x3 →
        // cell[0] covers x=0..100 (entirely red).
        final canvas = img.Image(width: 600, height: 300, numChannels: 4);
        for (var y = 0; y < 300; y++) {
          for (var x = 0; x < 600; x++) {
            if (x < 200) {
              canvas.setPixelRgba(x, y, 255, 0, 0, 255);
            } else if (x < 400) {
              canvas.setPixelRgba(x, y, 0, 255, 0, 255);
            } else {
              canvas.setPixelRgba(x, y, 0, 0, 255, 255);
            }
          }
        }
        final src = Uint8List.fromList(img.encodePng(canvas));

        const renderer = GridImageRenderer();
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: src,
            gridType: GridType.g3x3,
            spacing: 0,
            cornerRadius: 0,
            sourceOffset: const SourceOffset(0, 0.5),
          ),
        );
        expect(cells, hasLength(9));
        final cell0 = img.decodeImage(cells[0])!;
        expect(cell0.width, 100);
        expect(cell0.height, 100);
        final px = cell0.getPixel(50, 50);
        expect((px.r, px.g, px.b), (255, 0, 0));
      },
    );

    test('per-cell replacement: replaced cells differ from source slice; '
        'untouched cells keep source pixels', () async {
      // Build a 300x300 source with 9 distinct color quadrants (one
      // color per 3x3 cell). Replace cells 0 and 4 with a magenta
      // image; expect cells 0, 4 to be magenta, and cells 1, 2, 3, 5,
      // 6, 7, 8 to match the source crop colors.
      final src = img.Image(width: 300, height: 300, numChannels: 4);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          final color = img.ColorRgba8(20 + r * 60, 20 + c * 60, 100, 255);
          for (var y = r * 100; y < (r + 1) * 100; y++) {
            for (var x = c * 100; x < (c + 1) * 100; x++) {
              src.setPixel(x, y, color);
            }
          }
        }
      }
      final srcBytes = Uint8List.fromList(img.encodePng(src));

      // 50x50 solid magenta replacement (smaller than the 100x100 cell
      // → renderer cover-scales it up).
      final replacement = img.Image(width: 50, height: 50, numChannels: 4);
      img.fill(replacement, color: img.ColorRgba8(255, 0, 255, 255));
      final replacementBytes = Uint8List.fromList(img.encodePng(replacement));

      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: srcBytes,
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
          cellReplacements: {
            0: CellReplacementBytes(
              bytes: replacementBytes,
              width: 50,
              height: 50,
              scale: kDefaultCellScale,
              offset: kCellOffsetZero,
            ),
            4: CellReplacementBytes(
              bytes: replacementBytes,
              width: 50,
              height: 50,
              scale: kDefaultCellScale,
              offset: kCellOffsetZero,
            ),
          },
        ),
      );

      expect(cells, hasLength(9));
      // Cell 0 and 4 should be magenta (replacement).
      final cell0Px = img.decodeImage(cells[0])!.getPixel(50, 50);
      final cell4Px = img.decodeImage(cells[4])!.getPixel(50, 50);
      expect((cell0Px.r, cell0Px.g, cell0Px.b), (255, 0, 255));
      expect((cell4Px.r, cell4Px.g, cell4Px.b), (255, 0, 255));

      // Cells 1/2/3/5/6/7/8 should keep their source-slice colors —
      // verify a few representative ones.
      // Index 1 = row 0, col 1 → color (20, 80, 100)
      final cell1Px = img.decodeImage(cells[1])!.getPixel(50, 50);
      expect((cell1Px.r, cell1Px.g, cell1Px.b), (20, 80, 100));
      // Index 8 = row 2, col 2 → color (140, 140, 100)
      final cell8Px = img.decodeImage(cells[8])!.getPixel(50, 50);
      expect((cell8Px.r, cell8Px.g, cell8Px.b), (140, 140, 100));

      // Every output cell is still square.
      for (final bytes in cells) {
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, decoded.height);
        expect(decoded.width, 100);
      }
    });
  });
}
