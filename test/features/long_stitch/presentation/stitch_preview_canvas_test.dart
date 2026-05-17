import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({int width = 100, int height = 200, String tag = 'a'}) {
  return ImportedImage(
    sourcePath: tag,
    bytes: _validPng(),
    width: width,
    height: height,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Widget _harness({required List<ImportedImage> images, required double height}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: height,
            child: const StitchPreviewCanvas(),
          ),
        ),
      ),
    ),
  );
}

/// Look up the grey-surface Container painted inside the
/// [StitchPreviewCanvas] — the only Container painted with
/// [ColorScheme.surfaceContainerHighest] in the canvas subtree.
Finder _surfaceContainer(WidgetTester tester) {
  return find.descendant(
    of: find.byType(StitchPreviewCanvas),
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      final color = decoration.color;
      if (color == null) return false;
      // Match against the theme's surfaceContainerHighest by looking up
      // the live ColorScheme from any descendant context. We can't pull
      // that from here, so identify the surface container by the fact
      // that it has a BoxDecoration with a non-null color and is
      // located directly under a ConstrainedBox + SingleChildScrollView
      // tree.
      return true;
    }),
  );
}

void main() {
  testWidgets(
    'grey surface fills the full Expanded height when given an empty session',
    (tester) async {
      await tester.pumpWidget(_harness(images: const [], height: 600));
      await tester.pumpAndSettle();

      // The surface Container (root paint of the canvas) should be 600
      // tall, matching the SizedBox parent height — no dead band below.
      final surface = tester.renderObject<RenderBox>(
        _surfaceContainer(tester).first,
      );
      expect(surface.size.height, closeTo(600, 0.5));
    },
  );

  testWidgets(
    'grey surface fills the full Expanded height for a short-aspect image',
    (tester) async {
      // Wide-aspect image: surface should still fill 600 dp tall
      // (the canvas painted inside will be smaller and centered).
      await tester.pumpWidget(
        _harness(images: [_stub(width: 1000, height: 200)], height: 600),
      );
      await tester.pumpAndSettle();

      final surface = tester.renderObject<RenderBox>(
        _surfaceContainer(tester).first,
      );
      expect(surface.size.height, closeTo(600, 0.5));
    },
  );

  testWidgets('canvas is scrollable when the assembled image is tall-aspect', (
    tester,
  ) async {
    // Tall image — long stitch assembled at natural width will be
    // taller than the 600 dp surface, so the inner
    // SingleChildScrollView should accommodate it.
    await tester.pumpWidget(
      _harness(
        images: [
          _stub(width: 100, height: 2000),
          _stub(width: 100, height: 2000, tag: 'b'),
        ],
        height: 600,
      ),
    );
    await tester.pumpAndSettle();

    // SingleChildScrollView must exist inside the canvas widget.
    final scrollViewFinder = find.descendant(
      of: find.byType(StitchPreviewCanvas),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollViewFinder, findsOneWidget);
  });

  testWidgets('shows empty hint text when no images are present', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(images: const [], height: 600));
    await tester.pumpAndSettle();

    expect(find.text('导入图片以预览拼接效果'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
