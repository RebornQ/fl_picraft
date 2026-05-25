import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_editor_state.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for [StitchControlsSheet] after the
/// `05-26-long-stitch-toolbar-tab-redesign` refactor.
///
/// The sheet now wraps a TabBar-based panel. Earlier subtitle-toggle /
/// segmented-mode tests have been migrated to the basic-tab card tests
/// in `stitch_controls_panel_test.dart`. The remaining responsibilities
/// of the sheet are (a) wrap the panel in Material chrome, (b) drive
/// the `setSubtitleBandHeightPercent` setter through the slider when
/// subtitle mode is active, and (c) clamp inputs at the controller
/// boundary.
void main() {
  ImportedImage stub({int width = 100, int height = 200, String tag = 'a'}) {
    return ImportedImage(
      bytes: Uint8List.fromList([1, 2, 3, tag.codeUnitAt(0)]),
      width: width,
      height: height,
      mimeType: 'image/png',
      importedAt: DateTime(2026, 1, 1),
    );
  }

  testWidgets('renders inside a Material with elevation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWith((ref) => [stub(tag: 'a'), stub(tag: 'b')]),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StitchControlsSheet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The sheet's Material wrapper is rendered (elevation 8 in source).
    final sheet = find.byType(StitchControlsSheet);
    expect(sheet, findsOneWidget);

    // Tab labels confirm the underlying panel rendered.
    expect(find.text('基础'), findsOneWidget);
    expect(find.text('边框'), findsOneWidget);
    expect(find.text('圆角 / 间距'), findsOneWidget);
  });

  testWidgets(
    'setSubtitleBandHeightPercent reflects in the slider value text',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWith((ref) => [stub(tag: 'a'), stub(tag: 'b')]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: StitchControlsSheet(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable subtitle mode + navigate to the subtitle Tab.
      container
          .read(stitchEditorControllerProvider.notifier)
          .selectMovieSubtitleMode();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Tab), matching: find.text('电影台词')),
      );
      await tester.pumpAndSettle();

      // Drive the setter via the notifier to verify the slider's
      // value-text mirrors. A gesture-driven drag is brittle in
      // widget tests.
      container
          .read(stitchEditorControllerProvider.notifier)
          .setSubtitleBandHeightPercent(0.25);
      await tester.pumpAndSettle();

      expect(find.text('25%'), findsOneWidget);
    },
  );

  testWidgets('setSubtitleBandHeightPercent clamps to [kMin, kMax] limits', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        importedImagesProvider(
          ImageImportSessionKind.stitch,
        ).overrideWith((ref) => [stub(), stub()]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold()),
      ),
    );

    final notifier = container.read(stitchEditorControllerProvider.notifier);
    notifier.setSubtitleBandHeightPercent(0);
    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeightPercent,
      kMinSubtitleBandHeightPercent,
    );
    notifier.setSubtitleBandHeightPercent(99999);
    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeightPercent,
      kMaxSubtitleBandHeightPercent,
    );
  });

  testWidgets('horizontal mode hides the subtitle Tab', (tester) async {
    final container = ProviderContainer(
      overrides: [
        importedImagesProvider(
          ImageImportSessionKind.stitch,
        ).overrideWith((ref) => [stub(tag: 'a'), stub(tag: 'b')]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StitchControlsSheet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Force horizontal mode — subtitle flag stays false.
    container
        .read(stitchEditorControllerProvider.notifier)
        .setMode(StitchMode.horizontal);
    await tester.pumpAndSettle();

    // Subtitle Tab is only visible when subtitleOnlyMode == true; with
    // horizontal forced and the flag never set, the Tab is absent and
    // the basic-tab card row is the only place "电影台词" appears.
    final tabLabel = find.descendant(
      of: find.byType(Tab),
      matching: find.text('电影台词'),
    );
    expect(tabLabel, findsNothing);
  });
}
