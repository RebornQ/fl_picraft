/// Widget tests for [showStitchParamsSheet].
///
/// PRD: `.trellis/tasks/05-23-mobile-canvas-redesign-for-long-image-stitching`
///
/// The params sheet wraps [StitchControlsPanel] inside a
/// [DraggableScrollableSheet] with three snap stops (0.3 / 0.55
/// / 0.9). The initial child size is 0.55 — guarded so the canvas
/// stays ≥ 40% visible at first opening.
library;

import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_params_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({String tag = 'a'}) {
  return ImportedImage(
    sourcePath: tag,
    bytes: _validPng(),
    width: 100,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Future<void> _pumpSheetOpener(
  WidgetTester tester, {
  required List<ImportedImage> images,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        importedImagesProvider(
          ImageImportSessionKind.stitch,
        ).overrideWith((ref) => images),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showStitchParamsSheet(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showStitchParamsSheet — rendering', () {
    testWidgets('renders StitchControlsPanel inside the sheet', (tester) async {
      await _pumpSheetOpener(tester, images: [_stub(tag: 'a')]);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(StitchControlsPanel), findsOneWidget);
      // Sanity: at least one slider row label rendered.
      expect(find.text('图片间距'), findsOneWidget);
    });

    testWidgets('renders a DraggableScrollableSheet wrapping the panel', (
      tester,
    ) async {
      await _pumpSheetOpener(tester, images: [_stub(tag: 'a')]);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    });
  });

  group('showStitchParamsSheet — sheet sizing', () {
    testWidgets(
      'opens at ~55% of the viewport height (initialChildSize: 0.55)',
      (tester) async {
        // Use a fixed viewport so 55% is a known value.
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpSheetOpener(tester, images: [_stub(tag: 'a')]);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // DraggableScrollableSheet sizes its child to
        // `initialChildSize * viewport.height` ± snap animation.
        // The sheet's outermost render box height should land in
        // the ~440 dp neighborhood (800 * 0.55) at rest.
        final sheetRenderBox = tester.renderObject<RenderBox>(
          find.byType(DraggableScrollableSheet),
        );
        // Allow generous tolerance for snap / safe area insets.
        expect(sheetRenderBox.size.height, lessThan(560));
        expect(sheetRenderBox.size.height, greaterThan(360));
      },
    );
  });
}
