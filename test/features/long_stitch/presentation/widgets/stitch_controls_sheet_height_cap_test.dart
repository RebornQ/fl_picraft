import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guard the height-cap formula for [StitchControlsSheet]:
/// `max(200, min(screenHeight * 0.22, 320))`.
///
/// These tests pin the formula to its current values so accidental
/// regression (e.g. someone reverts to `0.28` / `360`) trips the
/// assertion. The ratio / ceiling / floor are tested by sampling
/// representative compact + medium viewport heights via
/// `tester.view.physicalSize` (per the responsive-layout spec — wrapping
/// in `MediaQuery` doesn't override the size that `MaterialApp` then
/// re-injects).
void main() {
  ImportedImage stub({String tag = 'a'}) {
    return ImportedImage(
      bytes: Uint8List.fromList([1, 2, 3, tag.codeUnitAt(0)]),
      width: 100,
      height: 200,
      mimeType: 'image/png',
      importedAt: DateTime(2026, 1, 1),
    );
  }

  Future<void> setViewportSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<double> pumpAndMeasureMaxHeight(WidgetTester tester) async {
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

    final constrainedBox = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(StitchControlsSheet),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    return constrainedBox.constraints.maxHeight;
  }

  testWidgets(
    'mid-tall viewport (800x1000) hits the ratio branch: maxHeight = 1000 * 0.22 = 220',
    (tester) async {
      // 1000 * 0.22 = 220 — above the 200 floor, below the 320 ceiling.
      await setViewportSize(tester, const Size(800, 1000));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(220.0, 0.001));
    },
  );

  testWidgets('compact (360x800) — floor wins because 800 * 0.22 = 176 < 200', (
    tester,
  ) async {
    // Captures the floor-guard behavior on a typical phone viewport.
    // Documents that the PRD-stated "sheet ≤ 176 dp at 360x800" is
    // superseded by the 200 dp floor on this height.
    await setViewportSize(tester, const Size(360, 800));
    final maxHeight = await pumpAndMeasureMaxHeight(tester);
    expect(maxHeight, closeTo(200.0, 0.001));
  });

  testWidgets(
    'tall viewport (800x2000) hits the ceiling branch: maxHeight = 320 (ceiling clamps the ratio)',
    (tester) async {
      // 2000 * 0.22 = 440 -> clamped down to the 320 ceiling.
      await setViewportSize(tester, const Size(800, 2000));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(320.0, 0.001));
    },
  );

  testWidgets(
    'ultra-short (720x412 landscape) hits the floor branch: maxHeight = 200 (floor protects against tiny windows)',
    (tester) async {
      // 412 * 0.22 = 90.64 — well below the 200 floor.
      await setViewportSize(tester, const Size(720, 412));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(200.0, 0.001));
    },
  );
}
