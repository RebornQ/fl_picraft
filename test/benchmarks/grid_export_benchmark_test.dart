// Headless benchmark for the grid render pipeline.
//
// Tagged so default `flutter test` runs skip it (configured in
// `dart_test.yaml`) — performance numbers from a CI runner aren't
// comparable across machines and would gate PRs on machine variance.
// Run explicitly with:
//
//     flutter test --run-skipped --tags benchmark test/benchmarks/
//
// Grid export does N PNG encodes (one per cell). The 3x3 social-mode
// path is the heaviest realistic shape: it center-crops to square,
// composes one custom-cropped middle cell, and PNG-encodes 9 outputs.
// The 2x3 path covers a non-square shape (6 encodes) so we also exercise
// the residual-pixel distribution on the height axis.

@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:fl_picraft/features/grid/data/renderers/grid_image_renderer.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/domain/usecases/grid_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List syntheticPng({
    required int width,
    required int height,
    required int seed,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8((seed * 12) % 255, 100, 200));
    return Uint8List.fromList(img.encodePng(image));
  }

  group('Grid export benchmark', () {
    test('3x3 grid @ 3000x3000 source PNG encode (9 cells)', () async {
      final synthSw = Stopwatch()..start();
      final source = syntheticPng(width: 3000, height: 3000, seed: 0);
      synthSw.stop();
      // ignore: avoid_print
      print('[grid-3x3] synth elapsed: ${synthSw.elapsedMilliseconds} ms');

      final renderSw = Stopwatch()..start();
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: source,
          gridType: GridType.g3x3,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      renderSw.stop();
      // ignore: avoid_print
      print('[grid-3x3] render elapsed: ${renderSw.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print(
        '[grid-3x3] cell bytes (avg): ${cells.fold<int>(0, (a, b) => a + b.length) ~/ cells.length}',
      );

      expect(cells, hasLength(9));
      expect(renderSw.elapsed.inSeconds, lessThan(30));
    });

    test('2x3 grid @ 4000x4000 source PNG encode (6 cells)', () async {
      final synthSw = Stopwatch()..start();
      final source = syntheticPng(width: 4000, height: 4000, seed: 1);
      synthSw.stop();
      // ignore: avoid_print
      print('[grid-2x3] synth elapsed: ${synthSw.elapsedMilliseconds} ms');

      final renderSw = Stopwatch()..start();
      const renderer = GridImageRenderer();
      final cells = await renderer.render(
        GridRenderRequest(
          sourceBytes: source,
          gridType: GridType.g2x3,
          spacing: 0,
          cornerRadius: 0,
        ),
      );
      renderSw.stop();
      // ignore: avoid_print
      print('[grid-2x3] render elapsed: ${renderSw.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print(
        '[grid-2x3] cell bytes (avg): ${cells.fold<int>(0, (a, b) => a + b.length) ~/ cells.length}',
      );

      expect(cells, hasLength(6));
      expect(renderSw.elapsed.inSeconds, lessThan(30));
    });

    test(
      '3x3 nine-grid social mode @ 3000x3000 + center replacement',
      () async {
        final synthSw = Stopwatch()..start();
        final source = syntheticPng(width: 3000, height: 3000, seed: 2);
        final center = syntheticPng(width: 1000, height: 1000, seed: 3);
        synthSw.stop();
        // ignore: avoid_print
        print('[grid-social] synth elapsed: ${synthSw.elapsedMilliseconds} ms');

        final renderSw = Stopwatch()..start();
        const renderer = GridImageRenderer();
        final cells = await renderer.render(
          GridRenderRequest(
            sourceBytes: source,
            gridType: GridType.g3x3,
            spacing: 0,
            cornerRadius: 0,
            nineGridSocialMode: true,
            centerImageBytes: center,
          ),
        );
        renderSw.stop();
        // ignore: avoid_print
        print(
          '[grid-social] render elapsed: ${renderSw.elapsedMilliseconds} ms',
        );

        expect(cells, hasLength(9));
        expect(renderSw.elapsed.inSeconds, lessThan(30));
      },
    );
  });
}
