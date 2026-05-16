import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/screens/grid_editor_screen.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_controls_panel.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
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
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((ref) => images ?? [_stub()]),
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

        // Vertical ordering signal: panel sits **below** the canvas in
        // the height-first Column skeleton. Horizontal dx values are
        // not asserted here — the canvas is now `Center`-ed inside its
        // Expanded slot, so when the column width exceeds the
        // height-constrained square the canvas shifts inward while the
        // panel keeps the column's left edge.
        final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
        final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
        expect(panelOrigin.dy, greaterThan(canvasOrigin.dy));
      },
    );

    testWidgets(
      'compact body uses height-first Column skeleton (no outer ListView)',
      (tester) async {
        // 360x640 mimics a typical phone portrait viewport — the smallest
        // realistic compact size. The canvas must stay square and visible
        // on the first screen alongside the first controls card without
        // any page-level scroll.
        await _setViewportSize(tester, const Size(360, 640));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        // The body skeleton must NOT be a vertical ListView (the prior
        // skeleton was; the height-first refactor replaced it with a
        // Column). We allow horizontal ListViews because
        // [GridTypeSelector] uses one internally for the type chips.
        final verticalBodyListView = find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.vertical,
        );
        expect(verticalBodyListView, findsNothing);

        // Canvas keeps its 1:1 square shape (within sub-pixel rounding).
        final canvas = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        expect(
          (canvas.size.width - canvas.size.height).abs(),
          lessThan(0.5),
          reason: 'GridPreviewCanvas should render as a square in compact mode',
        );

        // Canvas height must fit within the viewport height (no need to
        // scroll the page to see the canvas in full).
        expect(canvas.size.height, lessThanOrEqualTo(640));

        // Controls panel scrolls internally — a SingleChildScrollView
        // wraps it directly so any overflow stays inside the panel.
        final scrollableAncestors = find.ancestor(
          of: find.byType(GridControlsPanel),
          matching: find.byType(SingleChildScrollView),
        );
        expect(scrollableAncestors, findsOneWidget);

        // No render-flex overflow exception fired during pump.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('medium (>= 600 dp) keeps the inline stacked layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      expect(find.byType(GridControlsPanel), findsOneWidget);

      // Stacked: panel sits below the canvas. The dx values are not
      // strictly equal anymore because the canvas is centered inside an
      // Expanded slot — when the column is wider than the
      // height-constrained square the canvas shifts inward while the
      // panel hugs the column's left edge.
      final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
      final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
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

    testWidgets(
      'expanded (1280×800) keeps canvas square and bounded by viewport height',
      (tester) async {
        // 1280×800: typical tablet-landscape / small desktop window.
        // Available body height ≈ 800 − 56 (AppBar) − 40 (vertical padding)
        // = 704 dp. Left-column width is much wider (≈ 1232 − 16 − 380 =
        // 836 dp), so the height-first square must clamp to the height.
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final canvas = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );

        // Canvas keeps its 1:1 square shape (within sub-pixel rounding).
        expect(
          (canvas.size.width - canvas.size.height).abs(),
          lessThan(0.5),
          reason: 'GridPreviewCanvas should stay square in expanded mode',
        );

        // Canvas height must NOT exceed the viewport's available body
        // height — the prior bug let the canvas grow to the column
        // width, overflowing the viewport. Generous upper bound of
        // 720 keeps the assertion robust to small chrome variations.
        expect(
          canvas.size.height,
          lessThanOrEqualTo(720),
          reason: 'canvas height must fit within the viewport',
        );

        // Side panel stays docked at the right.
        final canvasOrigin = tester.getTopLeft(find.byType(GridPreviewCanvas));
        final panelOrigin = tester.getTopLeft(find.byType(GridControlsPanel));
        expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));

        // No outer vertical overflow.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'large (1920×1080) keeps canvas square and bounded by viewport height',
      (tester) async {
        // 1920×1080: typical desktop full-screen. Body height ≈ 1080 −
        // 56 − 40 = 984 dp; left column width ≈ 1872 − 16 − 468 = 1388
        // dp. Pre-fix the canvas would have grown to 1388×1388 and
        // overflowed the 984 dp tall body. With the height-first
        // skeleton it must clamp to ≤ 984.
        await _setViewportSize(tester, const Size(1920, 1080));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final canvas = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );

        expect(
          (canvas.size.width - canvas.size.height).abs(),
          lessThan(0.5),
          reason: 'GridPreviewCanvas should stay square in large mode',
        );
        expect(
          canvas.size.height,
          lessThanOrEqualTo(1000),
          reason: 'canvas height must fit within the viewport',
        );

        // Side panel stays docked and clamped to the [380, 480] range.
        final panel = tester.renderObject<RenderBox>(
          find.byType(GridControlsPanel),
        );
        expect(panel.size.width, greaterThanOrEqualTo(380));
        expect(panel.size.width, lessThanOrEqualTo(480));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('content fills the container on very wide windows', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(2400, 1080));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      // No outer maxContentWidth cap — the side panel should hug the
      // viewport's right edge (only 16 dp of padding between them),
      // confirming the body tracks the container width rather than
      // locking at 1200 dp. We can't use `canvas.width + panel.width`
      // anymore (the canvas is now height-bounded so its width tops
      // out at ~984 dp on a 1080 px tall window) — instead assert the
      // panel's right edge reaches the right padding boundary.
      final panelPos = tester.getTopLeft(find.byType(GridControlsPanel));
      final panel = tester.renderObject<RenderBox>(
        find.byType(GridControlsPanel),
      );
      expect(panelPos.dx + panel.size.width, greaterThan(2380));
    });

    testWidgets(
      'side panel respects [380, 480] dp bounds across wide windows',
      (tester) async {
        // 1280 dp viewport: inner row width ≈ 1280 - 32 padding - 16
        // gap = 1232; 25% = 308 → clamped UP to 380 dp.
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();
        var panel = tester.renderObject<RenderBox>(
          find.byType(GridControlsPanel),
        );
        expect(panel.size.width, 380);

        // 1920 dp: inner ≈ 1872; 25% = 468 → in bounds, exact value.
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        panel = tester.renderObject<RenderBox>(find.byType(GridControlsPanel));
        expect(panel.size.width, greaterThanOrEqualTo(380));
        expect(panel.size.width, lessThanOrEqualTo(480));

        // 2560 dp: 25% comfortably above 480 → clamped DOWN to 480 dp.
        tester.view.physicalSize = const Size(2560, 1440);
        await tester.pumpAndSettle();
        panel = tester.renderObject<RenderBox>(find.byType(GridControlsPanel));
        expect(panel.size.width, 480);
      },
    );
  });
}
