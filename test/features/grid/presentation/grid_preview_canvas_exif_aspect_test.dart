import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 1×1 PNG byte payload — we don't need real pixels here, only a
/// non-empty buffer that Flutter's `Image.memory` accepts without
/// crashing during layout. The geometry under test is driven entirely
/// by the metadata fields on [ImportedImage], not by the bytes.
Uint8List _stubPngBytes() {
  final canvas = img.Image(width: 1, height: 1, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(canvas));
}

/// Simulates the post-bake [ImportedImage] for a 1080×1440 portrait
/// camera shot — the EXIF Orientation was applied during import so
/// `width`/`height` reflect what the user sees on screen (NOT the raw
/// JPEG SOF dimensions of 1440×1080).
ImportedImage _portrait1080x1440() => ImportedImage(
  bytes: _stubPngBytes(),
  width: 1080,
  height: 1440,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 19),
);

Widget _wrap({required Widget child, required ImportedImage source}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => [source]),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          // Square viewport because the default 2×2 grid is square.
          child: SizedBox(width: 320, height: 320, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('GridPreviewCanvas — EXIF-baked portrait layout', () {
    testWidgets('1080×1440 portrait source → preview Image keeps source aspect '
        '(1080/1440 ≈ 0.75), no squish', (tester) async {
      await tester.pumpWidget(
        _wrap(source: _portrait1080x1440(), child: const GridPreviewCanvas()),
      );
      await tester.pumpAndSettle();

      // The canvas wraps the source in a `Positioned(width: imgWidth,
      // height: imgHeight, child: Image.memory(...))` — find that
      // Image and inspect the rendered box. The size of the rendered
      // RenderBox carries the layout-computed width/height we want
      // to assert on (avoiding having to reach into private
      // Positioned widgets).
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(imageFinder);
      final imgWidth = renderBox.size.width;
      final imgHeight = renderBox.size.height;

      // The renderer's invariant: at default offset (0.5, 0.5) and
      // scale 1, the source occupies a Positioned box whose
      // width/height ratio equals the source's width/height ratio.
      // Pre-fix (when ImportedImage carried raw 1440×1080 SOF dims
      // but Flutter rendered the bytes as portrait), this ratio
      // would have come out as 1440/1080 ≈ 1.33 — i.e. the image was
      // sized as landscape while the underlying pixels were
      // portrait, which is exactly the visual squish the user
      // reported.
      final renderedAspect = imgWidth / imgHeight;
      const expectedAspect = 1080.0 / 1440.0; // 0.75
      expect(
        renderedAspect,
        closeTo(expectedAspect, 0.01),
        reason:
            'Preview must layout the source with the same aspect ratio its '
            'metadata claims. A ratio meaningfully greater than 0.75 means '
            'the portrait image is being stretched horizontally — the '
            '1080×1440 squish bug.',
      );
    });

    testWidgets(
      'tall source on a square viewport overflows vertically (height > '
      'viewport height) — confirms cover-fit, not contain-fit',
      (tester) async {
        await tester.pumpWidget(
          _wrap(source: _portrait1080x1440(), child: const GridPreviewCanvas()),
        );
        await tester.pumpAndSettle();

        final renderBox = tester.renderObject<RenderBox>(find.byType(Image));
        // Viewport is 320×320; portrait source filling that viewport
        // via cover-fit places a width-bound 1080-wide crop and lets
        // the 1440-tall image overhang vertically (the canvas clips
        // it). If the image's height came out <= 320 the renderer
        // would be doing contain-fit, which is a different bug — fail
        // loudly.
        expect(
          renderBox.size.height,
          greaterThan(320.0),
          reason:
              'Cover-fit on a portrait source against a square viewport must '
              'leave the image overhanging vertically. A height ≤ viewport '
              'means we silently switched to contain-fit, which would '
              'reintroduce the squish under a different shape.',
        );
        expect(renderBox.size.width, closeTo(320.0, 0.5));
      },
    );
  });
}
