import 'dart:typed_data';

import 'package:fl_picraft/features/export/presentation/widgets/preview_full_screen_dialog.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _smallPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

Widget _thumbnailHarness(Uint8List bytes) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: PreviewThumbnail(bytes: bytes),
      ),
    ),
  );
}

Widget _dialogHarness(Uint8List bytes) {
  return MaterialApp(
    home: Scaffold(body: PreviewFullScreenDialog(bytes: bytes)),
  );
}

void main() {
  group('PreviewFullScreenDialog', () {
    testWidgets('tap on PreviewThumbnail opens the dialog', (tester) async {
      await tester.pumpWidget(_thumbnailHarness(_smallPng()));
      await tester.pumpAndSettle();

      // No dialog at first.
      expect(find.byType(PreviewFullScreenDialog), findsNothing);

      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);
    });

    testWidgets('dialog contains an InteractiveViewer', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.panEnabled, isTrue);
      expect(iv.minScale, 0.5);
      expect(iv.maxScale, 4.0);
    });

    testWidgets(
      'InteractiveViewer.boundaryMargin is infinite so pan is unlimited '
      'after zoom-in',
      (tester) async {
        await tester.pumpWidget(_dialogHarness(_smallPng()));
        await tester.pumpAndSettle();

        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(iv.boundaryMargin, const EdgeInsets.all(double.infinity));
      },
    );

    testWidgets('close button title and tooltip render', (tester) async {
      await tester.pumpWidget(_dialogHarness(_smallPng()));
      await tester.pumpAndSettle();

      expect(find.text('预览'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping the close button pops the dialog', (tester) async {
      await tester.pumpWidget(_thumbnailHarness(_smallPng()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PreviewThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFullScreenDialog), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(PreviewFullScreenDialog), findsNothing);
    });
  });
}
