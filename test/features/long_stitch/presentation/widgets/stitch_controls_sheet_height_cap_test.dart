import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guard the height-cap formula for [StitchControlsSheet] after the
/// `05-26-long-stitch-toolbar-tab-redesign` refactor:
/// `max(260, min(screenHeight * 0.30, 400))`.
///
/// The floor / ratio / ceiling were bumped from the legacy
/// `200 / 0.22 / 320` triple to absorb the new TabBar header (~48 dp)
/// plus the tallest tab body (≤ 224 dp). These tests pin the new
/// values so accidental regression (e.g. someone reverts to the
/// legacy triple) trips the assertion.
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
    'mid-tall viewport (800x1100) hits the ratio branch: maxHeight = 1100 * 0.30 = 330',
    (tester) async {
      // 1100 * 0.30 = 330 — above the 260 floor, below the 400 ceiling.
      await setViewportSize(tester, const Size(800, 1100));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(330.0, 0.001));
    },
  );

  testWidgets('compact (360x800) — floor wins because 800 * 0.30 = 240 < 260', (
    tester,
  ) async {
    await setViewportSize(tester, const Size(360, 800));
    final maxHeight = await pumpAndMeasureMaxHeight(tester);
    expect(maxHeight, closeTo(260.0, 0.001));
  });

  testWidgets(
    'tall viewport (800x2000) hits the ceiling branch: maxHeight = 400 (ceiling clamps the ratio)',
    (tester) async {
      // 2000 * 0.30 = 600 -> clamped down to the 400 ceiling.
      await setViewportSize(tester, const Size(800, 2000));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(400.0, 0.001));
    },
  );

  testWidgets(
    'ultra-short (720x412 landscape) hits the floor branch: maxHeight = 260 (floor protects against tiny windows)',
    (tester) async {
      // 412 * 0.30 = 123.6 — well below the 260 floor.
      await setViewportSize(tester, const Size(720, 412));
      final maxHeight = await pumpAndMeasureMaxHeight(tester);
      expect(maxHeight, closeTo(260.0, 0.001));
    },
  );
}
