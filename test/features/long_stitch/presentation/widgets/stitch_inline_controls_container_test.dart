/// Widget tests for [StitchInlineControlsContainer].
///
/// PRD: `.trellis/tasks/05-26-compact`
///
/// The inline panel is driven by
/// [stitchControlsInlineVisibleProvider]:
///
/// * default `false` → panel is collapsed (no [StitchControlsPanel]
///   in the widget tree)
/// * flip to `true` → [StitchControlsPanel] appears with its TabBar
/// * flip back to `false` → panel collapses and the
///   [StitchControlsPanel] is removed
///
/// While expanded the user can switch between the 4 tabs as if the
/// panel were docked the regular way.
library;

import 'dart:typed_data';

import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_inline_controls_container.dart';
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

Widget _harness({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox.shrink()),
            StitchInlineControlsContainer(),
          ],
        ),
      ),
    ),
  );
}

ProviderContainer _makeContainer({List<ImportedImage>? images}) {
  return ProviderContainer(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images ?? [_stub(tag: 'a')]),
    ],
  );
}

void main() {
  group('StitchInlineControlsContainer — visibility', () {
    testWidgets(
      'provider default (false) → StitchControlsPanel is NOT in the tree',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container: container));
        await tester.pumpAndSettle();

        expect(
          container.read(stitchControlsInlineVisibleProvider),
          isFalse,
          reason: 'provider default value should be false',
        );
        expect(find.byType(StitchControlsPanel), findsNothing);
      },
    );

    testWidgets(
      'flip provider to true → StitchControlsPanel mounts; flip back → unmounts',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container: container));
        await tester.pumpAndSettle();

        // Initially hidden.
        expect(find.byType(StitchControlsPanel), findsNothing);

        // Expand.
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            true;
        await tester.pumpAndSettle();

        expect(find.byType(StitchControlsPanel), findsOneWidget);
        // TabBar labels confirm the panel actually rendered inside.
        expect(find.text('基础'), findsOneWidget);
        expect(find.text('边框'), findsOneWidget);
        expect(find.text('圆角 / 间距'), findsOneWidget);

        // Collapse.
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            false;
        await tester.pumpAndSettle();

        expect(find.byType(StitchControlsPanel), findsNothing);
      },
    );
  });

  group('StitchInlineControlsContainer — tab interaction', () {
    testWidgets('while expanded, tapping the "边框" Tab activates that tab', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container: container));
      // Start expanded.
      container.read(stitchControlsInlineVisibleProvider.notifier).state = true;
      await tester.pumpAndSettle();

      // Panel mounted with all tab labels visible.
      expect(find.byType(StitchControlsPanel), findsOneWidget);

      // Pin the "边框" label inside an actual Tab (the basic-tab card
      // labels share some strings but never the "边框" string).
      final borderTab = find.descendant(
        of: find.byType(Tab),
        matching: find.text('边框'),
      );
      expect(borderTab, findsOneWidget);

      await tester.tap(borderTab);
      await tester.pumpAndSettle();

      // After switching tabs the panel is still mounted; the slider
      // label of the border tab body is visible.
      expect(find.byType(StitchControlsPanel), findsOneWidget);
      expect(find.text('边框宽度'), findsOneWidget);
    });
  });

  group('StitchInlineControlsContainer — layout contract', () {
    testWidgets(
      'expanded panel fits within 200dp without RenderFlex overflow',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container: container));
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            true;
        await tester.pumpAndSettle();

        // No exceptions raised during layout — the bounded
        // 200 dp slot must hold the TabBar + TabBarView without
        // a RenderFlex overflow. The LayoutBuilder path inside
        // [StitchControlsPanel] is responsible for picking the
        // `Expanded(TabBarView)` branch under the bounded parent.
        expect(tester.takeException(), isNull);
        expect(find.byType(StitchControlsPanel), findsOneWidget);
      },
    );

    testWidgets(
      'TabBar pinned: only TabBarView slot lives below the TabBar (no outer scroll wraps the TabBar)',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container: container));
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            true;
        await tester.pumpAndSettle();

        // The TabBar must NOT have a SingleChildScrollView ancestor
        // *inside* the container — earlier revisions wrapped the
        // entire panel in a vertical scroll view, which let the
        // TabBar scroll out of view together with the content. The
        // fix moves the scroll wrapper inside each per-Tab body, so
        // the TabBar stays pinned at the top of the container.
        final panel = find.byType(StitchControlsPanel);
        expect(panel, findsOneWidget);

        // No `SingleChildScrollView` should sit between the
        // container and the TabBar — the container wraps the panel
        // directly without an outer scroll view.
        final outerScroll = find.ancestor(
          of: find.byType(TabBar),
          matching: find.descendant(
            of: find.byType(StitchInlineControlsContainer),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(
          outerScroll,
          findsNothing,
          reason:
              'TabBar must NOT be inside a SingleChildScrollView '
              'descendant of StitchInlineControlsContainer — that '
              'would let the TabBar scroll out of view with the '
              'content. Per-Tab bodies own their own scroll views '
              'instead.',
        );
      },
    );
  });
}
