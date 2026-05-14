import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/usecases/compute_center_transform.dart';
import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/center_cell_overlay.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements ImageImportRepository {}

Uint8List _solidColorPng({int width = 64, int height = 64}) {
  final canvas = img.Image(width: width, height: height, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(120, 80, 200, 255));
  return Uint8List.fromList(img.encodePng(canvas));
}

ImportedImage _image(String tag, {int w = 64, int h = 64}) => ImportedImage(
  bytes: _solidColorPng(width: w, height: h),
  width: w,
  height: h,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 14),
);

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
  });

  Widget wrap(Widget child) => ProviderScope(
    overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );

  group('CenterCellOverlay — CTA state', () {
    testWidgets('renders "替换图片" CTA when no center image is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 200,
            height: 200,
            child: CenterCellOverlay(
              cellWidth: 200,
              cellHeight: 200,
              sourceCellWidth: 200,
              sourceCellHeight: 200,
            ),
          ),
        ),
      );

      expect(find.text('替换图片'), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo), findsOneWidget);
    });

    testWidgets('tapping the CTA invokes the image picker repo', (
      tester,
    ) async {
      final picked = _image('center', w: 200, h: 200);
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([picked]));

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                ),
              );
            },
          ),
        ),
      );

      // Activate social mode so the overlay is in the expected state.
      capturedRef
          .read(gridEditorControllerProvider.notifier)
          .setNineGridSocialMode(true);

      await tester.tap(find.text('替换图片'));
      await tester.pumpAndSettle();

      verify(() => repo.pickFromGallery(limit: any(named: 'limit'))).called(1);
      // After successful pick the controller should hold the picked
      // image.
      expect(
        capturedRef.read(gridEditorControllerProvider).centerImage,
        picked,
      );
    });
  });

  group('CenterCellOverlay — scale/offset bounds via gestures', () {
    testWidgets('a scale-up gesture clamps to 2.0', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                ),
              );
            },
          ),
        ),
      );

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('c', w: 200, h: 200));
      // Force an extreme scale request through the controller — the
      // clamp should kick in regardless of how it was reached.
      notifier.setCenterScale(10);
      expect(capturedRef.read(gridEditorControllerProvider).centerScale, 2);
    });

    testWidgets('a scale-down request clamps to 1.0 (cover-fit)', (
      tester,
    ) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                ),
              );
            },
          ),
        ),
      );

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('c'));
      notifier.setCenterScale(0.3);
      expect(
        capturedRef.read(gridEditorControllerProvider).centerScale,
        1,
        reason: 'PRD edge case: 0.5x exposes transparent area → clamps to 1.0',
      );
    });

    testWidgets('offset cannot drag image beyond the cell bounds', (
      tester,
    ) async {
      // 300x300 image, default 256 cell extent at userScale=1.
      // cover = 256/300, effective = 256/300. Scaled = 256.
      // Surplus = 0, so any offset clamps to 0.
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 200,
                  sourceCellHeight: 200,
                ),
              );
            },
          ),
        ),
      );

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('c'));
      // At userScale=1, the cover-fit minimum, surplus is exactly 0 —
      // there's no slack for panning. Any offset request collapses to
      // (0, 0).
      notifier.setCenterOffset(const CenterOffset(500, 500));
      final state = capturedRef.read(gridEditorControllerProvider);
      expect(state.centerOffset, kCenterOffsetZero);
    });
  });

  group('CenterCellOverlay — widget↔source unit conversion', () {
    testWidgets('gesture deltas convert from widget pixels to source pixels '
        'before storage so the preview matches the renderer', (tester) async {
      // The overlay is sized at 200×200 widget pixels but its underlying
      // 5th cell is 100×100 source pixels (a 2:1 widget-to-source scale,
      // simulating a preview canvas that's twice the size of the source).
      // The gesture handler should divide widget-pixel drag deltas by 2
      // before storing the source-pixel offset.
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 100,
                  sourceCellHeight: 100,
                ),
              );
            },
          ),
        ),
      );

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      // 300×300 image; controller's `_currentCenterCellExtent` falls
      // back to 256 source pixels (no source set). userScale = 2.0:
      //   cover  = 256 / 300
      //   effective = cover × 2 ≈ 1.707
      //   scaled = 300 × 1.707 ≈ 512
      //   surplus = 512 − 256 = 256, half = 128 source pixels.
      // So source-pixel offset clamp range is [-128, 128] — wide
      // enough that the test drag won't be clipped, only converted.
      notifier.setCenterImage(_image('c', w: 300, h: 300));
      notifier.setCenterScale(2);

      // Drive a 40-widget-pixel rightward drag. Gesture-slop is a
      // device-detail black box — the recognizer only fires updates
      // after the pointer crosses `kPanSlop` (~18 px). So the
      // *captured* travel is some value `T ∈ (0, 40]` widget pixels,
      // not the full 40. What we verify here is the **conversion
      // contract**: the stored source-pixel offset equals
      // `T * sourcePerWidget = T * 0.5`. We assert the result lives
      // in `(0, 20]`, which only holds if the multiplier was applied
      // — without the fix the stored value would be `T`, which can
      // exceed 20 for any drag above 20 widget pixels.
      await tester.timedDrag(
        find.byType(CenterCellOverlay),
        const Offset(40, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      final stored = capturedRef
          .read(gridEditorControllerProvider)
          .centerOffset;
      expect(
        stored.dx,
        greaterThan(0),
        reason: 'A rightward drag must produce a positive source-pixel offset',
      );
      expect(
        stored.dx,
        lessThanOrEqualTo(20),
        reason:
            'sourcePerWidget = 100/200 = 0.5 — the stored offset must be '
            'at most half the 40-widget-pixel drag; without the conversion '
            'it would equal the raw widget delta',
      );
      expect(stored.dy, 0, reason: 'No vertical drag → no vertical offset');
    });

    testWidgets('preview offset accounts for the widget↔source ratio so the '
        'image sits at the same visible position as the export', (
      tester,
    ) async {
      // Set a known source-pixel offset on the state, then verify the
      // rendered Image.memory inside the overlay is positioned at the
      // widget-pixel equivalent (offset.dx × widgetPerSource).
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              return const SizedBox(
                width: 200,
                height: 200,
                child: CenterCellOverlay(
                  cellWidth: 200,
                  cellHeight: 200,
                  sourceCellWidth: 100,
                  sourceCellHeight: 100,
                ),
              );
            },
          ),
        ),
      );

      final notifier = capturedRef.read(gridEditorControllerProvider.notifier);
      notifier.setNineGridSocialMode(true);
      notifier.setCenterImage(_image('c', w: 300, h: 300));
      notifier.setCenterScale(2);
      // 30 source-pixel offset on a 100-source-pixel cell rendered as
      // a 200-widget-pixel cell → 60 widget-pixel shift in the
      // preview. The clamp at scale=2 / 256-fallback-cell allows
      // ±128 source pixels, so 30 isn't clipped.
      notifier.setCenterOffset(const CenterOffset(30, 0));
      await tester.pumpAndSettle();

      // Read the `Positioned` rect inside the overlay's Stack.
      final positionedFinder = find.descendant(
        of: find.byType(CenterCellOverlay),
        matching: find.byType(Positioned),
      );
      final positioned = tester.widget<Positioned>(positionedFinder.first);
      // cellWidth = 200, image width = 300, cover = max(200/300, 200/300) ≈
      // 0.667, effective = 0.667 × 2 = 1.333, renderedWidth = 300 × 1.333 ≈
      // 400. Center the image: (200 − 400) / 2 = −100. Add offset 30
      // source × widgetPerSource (200/100=2) = 60 widget pixels → left = −40.
      expect(positioned.left, closeTo(-40, 0.5));
    });
  });
}
