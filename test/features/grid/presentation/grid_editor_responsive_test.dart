import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
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

        // Side panel chrome (the docked column) stays clamped to the
        // [380, 480] range. The bare [GridControlsPanel] inside the
        // chrome is 32 dp narrower (16 dp inner padding on each side)
        // so it's not the right anchor for the spec's column-width
        // contract.
        final chrome = tester.renderObject<RenderBox>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        expect(chrome.size.width, greaterThanOrEqualTo(380));
        expect(chrome.size.width, lessThanOrEqualTo(480));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('content fills the container on very wide windows', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(2400, 1080));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      // No outer maxContentWidth cap — the side panel column should
      // hug the viewport's right edge (only 16 dp of body padding
      // between them), confirming the body tracks the container width
      // rather than locking at 1200 dp.
      //
      // We measure the **chrome** (the side column's outer container)
      // rather than the bare [GridControlsPanel] inside it — the chrome
      // **is** the side column now (its 16 dp internal padding sits
      // *inside* the column). The chrome's right edge is what visually
      // touches the body padding boundary.
      final chromePos = tester.getTopLeft(
        find.byKey(kGridControlsPanelChromeKey),
      );
      final chrome = tester.renderObject<RenderBox>(
        find.byKey(kGridControlsPanelChromeKey),
      );
      expect(chromePos.dx + chrome.size.width, greaterThan(2380));
    });

    testWidgets(
      'side panel respects [380, 480] dp bounds across wide windows',
      (tester) async {
        // The "panel" here means the side **column** (the chrome
        // container) — what the panel-width clamp formula actually
        // sizes. The bare [GridControlsPanel] now lives inside the
        // chrome with 16 dp internal padding, so its `RenderBox.size`
        // is smaller than the clamp value. Asserting on the chrome
        // keeps the test aligned with the responsive-layout spec's
        // "side panel width ∈ [380, 480] dp" contract.

        // 1280 dp viewport: inner row width ≈ 1280 - 32 padding - 16
        // gap = 1232; 25% = 308 → clamped UP to 380 dp.
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();
        var chrome = tester.renderObject<RenderBox>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        expect(chrome.size.width, 380);

        // 1920 dp: inner ≈ 1872; 25% = 468 → in bounds, exact value.
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        chrome = tester.renderObject<RenderBox>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        expect(chrome.size.width, greaterThanOrEqualTo(380));
        expect(chrome.size.width, lessThanOrEqualTo(480));

        // 2560 dp: 25% comfortably above 480 → clamped DOWN to 480 dp.
        tester.view.physicalSize = const Size(2560, 1440);
        await tester.pumpAndSettle();
        chrome = tester.renderObject<RenderBox>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        expect(chrome.size.width, 480);
      },
    );

    testWidgets(
      'expanded canvas tracks viewport size changes (no LayoutBuilder short-circuit)',
      (tester) async {
        // 1280×800: body height ≈ 800 − 56 (AppBar) − 40 (vertical
        // padding) = 704 dp; left col width ≈ 1280 − 32 − 16 − 380 =
        // 852 dp. Canvas square = min(852, 704) = 704 (height-bounded).
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();
        final canvasInitial = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        final initialHeight = canvasInitial.size.height;

        // Grow the viewport vertically — body height becomes ≈ 1000 −
        // 56 − 40 = 904 dp; left col width unchanged at 852 dp. Canvas
        // square = min(852, 904) = 852 (now width-bounded). The canvas
        // must follow this change because [LayoutBuilder] rebuilds on
        // every viewport metric update; if a future refactor inserts a
        // widget that caches constraints, this test catches the
        // regression.
        tester.view.physicalSize = const Size(1280, 1000);
        await tester.pumpAndSettle();
        final canvasGrown = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        expect(
          canvasGrown.size.height,
          greaterThan(initialHeight + 50),
          reason:
              'canvas must grow when the viewport gains vertical space '
              'because LayoutBuilder rebuilds on metric changes',
        );

        // Shrink back to the original viewport — canvas height should
        // return to ~initialHeight (within sub-pixel rounding).
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        final canvasReverted = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        expect(
          (canvasReverted.size.height - initialHeight).abs(),
          lessThan(1.0),
          reason:
              'canvas height must return to the original value when the '
              'viewport shrinks back',
        );
      },
    );

    testWidgets('expanded panel chrome fills the row height', (tester) async {
      // 1280×800: body height ≈ 800 − 56 − 40 = 704 dp. The chrome
      // container is stretched to the row's full height by
      // `Row(crossAxisAlignment: stretch)`, so its rendered height
      // should match the body height within Material chrome tolerances.
      await _setViewportSize(tester, const Size(1280, 800));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      final chromeSize = tester.getSize(
        find.byKey(kGridControlsPanelChromeKey),
      );
      // Expected ≈ 704 dp. Tolerance ±8 covers borderline cases where
      // the AppBar / safe-area math differs by a pixel or two across
      // host platforms.
      expect(
        (chromeSize.height - 704).abs(),
        lessThan(8.0),
        reason:
            'chrome should fill the row height (≈ 704 dp on a 800 dp '
            'viewport), actually ${chromeSize.height}',
      );
      // Width matches the clamped panel width.
      expect(chromeSize.width, 380);
    });

    testWidgets(
      'expanded panel chrome uses surfaceContainerLow + outlineVariant decoration',
      (tester) async {
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        // Resolve the active theme via the GridControlsPanel's element
        // so the assertion stays correct even if the harness changes
        // themes in the future.
        final panelContext = tester.element(find.byType(GridControlsPanel));
        final scheme = Theme.of(panelContext).colorScheme;

        final chrome = tester.widget<Container>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        final decoration = chrome.decoration as BoxDecoration;

        expect(decoration.color, scheme.surfaceContainerLow);
        expect(decoration.border, Border.all(color: scheme.outlineVariant));
        expect(decoration.borderRadius, BorderRadius.circular(16));
        expect(chrome.clipBehavior, Clip.antiAlias);
      },
    );

    testWidgets('compact panel chrome follows the 3:2 flex split', (
      tester,
    ) async {
      // 360×900 mimics a typical tall-phone portrait viewport.
      //
      // Per the 05-20 grid-controls-chrome-cap ADR-lite (revised), the
      // compact chrome slot is `Expanded(flex: 2)` and the canvas slot
      // is `Expanded(flex: 3)`. An earlier attempt at
      // `Flexible(loose) + ConstrainedBox(maxHeight: ...)` was reverted
      // because the chrome collapsed to its intrinsic height and a
      // strip of bare page background bled through below it. The 3:2
      // flex split returns ≈ 60 % of the column's remaining height to
      // the canvas while still letting the chrome's background paint
      // edge-to-edge inside its slot.
      //
      // On 360×900: body height ≈ 900 − 56 (AppBar) − 32 (outer Padding
      // 16 top + 16 bottom) = 812 dp. Minus the canvas/chrome 16 dp gap
      // = 796 dp of flex space (the source-size warning is not rendered
      // when the stub image is 1024×1024). chrome ≈ 796 * 2/5 ≈ 318 dp.
      await _setViewportSize(tester, const Size(360, 900));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      final chromeSize = tester.getSize(
        find.byKey(kGridControlsPanelChromeKey),
      );
      final canvasSize = tester.getSize(find.byType(GridPreviewCanvas));

      // canvas : chrome ≈ 3 : 2. The canvas square is also bounded by
      // the column width (≈ 328 dp), so on a tall narrow phone the
      // canvas height is clamped to its width and the ratio assertion
      // below targets `chrome ≈ available * 2/5` against the canvas's
      // **flex-slot height** rather than the canvas square's rendered
      // height. We assert on the flex slot indirectly:
      //   canvas_slot_height = chrome_size_height * 1.5  (3:2)
      // chrome should be ≈ 318 dp on this viewport (±15 dp tolerance
      // for AppBar / safe-area variations across host platforms).
      expect(
        chromeSize.height,
        inInclusiveRange(290, 345),
        reason:
            'compact chrome should be ≈ 318 dp on a 360×900 viewport '
            '(3:2 flex split of ~796 dp). Actually ${chromeSize.height}',
      );

      // Lower bound: the panel still must be tall enough to show the
      // grid-type selector + the first parameter card. A regression
      // that collapses the chrome to ~0 dp would fail this.
      expect(
        chromeSize.height,
        greaterThan(200),
        reason:
            'compact chrome should at least fit the grid-type selector + '
            'first parameter card. Actually ${chromeSize.height}',
      );

      // Canvas is square (height == width) on this viewport because the
      // 328 dp column width is the limiting axis, not the flex slot
      // height. Sanity: canvas height ≈ canvas width.
      expect(
        (canvasSize.width - canvasSize.height).abs(),
        lessThan(0.5),
        reason: 'canvas should be square on a 360-wide viewport',
      );

      // Width = column width = viewport − 32 dp side padding = 328 dp.
      expect((chromeSize.width - 328).abs(), lessThan(1.0));

      // No render-flex overflow exception.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'compact panel chrome shares decoration with expanded variant',
      (tester) async {
        // Decoration is built by `_buildControlsPanelChrome`, shared
        // across all size classes — regressions in one branch are
        // already caught by the expanded decoration test above, but
        // duplicating the assertion at compact width pins down the
        // contract that both branches must render visually identical
        // chrome.
        await _setViewportSize(tester, const Size(360, 900));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final panelContext = tester.element(find.byType(GridControlsPanel));
        final scheme = Theme.of(panelContext).colorScheme;

        final chrome = tester.widget<Container>(
          find.byKey(kGridControlsPanelChromeKey),
        );
        final decoration = chrome.decoration as BoxDecoration;

        expect(decoration.color, scheme.surfaceContainerLow);
        expect(decoration.border, Border.all(color: scheme.outlineVariant));
        expect(decoration.borderRadius, BorderRadius.circular(16));
        expect(chrome.clipBehavior, Clip.antiAlias);
      },
    );

    testWidgets('medium panel chrome follows the 3:2 flex split', (
      tester,
    ) async {
      // 720×1200 medium width (phone landscape / small tablet). Same
      // single-column skeleton as compact; chrome takes ≈ 2/5 of the
      // remaining column height per the 3:2 flex split.
      //
      // body height ≈ 1200 − 56 − 32 = 1112 dp; minus 16 dp gap = 1096
      // dp flex space. chrome ≈ 1096 * 2/5 ≈ 438 dp.
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      final chromeSize = tester.getSize(
        find.byKey(kGridControlsPanelChromeKey),
      );
      // Expected ≈ 438 dp on a 1200 dp viewport. Tolerance ±20 dp for
      // AppBar / safe-area variations + flex-rounding.
      expect(
        chromeSize.height,
        inInclusiveRange(415, 465),
        reason:
            'medium chrome should be ≈ 438 dp on a 720×1200 viewport '
            '(3:2 flex split of ~1096 dp). Actually ${chromeSize.height}',
      );
      expect(chromeSize.height, greaterThan(300));

      // Width = viewport − 32 dp side padding = 688 dp.
      expect((chromeSize.width - 688).abs(), lessThan(1.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'compact canvas claims its 3/5 share of the column (hasSource)',
      (tester) async {
        // Per the 05-20 grid-controls-chrome-cap ADR-lite (revised),
        // the canvas slot is `Expanded(flex: 3)` and the chrome slot
        // is `Expanded(flex: 2)`. This test verifies the canvas slot
        // height is comfortably larger than the chrome height — a
        // regression that flipped the flex back to 1:1 (the original
        // bug) would shrink the canvas closer to the chrome's size.
        //
        // On 360×900: column flex space ≈ 796 dp. canvas_slot ≈ 478 dp
        // (3/5). The canvas square is then `min(column_width, slot_h)
        // = min(328, 478) = 328` — width-bounded. We assert the
        // canvas's rendered height ≥ 320 dp (close to the column
        // width).
        await _setViewportSize(tester, const Size(360, 900));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final canvas = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        final chromeSize = tester.getSize(
          find.byKey(kGridControlsPanelChromeKey),
        );

        expect(
          canvas.size.height,
          greaterThan(320),
          reason:
              'canvas should claim its 3/5 share of the column; height = '
              '${canvas.size.height}, chrome = ${chromeSize.height}',
        );

        // canvas slot : chrome ≈ 3 : 2 → the chrome height should be
        // ≈ canvas_slot * 2/3. Because the canvas is width-bounded
        // (square of width 328 dp), the canvas's rendered height does
        // NOT reflect its slot height — but the chrome's height does
        // reflect the chrome's slot. We instead assert chrome height
        // is ≈ 318 dp (already covered by the "follows the 3:2 flex
        // split" test); here we just verify the canvas isn't being
        // starved.
        expect(canvas.size.height, greaterThanOrEqualTo(chromeSize.height));

        // The outer Padding's bottom inset must stay at 16 dp (FAB
        // clearance lives inside the chrome's scrollview). A regression
        // that restores a 96 dp outer-Padding bottom inset would push
        // the chrome up ~80 dp and leak page background below it.
        final outerPadding = tester
            .widgetList<Padding>(
              find.descendant(
                of: find.byType(GridEditorScreen),
                matching: find.byType(Padding),
              ),
            )
            .firstWhere(
              (p) =>
                  p.padding == const EdgeInsets.fromLTRB(16, 16, 16, 16) ||
                  p.padding == const EdgeInsets.fromLTRB(16, 16, 16, 96),
              orElse: () => const Padding(padding: EdgeInsets.zero),
            );
        expect(
          outerPadding.padding,
          const EdgeInsets.fromLTRB(16, 16, 16, 16),
          reason:
              'outer body Padding bottom must stay 16 dp — FAB clearance '
              'belongs inside the chrome\'s scrollview, not the outer pad.',
        );
      },
    );

    testWidgets(
      'compact canvas claims its 3/5 share of the column (no source)',
      (tester) async {
        // Without a source image (`hasSource == false`), the FAB is
        // hidden and the chrome's scrollview bottom padding shrinks
        // to 16 dp. The canvas still claims its 3/5 flex share — same
        // contract as the hasSource case.
        await _setViewportSize(tester, const Size(360, 900));
        await tester.pumpWidget(_gridHarness(images: const []));
        await tester.pumpAndSettle();

        final canvas = tester.renderObject<RenderBox>(
          find.byType(GridPreviewCanvas),
        );
        expect(
          canvas.size.height,
          greaterThan(320),
          reason:
              'canvas should claim its 3/5 share of the column even when '
              'the FAB is hidden; height = ${canvas.size.height}',
        );
      },
    );

    testWidgets('medium canvas claims its 3/5 share of the column', (
      tester,
    ) async {
      // Same contract at medium width (720×1200). canvas slot ≈ 658 dp
      // (3/5 of ~1096 dp). On 720 dp wide canvas is bounded by slot
      // height (≈ 658) and by width (688 minus its own padding); the
      // square ends up ≈ min(688, 658) = 658 dp. We assert > 500 dp
      // to give a comfortable lower bound.
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      final canvas = tester.renderObject<RenderBox>(
        find.byType(GridPreviewCanvas),
      );
      expect(
        canvas.size.height,
        greaterThan(500),
        reason:
            'medium canvas should claim its 3/5 share of the column; '
            'height = ${canvas.size.height}',
      );
    });

    testWidgets(
      'compact scrollview bottom padding is 80 dp when FAB is visible',
      (tester) async {
        // FAB clearance lives in the chrome's SingleChildScrollView
        // internal padding (not the outer Padding) so the chrome's
        // background fills the slot's bottom edge while the scrollable
        // content still stops 80 dp above the chrome bottom — enough
        // to keep the last GridParameterCards bento card clear of the
        // floating FAB.
        await _setViewportSize(tester, const Size(360, 900));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final scrollview = tester.widget<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(kGridControlsPanelChromeKey),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final padding = scrollview.padding as EdgeInsets;
        expect(
          padding.bottom,
          80,
          reason:
              'scrollview bottom padding should be 80 dp when the FAB is '
              'visible (hasSource == true), got ${padding.bottom}',
        );
        // Symmetry on the other three sides — the inner 16 dp padding
        // wrapping the controls is unchanged.
        expect(padding.left, 16);
        expect(padding.top, 16);
        expect(padding.right, 16);
      },
    );

    testWidgets(
      'compact scrollview bottom padding is 16 dp when FAB is hidden',
      (tester) async {
        // No source image → FAB hidden → scrollview reverts to a
        // symmetric 16 dp internal padding.
        await _setViewportSize(tester, const Size(360, 900));
        await tester.pumpWidget(_gridHarness(images: const []));
        await tester.pumpAndSettle();

        final scrollview = tester.widget<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(kGridControlsPanelChromeKey),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final padding = scrollview.padding as EdgeInsets;
        expect(padding.bottom, 16);
        expect(padding.left, 16);
        expect(padding.top, 16);
        expect(padding.right, 16);
      },
    );

    testWidgets(
      'expanded scrollview bottom padding stays 16 dp (side panel branch)',
      (tester) async {
        // Side-panel branch: the FAB floats over the canvas column,
        // not the docked panel, so the panel's scrollview uses the
        // default 16 dp regardless of hasSource.
        await _setViewportSize(tester, const Size(1280, 800));
        await tester.pumpWidget(_gridHarness());
        await tester.pumpAndSettle();

        final scrollview = tester.widget<SingleChildScrollView>(
          find.descendant(
            of: find.byKey(kGridControlsPanelChromeKey),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        final padding = scrollview.padding as EdgeInsets;
        expect(padding.bottom, 16);
        expect(padding.top, 16);
      },
    );

    testWidgets('canvas AspectRatio tracks the active GridType (cols / rows)', (
      tester,
    ) async {
      // 05-17 Subtask B contract: the canvas wrapper uses
      // `AspectRatio(cols / rows)`, NOT a hard-coded 1.0.
      await _setViewportSize(tester, const Size(400, 1200));
      await tester.pumpWidget(_gridHarness());
      await tester.pumpAndSettle();

      // Default grid type is 3x3 → aspect = 1.0.
      var canvasAspect = tester
          .widget<AspectRatio>(
            find.ancestor(
              of: find.byType(GridPreviewCanvas),
              matching: find.byType(AspectRatio),
            ),
          )
          .aspectRatio;
      expect(canvasAspect, 1.0);

      // Switch to 1×3 → aspect = 3.0.
      final element = tester.element(find.byType(GridPreviewCanvas));
      final container = ProviderScope.containerOf(element);
      container
          .read(gridEditorControllerProvider.notifier)
          .setGridType(GridType.g1x3);
      await tester.pumpAndSettle();

      canvasAspect = tester
          .widget<AspectRatio>(
            find.ancestor(
              of: find.byType(GridPreviewCanvas),
              matching: find.byType(AspectRatio),
            ),
          )
          .aspectRatio;
      expect(canvasAspect, 3.0);

      // Switch to 2×3 → aspect = 1.5.
      container
          .read(gridEditorControllerProvider.notifier)
          .setGridType(GridType.g2x3);
      await tester.pumpAndSettle();

      canvasAspect = tester
          .widget<AspectRatio>(
            find.ancestor(
              of: find.byType(GridPreviewCanvas),
              matching: find.byType(AspectRatio),
            ),
          )
          .aspectRatio;
      expect(canvasAspect, 1.5);
    });
  });
}
