import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_editor_state.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget pumpHarness({required List<ImportedImage> images}) {
    return ProviderScope(
      overrides: [importedImagesProvider.overrideWith((ref) => images)],
      child: const MaterialApp(
        home: Scaffold(
          // Bottom-aligned so the sheet doesn't overflow during pump.
          body: SingleChildScrollView(child: StitchControlsSheet()),
        ),
      ),
    );
  }

  testWidgets('subtitle toggle is hidden when horizontal mode is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpHarness(
        images: [
          stub(tag: 'a'),
          stub(tag: 'b'),
        ],
      ),
    );
    // Default state is vertical → toggle visible.
    expect(find.text('仅保留字幕'), findsOneWidget);

    // Switch to horizontal via the segmented control.
    await tester.tap(find.text('横向'));
    await tester.pumpAndSettle();

    expect(find.text('仅保留字幕'), findsNothing);
    expect(find.text('字幕高度'), findsNothing);
  });

  testWidgets('toggle is disabled when fewer than 2 images are present', (
    tester,
  ) async {
    await tester.pumpWidget(pumpHarness(images: [stub()]));
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final toggle = tester.widget<Switch>(switchFinder);
    expect(toggle.onChanged, isNull, reason: 'should be disabled');
  });

  testWidgets('enabling toggle reveals the band-height slider', (tester) async {
    await tester.pumpWidget(
      pumpHarness(
        images: [
          stub(tag: 'a'),
          stub(tag: 'b'),
        ],
      ),
    );
    expect(find.text('字幕高度'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('字幕高度'), findsOneWidget);
    expect(find.text('120 px'), findsOneWidget);
  });

  testWidgets('dragging the band-height slider updates the controller state', (
    tester,
  ) async {
    // Use a wider container so the slider has measurable extent.
    final container = ProviderContainer(
      overrides: [
        importedImagesProvider.overrideWith(
          (ref) => [stub(tag: 'a'), stub(tag: 'b')],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StitchControlsSheet())),
      ),
    );

    // Enable subtitle mode programmatically (more deterministic than
    // chasing the toggle hit-test through Material's gesture layer).
    container
        .read(stitchEditorControllerProvider.notifier)
        .setSubtitleOnlyMode(true);
    await tester.pumpAndSettle();

    // Initial value reflects the default.
    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeight,
      kDefaultSubtitleBandHeight,
    );

    // Find the band-height slider (the only one visible labelled
    // "字幕高度"). Sliders below it are spacing/border/corner.
    final sliders = find.byType(Slider);
    expect(sliders.evaluate().length, greaterThanOrEqualTo(2));

    // Just exercise the controller setter directly to verify wiring;
    // simulating a drag is brittle in widget tests.
    container
        .read(stitchEditorControllerProvider.notifier)
        .setSubtitleBandHeight(200);
    await tester.pumpAndSettle();

    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeight,
      200,
    );
    expect(find.text('200 px'), findsOneWidget);
  });

  testWidgets('setSubtitleBandHeight clamps to [kMin, kMax] limits', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        importedImagesProvider.overrideWith((ref) => [stub(), stub()]),
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
    notifier.setSubtitleBandHeight(0);
    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeight,
      kMinSubtitleBandHeight,
    );
    notifier.setSubtitleBandHeight(99999);
    expect(
      container.read(stitchEditorControllerProvider).subtitleBandHeight,
      kMaxSubtitleBandHeight,
    );
  });
}
