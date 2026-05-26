import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/screens/stitch_editor_screen.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_image_strip.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_inline_controls_container.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart';
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
    // ---- compact (< 600 dp) -----------------------------------------
    //
    // PR-2 of `05-23-mobile-canvas-redesign-for-long-image-stitching`:
    // the compact branch swaps the strip + bottom sheet for a single
    // 3-chip [StitchEditorBottomBar] (mounted in the inner Scaffold's
    // `bottomNavigationBar` slot). The canvas claims the body alone;
    // the strip / sheet are NOT rendered by default — they live in
    // modal sheets surfaced from the bottom bar's chips. The AppBar
    // export IconButton is **retained** on compact (D-4 revised) — it
    // stays the export CTA across compact + medium so users keep the
    // same muscle memory.
    testWidgets('compact (< 600 dp) docks chips in a [StitchEditorBottomBar]; '
        'strip / sheet are gone; canvas fills the body; AppBar keeps export', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(400, 800));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      // Editor bottom bar is the only persistent chrome under the
      // canvas on compact.
      expect(find.byType(StitchEditorBottomBar), findsOneWidget);

      // Old strip + bottom sheet pair is gone — they would compete
      // with the bar for the same vertical space and re-introduce
      // the ~71% screen-eating problem the PRD set out to fix.
      expect(find.byType(StitchImageStrip), findsNothing);
      expect(find.byType(StitchControlsSheet), findsNothing);

      // Side-column vertical list is reserved for expanded / large.
      expect(find.byType(StitchVerticalImageList), findsNothing);

      // Canvas is rendered (and, by virtue of being the sole
      // [Expanded] child of the body Column, claims the available
      // height).
      expect(find.byType(StitchPreviewCanvas), findsOneWidget);

      // PRD `05-26-compact`: the compact body mounts the inline
      // parameter container between the canvas and the bottom bar.
      // The container itself is always mounted (it owns the
      // expand / collapse animation); the inner [StitchControlsPanel]
      // is only added when the user toggles the [⚙ 参数] chip.
      expect(find.byType(StitchInlineControlsContainer), findsOneWidget);
      expect(
        find.byType(StitchControlsPanel),
        findsNothing,
        reason: 'panel defaults to hidden — provider value is false',
      );

      // AppBar export IconButton (Icons.save_outlined, tooltip
      // "导出拼图") IS rendered on compact — the bottom bar
      // hosts only [+ 添加] / [🖼 N/20] / [⚙ 参数] (no export
      // chip), so the AppBar action stays the export CTA across
      // compact + medium for muscle-memory consistency.
      expect(find.byTooltip('导出拼图'), findsOneWidget);

      // FAB is reserved for the side-panel size classes.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets(
      'compact empty state (imageCount == 0) disables [🖼] chip and the '
      'canvas shows the empty hint; AppBar export IconButton is disabled',
      (tester) async {
        await _setViewportSize(tester, const Size(400, 800));
        await tester.pumpWidget(_stitchHarness(images: const []));
        await tester.pumpAndSettle();

        // Canvas falls through to the `_EmptyHint` widget which renders
        // a distinctive prompt — `find.text` matches it via the text
        // contents because `_EmptyHint` is private and can't be
        // matched by type from outside the canvas file.
        expect(find.text('导入图片以预览拼接效果'), findsOneWidget);

        // Bottom bar rendered (with the disabled count chip).
        expect(find.byType(StitchEditorBottomBar), findsOneWidget);

        // Pin the disabled count chip by its visible label.
        // `find.byWidgetPredicate` catches the private subclasses that
        // `find.byType(FilledButton)` misses.
        final imagesChipBtn = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('0/$kMaxImportSessionImages'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(
          imagesChipBtn.onPressed,
          isNull,
          reason: 'image-count chip must be disabled on empty session',
        );

        // AppBar export IconButton is rendered (greyed out): its
        // onPressed should be null when there are no images.
        // `find.byTooltip` matches the Tooltip widget itself; use
        // `find.ancestor` to climb up to the IconButton.
        final exportIconButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('导出拼图'),
            matching: find.byType(IconButton),
          ),
        );
        expect(
          exportIconButton.onPressed,
          isNull,
          reason: 'AppBar export IconButton must be disabled on empty session',
        );
      },
    );

    // ---- medium (>= 600 dp) -----------------------------------------
    //
    // Per PRD R-3 the medium branch is **unchanged** by PR-2: the
    // strip + bottom sheet pair stays, the editor bottom bar does
    // NOT render, and the AppBar IconButton remains the medium CTA.
    testWidgets('medium (>= 600 dp) keeps the strip + controls sheet layout; '
        'no editor bottom bar; AppBar export IconButton is the CTA', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(720, 1200));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      // Compact's new bottom bar is hidden on medium.
      expect(find.byType(StitchEditorBottomBar), findsNothing);

      // Existing medium layout: top strip + canvas + bottom sheet.
      expect(find.byType(StitchImageStrip), findsOneWidget);
      expect(find.byType(StitchControlsSheet), findsOneWidget);
      expect(find.byType(StitchControlsPanel), findsOneWidget);

      // Side-column vertical list still reserved for expanded / large.
      expect(find.byType(StitchVerticalImageList), findsNothing);

      // AppBar export IconButton is the medium-mode CTA — its
      // tooltip "导出拼图" pins it.
      expect(find.byTooltip('导出拼图'), findsOneWidget);

      // FAB only appears on expanded / large.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    // ---- expanded (>= 840 dp) ---------------------------------------
    //
    // Behavior unchanged by PR-2 — keep all existing assertions, plus
    // explicit checks that compact's bottom bar / medium's AppBar
    // IconButton are absent on this size class so the regression net
    // covers every branch.
    testWidgets(
      'expanded (>= 840 dp) docks a vertical list + controls panel in the side column',
      (tester) async {
        await _setViewportSize(tester, const Size(1024, 800));
        await tester.pumpWidget(_stitchHarness());
        await tester.pumpAndSettle();

        // The bottom-sheet wrapper is gone; only the bare panel is on screen.
        expect(find.byType(StitchControlsSheet), findsNothing);
        expect(find.byType(StitchControlsPanel), findsOneWidget);

        // Top horizontal strip is replaced by the side-column vertical list.
        expect(find.byType(StitchImageStrip), findsNothing);
        expect(find.byType(StitchVerticalImageList), findsOneWidget);

        // Compact's bottom bar is NOT mounted on expanded.
        expect(find.byType(StitchEditorBottomBar), findsNothing);
        // Medium's AppBar IconButton is also gone — the FAB is the CTA.
        expect(find.byTooltip('导出拼图'), findsNothing);
        // FAB present (hasImages == true via the harness default).
        expect(find.byType(FloatingActionButton), findsOneWidget);

        // Layout signal: the panel sits to the RIGHT of the canvas.
        final canvasOrigin = tester.getTopLeft(
          find.byType(StitchPreviewCanvas),
        );
        final panelOrigin = tester.getTopLeft(find.byType(StitchControlsPanel));
        expect(panelOrigin.dx, greaterThan(canvasOrigin.dx));

        // And the vertical list sits ABOVE the controls panel inside
        // the side column (both share the same X origin, but list.y < panel.y).
        final listOrigin = tester.getTopLeft(
          find.byType(StitchVerticalImageList),
        );
        expect(listOrigin.dx, equals(panelOrigin.dx));
        expect(listOrigin.dy, lessThan(panelOrigin.dy));
      },
    );

    testWidgets('large (>= 1200 dp) keeps the side-column layout', (
      tester,
    ) async {
      await _setViewportSize(tester, const Size(1600, 900));
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      expect(find.byType(StitchControlsSheet), findsNothing);
      expect(find.byType(StitchControlsPanel), findsOneWidget);
      expect(find.byType(StitchImageStrip), findsNothing);
      expect(find.byType(StitchVerticalImageList), findsOneWidget);
      // Same compact bar / medium IconButton absence checks as expanded.
      expect(find.byType(StitchEditorBottomBar), findsNothing);
      expect(find.byTooltip('导出拼图'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);

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
