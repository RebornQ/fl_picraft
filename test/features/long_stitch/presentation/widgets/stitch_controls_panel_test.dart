import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ImportedImage _stub({int width = 100, int height = 200, String tag = 'a'}) {
  return ImportedImage(
    bytes: Uint8List.fromList([1, 2, 3, tag.codeUnitAt(0)]),
    width: width,
    height: height,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Widget _pumpHarness({required List<ImportedImage> images}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: StitchControlsPanel())),
    ),
  );
}

void main() {
  group('StitchControlsPanel — subtitle-mode visibility rules', () {
    testWidgets(
      'when subtitle mode is INACTIVE, spacing slider is visible and trim toggle / band slider are hidden',
      (tester) async {
        await tester.pumpWidget(
          _pumpHarness(
            images: [
              _stub(),
              _stub(tag: 'b'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Default state: vertical + subtitle OFF → subtitle is NOT effective.
        expect(find.text('图片间距'), findsOneWidget);
        expect(find.text('自动剪裁黑边'), findsNothing);
        expect(find.text('字幕高度'), findsNothing);
      },
    );

    testWidgets(
      'when subtitle mode is ACTIVE, spacing slider is hidden and trim toggle / band slider are visible',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            importedImagesProvider(
              ImageImportSessionKind.stitch,
            ).overrideWith((ref) => [_stub(), _stub(tag: 'b')]),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: StitchControlsPanel()),
              ),
            ),
          ),
        );

        container
            .read(stitchEditorControllerProvider.notifier)
            .setSubtitleOnlyMode(true);
        await tester.pumpAndSettle();

        expect(find.text('图片间距'), findsNothing);
        expect(find.text('字幕高度'), findsOneWidget);
        expect(find.text('自动剪裁黑边'), findsOneWidget);
        // Default percent reads as 12%.
        expect(find.text('12%'), findsOneWidget);
      },
    );

    testWidgets(
      'toggling auto-trim flips controller state and shows a hint snackbar',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            importedImagesProvider(
              ImageImportSessionKind.stitch,
            ).overrideWith((ref) => [_stub(), _stub(tag: 'b')]),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: StitchControlsPanel()),
              ),
            ),
          ),
        );

        container
            .read(stitchEditorControllerProvider.notifier)
            .setSubtitleOnlyMode(true);
        await tester.pumpAndSettle();

        // Two switches now visible: subtitle toggle (already ON) and
        // the auto-trim toggle. Tap the auto-trim one (the second).
        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(2));
        await tester.tap(switches.at(1));
        await tester.pumpAndSettle();

        expect(
          container.read(stitchEditorControllerProvider).autoTrimBlackBars,
          isTrue,
        );
        expect(find.text('已开启自动剪裁黑边，请检查预览效果'), findsOneWidget);
      },
    );
  });
}
