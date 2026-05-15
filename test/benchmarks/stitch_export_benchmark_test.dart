// Headless benchmark for the long-stitch render pipeline.
//
// Tagged so default `flutter test` runs skip it (configured in
// `dart_test.yaml`) — performance numbers from a CI runner aren't
// comparable across machines and would gate PRs on machine variance.
// Run explicitly with:
//
//     flutter test --run-skipped --tags benchmark test/benchmarks/
//
// `--run-skipped` overrides the dart_test.yaml `skip:` directive;
// `--tags benchmark` then narrows down to only benchmark tests.
//
// The PRD §7 budget is "20 images stitch + export under 5 seconds on a
// mid-tier device". This harness uses a deliberately loose 30s ceiling
// so the test won't fail on slow CI hardware — its purpose is to record
// a baseline for triage, not to gate releases. The real device target
// (5s) is verified manually per `manual-test-plan.md`.

@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:fl_picraft/features/long_stitch/data/renderers/stitch_image_renderer.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_editor_state.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/domain/usecases/stitch_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Synthesize a [width] x [height] PNG with a flat color so the
  /// decode path has realistic work to do but the pixel content is
  /// deterministic across runs.
  Uint8List syntheticPng({
    required int width,
    required int height,
    required int seed,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8((seed * 12) % 255, 100, 200));
    return Uint8List.fromList(img.encodePng(image));
  }

  group('Stitch export benchmark', () {
    test('20 images @ 1920x1080 vertical stitch + PNG encode', () async {
      // Phase 1: synth (pure pre-work; not part of the budget).
      final synthSw = Stopwatch()..start();
      final imageBytes = List.generate(
        20,
        (i) => syntheticPng(width: 1920, height: 1080, seed: i),
      );
      synthSw.stop();
      // ignore: avoid_print
      print('[stitch] synth elapsed: ${synthSw.elapsedMilliseconds} ms');

      // Phase 2: render (the actual budgeted work — decode + compose +
      // encode happens inside StitchImageRenderer.render).
      final renderSw = Stopwatch()..start();
      const renderer = StitchImageRenderer();
      final request = StitchRenderRequest(
        imageBytes: imageBytes,
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        borderColorArgb: 0xFF000000,
        cornerRadius: 0,
        format: StitchExportFormat.png,
        jpegQuality: 92,
        subtitleOnlyMode: false,
        subtitleBandHeight: kDefaultSubtitleBandHeight,
      );
      final pngBytes = await renderer.render(request);
      renderSw.stop();
      // ignore: avoid_print
      print('[stitch] render elapsed: ${renderSw.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print('[stitch] output bytes: ${pngBytes.length}');

      expect(pngBytes, isNotEmpty);
      // Loose CI ceiling — see file header for rationale.
      expect(renderSw.elapsed.inSeconds, lessThan(30));
    });

    test('20 images @ 1920x1080 vertical stitch + JPEG encode', () async {
      // JPEG-encode path is a separate baseline since the encoder is
      // a different cost class than PNG (JPEG quality knobs, no alpha
      // round-trip).
      final synthSw = Stopwatch()..start();
      final imageBytes = List.generate(
        20,
        (i) => syntheticPng(width: 1920, height: 1080, seed: i),
      );
      synthSw.stop();
      // ignore: avoid_print
      print('[stitch-jpeg] synth elapsed: ${synthSw.elapsedMilliseconds} ms');

      final renderSw = Stopwatch()..start();
      const renderer = StitchImageRenderer();
      final request = StitchRenderRequest(
        imageBytes: imageBytes,
        mode: StitchMode.vertical,
        spacing: 0,
        borderWidth: 0,
        borderColorArgb: 0xFF000000,
        cornerRadius: 0,
        format: StitchExportFormat.jpeg,
        jpegQuality: 85,
        subtitleOnlyMode: false,
        subtitleBandHeight: kDefaultSubtitleBandHeight,
      );
      final jpegBytes = await renderer.render(request);
      renderSw.stop();
      // ignore: avoid_print
      print('[stitch-jpeg] render elapsed: ${renderSw.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print('[stitch-jpeg] output bytes: ${jpegBytes.length}');

      expect(jpegBytes, isNotEmpty);
      expect(renderSw.elapsed.inSeconds, lessThan(30));
    });
  });
}
