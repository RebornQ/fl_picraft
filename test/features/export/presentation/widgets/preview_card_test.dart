import 'dart:typed_data';

import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_card.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_skeleton.dart';
import 'package:fl_picraft/features/export/presentation/widgets/preview_thumbnail.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_preview_canvas.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Stub controller that lets a widget test inject a fixed
/// [PreviewState] without going through the real renderer pipeline.
///
/// Overriding the provider with this stub returns the requested state
/// synchronously from `build()`. The real refresh() impl is replaced
/// with a counter so the "retry" assertion can verify the refresh code
/// path runs without depending on the real renderer.
class _StubPreviewController extends PreviewController {
  _StubPreviewController(this._initial);

  final PreviewState _initial;
  int refreshCallCount = 0;

  @override
  PreviewState build() => _initial;

  @override
  void refresh() {
    refreshCallCount++;
    // Intentionally a no-op aside from counting — bypasses the
    // parent's guard / debounce / isolate plumbing for tests.
  }
}

/// Generates a tiny valid PNG so [Image.memory] doesn't throw at decode.
Uint8List _smallPng({int width = 4, int height = 4, int seed = 0}) {
  final image = img.Image(width: width, height: height);
  // Fill with the seed value so different bytes produce different
  // content (lets us spot the wrong thumbnail in mixed-grid tests).
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, seed & 0xFF, seed & 0xFF, seed & 0xFF, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Widget _harness({
  required PreviewState state,
  ExportSourceKind sourceKind = ExportSourceKind.stitch,
  _StubPreviewController? controller,
  double maxWidth = 600,
}) {
  final stub = controller ?? _StubPreviewController(state);
  return ProviderScope(
    overrides: [
      previewControllerProvider.overrideWith(() => stub),
      currentExportSourceKindProvider.overrideWith((_) => sourceKind),
      // Editor providers need stable empty stubs because
      // PreviewSkeleton's editor-canvas fallback path reads them.
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((_) => const []),
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((_) => const []),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: const PreviewCard(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drive a couple of frames + just enough wall time to clear the
/// 200 ms [AnimatedSwitcher] inside [PreviewCard], **without**
/// calling `pumpAndSettle()` (which hangs because
/// [CircularProgressIndicator] in [PreviewSkeleton] / the
/// pending-image [Image] decode loops are never quiescent).
Future<void> _settleAnimatedSwitcher(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  group('PreviewCard — sealed state dispatch', () {
    testWidgets('PreviewEmpty renders the "没有可预览的图片" empty hint', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(state: const PreviewEmpty()));
      await _settleAnimatedSwitcher(tester);

      expect(find.text('没有可预览的图片'), findsOneWidget);
      expect(find.byType(PreviewThumbnail), findsNothing);
      expect(find.byType(PreviewSkeleton), findsNothing);
    });

    testWidgets(
      'PreviewLoading(staleBytes: null) shows the editor canvas skeleton with the "加载中..." chip',
      (tester) async {
        await tester.pumpWidget(_harness(state: const PreviewLoading()));
        await _settleAnimatedSwitcher(tester);

        expect(find.byType(PreviewSkeleton), findsOneWidget);
        expect(find.text('加载中...'), findsOneWidget);
        // Stitch source kind (default) → stitch canvas fallback.
        expect(find.byType(StitchPreviewCanvas), findsOneWidget);
      },
    );

    testWidgets(
      'PreviewLoading(staleBytes: [bytes]) renders the stale image + "刷新中..." chip',
      (tester) async {
        final stale = _smallPng(seed: 1);
        await tester.pumpWidget(
          _harness(state: PreviewLoading(staleBytes: [stale])),
        );
        await _settleAnimatedSwitcher(tester);

        expect(find.byType(PreviewSkeleton), findsOneWidget);
        expect(find.text('刷新中...'), findsOneWidget);
        // Stale bytes painted via Image.memory.
        expect(find.byType(Image), findsOneWidget);
        // Editor canvas fallback should NOT mount when we have stale.
        expect(find.byType(StitchPreviewCanvas), findsNothing);
      },
    );

    testWidgets(
      'PreviewReady (stitch, single image) shows one PreviewThumbnail',
      (tester) async {
        final bytes = _smallPng();
        await tester.pumpWidget(
          _harness(
            state: PreviewReady(bytes: [bytes], totalSizeBytes: bytes.length),
          ),
        );
        await _settleAnimatedSwitcher(tester);

        expect(find.byType(PreviewThumbnail), findsOneWidget);
        // Single-image path does NOT wrap in a horizontal ListView.
        expect(find.byType(ListView), findsNothing);
      },
    );

    testWidgets(
      'PreviewReady (grid, N images) shows a horizontal ListView with N thumbnails',
      (tester) async {
        final bytes = [
          _smallPng(seed: 1),
          _smallPng(seed: 2),
          _smallPng(seed: 3),
          _smallPng(seed: 4),
        ];
        final total = bytes.fold<int>(0, (a, b) => a + b.length);
        await tester.pumpWidget(
          _harness(
            state: PreviewReady(bytes: bytes, totalSizeBytes: total),
            sourceKind: ExportSourceKind.grid,
            // Wide enough that all 4 square thumbnails (240×240) fit
            // without the ListView.builder lazy-mounting tail items.
            maxWidth: 1200,
          ),
        );
        await _settleAnimatedSwitcher(tester);

        // Horizontal ListView with one thumbnail per cell.
        final lv = tester.widget<ListView>(find.byType(ListView));
        expect(lv.scrollDirection, Axis.horizontal);
        expect(find.byType(PreviewThumbnail), findsNWidgets(bytes.length));
      },
    );

    testWidgets('PreviewReady surfaces the "约 X.X MB" file-size label', (
      tester,
    ) async {
      // Pass a valid PNG (real Image.memory decodes), but pass the
      // *displayed* total size explicitly — the label only reads
      // [PreviewReady.totalSizeBytes], not the actual byte length.
      // 1.5 MB = 1024 * 1024 * 1.5 = 1_572_864.
      const labelBytes = 1572864;
      await tester.pumpWidget(
        _harness(
          state: PreviewReady(bytes: [_smallPng()], totalSizeBytes: labelBytes),
        ),
      );
      await _settleAnimatedSwitcher(tester);

      expect(find.text('约 1.5 MB'), findsOneWidget);
    });

    testWidgets(
      'PreviewError shows error icon + message + retry; retry triggers refresh()',
      (tester) async {
        final stub = _StubPreviewController(
          const PreviewError(message: 'boom'),
        );
        await tester.pumpWidget(
          _harness(
            state: const PreviewError(message: 'boom'),
            controller: stub,
          ),
        );
        await _settleAnimatedSwitcher(tester);

        expect(find.text('预览暂不可用'), findsOneWidget);
        expect(find.text('boom'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // TextButton.icon resolves to a private subclass of TextButton
        // (`_TextButtonWithIcon`), so `find.byType(TextButton)` doesn't
        // match it (strict runtimeType equality). Use a predicate that
        // checks `is TextButton` — see component-guidelines.md →
        // "Gotcha: `TextButton.icon` / `IconButton.icon` 不能用
        // `find.byType(TextButton)` 定位".
        final retry = find.byWidgetPredicate(
          (w) => w is TextButton,
          description: 'TextButton (incl. .icon subclass)',
        );
        expect(retry, findsOneWidget);

        await tester.tap(retry);
        await _settleAnimatedSwitcher(tester);

        expect(stub.refreshCallCount, 1);
      },
    );

    testWidgets(
      'PreviewError with stale bytes renders stale (translucent) behind the overlay',
      (tester) async {
        final stale = _smallPng(seed: 9);
        await tester.pumpWidget(
          _harness(
            state: PreviewError(message: 'boom', staleBytes: [stale]),
          ),
        );
        await _settleAnimatedSwitcher(tester);

        // Error overlay visible.
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        // Stale image renders behind it.
        expect(find.byType(Image), findsOneWidget);
        // Opacity wrapper around the stale image.
        expect(
          find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.5),
          findsOneWidget,
        );
      },
    );
  });

  group('PreviewCard — skeleton fallback dispatches on source kind', () {
    testWidgets('grid source kind → GridPreviewCanvas fallback (no stale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          state: const PreviewLoading(),
          sourceKind: ExportSourceKind.grid,
        ),
      );
      await _settleAnimatedSwitcher(tester);

      expect(find.byType(GridPreviewCanvas), findsOneWidget);
      expect(find.byType(StitchPreviewCanvas), findsNothing);
    });

    testWidgets(
      'stitch source kind → StitchPreviewCanvas fallback (no stale)',
      (tester) async {
        await tester.pumpWidget(_harness(state: const PreviewLoading()));
        await _settleAnimatedSwitcher(tester);

        expect(find.byType(StitchPreviewCanvas), findsOneWidget);
        expect(find.byType(GridPreviewCanvas), findsNothing);
      },
    );
  });

  group('PreviewCard — header chrome', () {
    testWidgets('header shows "预览" title in every state', (tester) async {
      for (final state in <PreviewState>[
        const PreviewEmpty(),
        const PreviewLoading(),
        PreviewReady(bytes: [_smallPng()], totalSizeBytes: 1),
        const PreviewError(message: 'x'),
      ]) {
        await tester.pumpWidget(_harness(state: state));
        await _settleAnimatedSwitcher(tester);
        expect(find.text('预览'), findsOneWidget);
      }
    });

    testWidgets(
      'size label is only rendered in PreviewReady (not in Empty / Loading / Error)',
      (tester) async {
        // Empty.
        await tester.pumpWidget(_harness(state: const PreviewEmpty()));
        await _settleAnimatedSwitcher(tester);
        expect(find.textContaining('MB'), findsNothing);

        // Loading.
        await tester.pumpWidget(_harness(state: const PreviewLoading()));
        await _settleAnimatedSwitcher(tester);
        expect(find.textContaining('MB'), findsNothing);

        // Error.
        await tester.pumpWidget(
          _harness(state: const PreviewError(message: 'x')),
        );
        await _settleAnimatedSwitcher(tester);
        expect(find.textContaining('MB'), findsNothing);
      },
    );
  });
}
