import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/screens/grid_editor_screen.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_controls_panel.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub() {
  return ImportedImage(
    bytes: _validPng(),
    width: 1024,
    height: 1024,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Widget _gridHarness({List<ImportedImage>? images}) {
  final router = GoRouter(
    initialLocation: '/grid',
    routes: [
      GoRoute(path: '/grid', builder: (_, _) => const GridEditorScreen()),
      GoRoute(path: '/export', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    overrides: [
      importedImagesProvider.overrideWith((ref) => images ?? [_stub()]),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Sets the physical surface size so the underlying paint engine matches
/// the simulated logical viewport. Necessary because the expanded layout
/// uses a `Row` with side-by-side bounded children that the default
/// 800-dp test surface cannot represent at the medium / expanded
/// breakpoints.
Future<void> _setViewportSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('GridEditorScreen responsive layout', () {
    testWidgets(
      'compact (< 600 dp) stacks canvas above the inline controls panel',
      (tester) async {
        await _setViewportSize(tester, const Size(400, 1200));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        expect(find.byType(GridPreviewCanvas), findsOneWidget);
        expect(find.byType(GridControlsPanel), findsOneWidget);

        // Layout signal: panel sits below the canvas in the ListView,
        // so they share the same left edge.
        final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
        final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
        expect(panelOrigin.dx, canvasOrigin.dx);
        expect(panelOrigin.dy, greaterThan(canvasOrigin.dy));
      },
    );

    testWidgets('medium (>= 600 dp) keeps the inline stacked layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      expect(find.byType(GridControlsPanel), findsOneWidget);

      final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
      // Stacked: same left edge, panel below.
      expect(panelOrigin.dx, canvasOrigin.dx);
      expect(panelOrigin.dy, greaterThan(canvasOrigin.dy));
    });

    testWidgets('expanded (>= 840 dp) docks controls as a side panel', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(1024, 800));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      expect(find.byType(GridPreviewCanvas), findsOneWidget);
      expect(find.byType(GridControlsPanel), findsOneWidget);

      // Layout signal: panel sits to the RIGHT of the canvas.
      final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
      expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));
    });

    testWidgets('large (>= 1200 dp) keeps the side-panel layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(1600, 900));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      expect(find.byType(GridControlsPanel), findsOneWidget);

      final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
      expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));
    });

    testWidgets('content is capped by maxContentWidth on very wide windows', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(2400, 1080));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      // The body's outermost ConstrainedBox caps to 1200 dp; canvas +
      // panel widths together must respect that bound.
      final panel = tester.renderObject<RenderBox>(
        find.byType(GridControlsPanel),
      );
      final canvas = tester.renderObject<RenderBox>(
        find.byType(GridPreviewCanvas),
      );
      expect(panel.size.width + canvas.size.width, lessThanOrEqualTo(1200));
    });
  });
}
