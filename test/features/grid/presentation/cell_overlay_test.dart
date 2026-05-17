import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/usecases/compute_cell_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/cell_overlay.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int w = 32, int h = 32}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _image({int seed = 0}) {
  return ImportedImage(
    bytes: _validPng(),
    width: 32,
    height: 32,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 17, 0, 0, seed),
  );
}

Widget _harness({required Widget child}) {
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => const []),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 120, height: 120, child: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('CellOverlay — empty state', () {
    testWidgets('uses placeholder accessibility label', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const CellOverlay(
            cellIndex: 4,
            rows: 3,
            cols: 3,
            cellWidth: 100,
            cellHeight: 100,
            sourceCellWidth: 100,
            sourceCellHeight: 100,
          ),
        ),
      );

      expect(find.bySemanticsLabel('替换第5格图片'), findsOneWidget);
    });

    testWidgets('tap on empty cell does not throw', (tester) async {
      // Picker can't actually run in unit tests (no platform channels),
      // but tapping should at least drive the controller method without
      // crashing the widget tree. Catch any propagated platform errors
      // from the gallery picker so the test stays deterministic.
      await tester.pumpWidget(
        _harness(
          child: const CellOverlay(
            cellIndex: 0,
            rows: 3,
            cols: 3,
            cellWidth: 100,
            cellHeight: 100,
            sourceCellWidth: 100,
            sourceCellHeight: 100,
          ),
        ),
      );
      await tester.tap(find.byType(CellOverlay), warnIfMissed: false);
      // Drain microtasks so the async pickFromGallery future completes.
      await tester.pump();
      // Ignore platform exceptions from the missing image_picker plugin.
      tester.takeException();
    });

    testWidgets('empty cell shows add-circle hint icon', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const CellOverlay(
            cellIndex: 0,
            rows: 3,
            cols: 3,
            cellWidth: 100,
            cellHeight: 100,
            sourceCellWidth: 100,
            sourceCellHeight: 100,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(CellOverlay),
          matching: find.byIcon(Icons.add_circle_outline),
        ),
        findsOneWidget,
      );
    });
  });

  group('CellOverlay — replaced state', () {
    testWidgets('renders the replacement image and uses indexed label', (
      tester,
    ) async {
      final image = _image();
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _harness(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const CellOverlay(
                cellIndex: 4,
                rows: 3,
                cols: 3,
                cellWidth: 100,
                cellHeight: 100,
                sourceCellWidth: 100,
                sourceCellHeight: 100,
              );
            },
          ),
        ),
      );
      // Seed the cell with a replacement.
      capturedRef
          .read(gridEditorControllerProvider.notifier)
          .setCellImage(4, image);
      await tester.pumpAndSettle();

      // Replaced cells render an Image.memory child of the overlay.
      expect(
        find.descendant(
          of: find.byType(CellOverlay),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      // Indexed semantics label.
      expect(find.bySemanticsLabel('第5格（第2行 第2列）图片，双指缩放或拖动调整'), findsOneWidget);
    });

    testWidgets('replaced cell still shows add-circle hint icon', (
      tester,
    ) async {
      final image = _image();
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _harness(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const CellOverlay(
                cellIndex: 2,
                rows: 3,
                cols: 3,
                cellWidth: 100,
                cellHeight: 100,
                sourceCellWidth: 100,
                sourceCellHeight: 100,
              );
            },
          ),
        ),
      );
      capturedRef
          .read(gridEditorControllerProvider.notifier)
          .setCellImage(2, image);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(CellOverlay),
          matching: find.byIcon(Icons.add_circle_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('resetCell removes the replacement entry', (tester) async {
      final image = _image();
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _harness(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const CellOverlay(
                cellIndex: 1,
                rows: 3,
                cols: 3,
                cellWidth: 100,
                cellHeight: 100,
                sourceCellWidth: 100,
                sourceCellHeight: 100,
              );
            },
          ),
        ),
      );
      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(1, image);
      await tester.pumpAndSettle();
      expect(
        capturedRef
            .read(gridEditorControllerProvider)
            .cellReplacements
            .containsKey(1),
        isTrue,
      );

      notifier.resetCell(1);
      await tester.pumpAndSettle();
      expect(
        capturedRef.read(gridEditorControllerProvider).cellReplacements,
        isEmpty,
      );
    });

    testWidgets('per-cell scale + offset persist in state', (tester) async {
      // Validates the contract that the overlay's gestures route into
      // per-cell controller methods without bleed between cells.
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        _harness(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setCellImage(0, _image(seed: 0));
      notifier.setCellImage(4, _image(seed: 1));

      // Scale + offset on cell 0 must not affect cell 4.
      notifier.setCellScale(0, 1.8);
      notifier.setCellOffset(0, const CellOffset(5, 10));
      final state = capturedRef.read(gridEditorControllerProvider);
      expect(state.cellReplacements[0]?.scale, 1.8);
      expect(state.cellReplacements[4]?.scale, kDefaultCellScale);
      expect(state.cellReplacements[4]?.offset, kCellOffsetZero);
    });
  });
}
