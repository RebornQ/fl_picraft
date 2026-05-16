import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/screens/stitch_editor_screen.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({String tag = 'a'}) {
  return ImportedImage(
    bytes: _validPng(),
    width: 100,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Widget _stitchHarness({List<ImportedImage>? images}) {
  final router = GoRouter(
    initialLocation: '/stitch',
    routes: [
      GoRoute(path: '/stitch', builder: (_, _) => const StitchEditorScreen()),
      GoRoute(path: '/export', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images ?? [_stub(tag: 'a'), _stub(tag: 'b')]),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Sets the physical surface size so the underlying paint engine matches
/// the simulated logical viewport. The stitch editor uses a `Column`
/// with an `Expanded` child, which depends on bounded vertical
/// constraints — overriding `MediaQuery` alone is not enough because
/// the actual paint surface stays at Flutter's default 800×600 (fine
/// for scrollable bodies like home / export, but not here).
Future<void> _setViewportSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('StitchEditorScreen responsive layout', () {
    testWidgets('compact (< 600 dp) docks controls as a bottom sheet', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(400, 1200));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      // Bottom sheet wrapper is present, containing the panel.
      expect(find.byType(StitchControlsSheet), findsOneWidget);
      expect(find.byType(StitchControlsPanel), findsOneWidget);
    });

    testWidgets('medium (>= 600 dp) keeps the bottom sheet layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      expect(find.byType(StitchControlsSheet), findsOneWidget);
      expect(find.byType(StitchControlsPanel), findsOneWidget);
    });

    testWidgets('expanded (>= 840 dp) docks controls as a side panel', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(1024, 800));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      // The bottom-sheet wrapper is gone; only the bare panel is on screen.
      expect(find.byType(StitchControlsSheet), findsNothing);
      expect(find.byType(StitchControlsPanel), findsOneWidget);

      // Layout signal: the panel sits to the RIGHT of the canvas.
      final canvasOrigin = tester.getTopLeft(find.byType(StitchPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(StitchControlsPanel));
      expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));
    });

    testWidgets('large (>= 1200 dp) keeps the side-panel layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(1600, 900));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      expect(find.byType(StitchControlsSheet), findsNothing);
      expect(find.byType(StitchControlsPanel), findsOneWidget);

      final canvasOrigin = tester.getTopLeft(find.byType(StitchPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(StitchControlsPanel));
      expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));
    });

    testWidgets('content fills the container on very wide windows', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(2400, 1080));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      // No outer maxContentWidth cap — canvas + panel widths together
      // should track the viewport width (not lock at 1200 dp).
      final panel = tester.renderObject<RenderBox>(
        find.byType(StitchControlsPanel),
      );
      final canvas = tester.renderObject<RenderBox>(
        find.byType(StitchPreviewCanvas),
      );
      expect(panel.size.width + canvas.size.width, greaterThan(2000));
    });

    testWidgets(
      'side panel respects [380, 480] dp bounds across wide windows',
      (tester) async {
        // 1280 dp: 25% = 320 → clamped UP to 380 dp.
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_stitchHarness());
        await tester.pumpAndSettle();
        var panel = tester.renderObject<RenderBox>(
          find.byType(StitchControlsPanel),
        );
        expect(panel.size.width, 380);

        // 1920 dp: 25% = 480 → exactly the upper bound.
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        panel = tester.renderObject<RenderBox>(
          find.byType(StitchControlsPanel),
        );
        expect(panel.size.width, 480);

        // 2560 dp: 25% = 640 → clamped DOWN to 480 dp.
        tester.view.physicalSize = const Size(2560, 1440);
        await tester.pumpAndSettle();
        panel = tester.renderObject<RenderBox>(
          find.byType(StitchControlsPanel),
        );
        expect(panel.size.width, 480);
      },
    );
  });
}
