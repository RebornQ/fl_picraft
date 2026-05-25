import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_controls_panel.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_mode_card.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_orientation_card.dart';
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

ProviderContainer _makeContainer({required List<ImportedImage> images}) {
  return ProviderContainer(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images),
    ],
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: StitchControlsPanel())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Pin assertions to the Tab labels (NOT the basic-tab card labels —
  // those also use the strings "电影台词" / "普通拼接").
  Finder tabLabel(String text) =>
      find.descendant(of: find.byType(Tab), matching: find.text(text));

  group('StitchControlsPanel — Tab structure', () {
    testWidgets('renders 3 tabs by default (no subtitle)', (tester) async {
      final container = _makeContainer(
        images: [
          _stub(tag: 'a'),
          _stub(tag: 'b'),
        ],
      );
      addTearDown(container.dispose);

      await _pumpPanel(tester, container: container);

      expect(tabLabel('基础'), findsOneWidget);
      expect(tabLabel('电影台词'), findsNothing);
      expect(tabLabel('边框'), findsOneWidget);
      expect(tabLabel('圆角 / 间距'), findsOneWidget);
    });

    testWidgets(
      'subtitle Tab is dynamically inserted when subtitleOnlyMode flips on',
      (tester) async {
        final container = _makeContainer(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
          ],
        );
        addTearDown(container.dispose);
        await _pumpPanel(tester, container: container);

        // Initially absent (no subtitle Tab).
        expect(tabLabel('电影台词'), findsNothing);

        container
            .read(stitchEditorControllerProvider.notifier)
            .selectMovieSubtitleMode();
        await tester.pumpAndSettle();

        // Subtitle Tab is now in the TabBar.
        expect(tabLabel('电影台词'), findsOneWidget);

        // Reverting clears the Tab. Toggle back to 普通拼接.
        container
            .read(stitchEditorControllerProvider.notifier)
            .selectNormalMode();
        await tester.pumpAndSettle();

        // Tab gone; basic-tab card still carries the label but that
        // isn't a `Tab` descendant.
        expect(tabLabel('电影台词'), findsNothing);
        expect(
          container.read(stitchEditorControllerProvider).subtitleOnlyMode,
          isFalse,
        );
      },
    );
  });

  group('StitchControlsPanel — basic-tab cards', () {
    testWidgets(
      'renders orientation + normal + subtitle cards in vertical mode',
      (tester) async {
        final container = _makeContainer(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
          ],
        );
        addTearDown(container.dispose);
        await _pumpPanel(tester, container: container);

        // Default mode is vertical — all 3 cards present.
        expect(find.byType(StitchOrientationCard), findsOneWidget);
        expect(find.byType(StitchModeCard), findsNWidgets(2));
        // The card row labels.
        expect(find.text('普通拼接'), findsOneWidget);
        expect(find.text('电影台词'), findsOneWidget);
      },
    );

    testWidgets(
      'hides the 电影台词 card in horizontal mode (only 2 cards render)',
      (tester) async {
        final container = _makeContainer(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
          ],
        );
        addTearDown(container.dispose);
        await _pumpPanel(tester, container: container);

        // Switch to horizontal mode. `setMode` does not touch
        // `subtitleOnlyMode`, but `subtitleOnlyMode` is already false
        // at this point so the renderer's force-clear invariant holds
        // either way (only `toggleOrientation` needs to clear it).
        container
            .read(stitchEditorControllerProvider.notifier)
            .setMode(StitchMode.horizontal);
        await tester.pumpAndSettle();

        // Only orientation + 普通拼接 cards render — 电影台词 hidden.
        expect(find.byType(StitchOrientationCard), findsOneWidget);
        expect(find.byType(StitchModeCard), findsOneWidget);
        expect(find.text('普通拼接'), findsOneWidget);
        // 电影台词 disappears from both the basic-tab card row AND the
        // Tab bar (the dynamic Tab is gated on
        // `subtitleOnlyMode == true`, which can never be true in
        // horizontal mode — toggleOrientation force-clears it).
        expect(find.text('电影台词'), findsNothing);
      },
    );

    testWidgets('tapping 电影台词 card in vertical mode enables subtitle mode', (
      tester,
    ) async {
      final container = _makeContainer(
        images: [
          _stub(tag: 'a'),
          _stub(tag: 'b'),
        ],
      );
      addTearDown(container.dispose);
      await _pumpPanel(tester, container: container);

      // Default is vertical + subtitleOnlyMode=false; the 电影台词
      // card is rendered and tappable. The atomic flip's other arm
      // (horizontal → vertical when `selectMovieSubtitleMode` is
      // invoked programmatically) is covered by
      // `stitch_editor_provider_atomic_setters_test.dart` — that path
      // is no longer reachable via UI because the card is hidden in
      // horizontal mode.
      expect(
        container.read(stitchEditorControllerProvider).mode,
        StitchMode.vertical,
      );

      await tester.tap(find.text('电影台词'));
      await tester.pumpAndSettle();

      final state = container.read(stitchEditorControllerProvider);
      expect(state.subtitleOnlyMode, isTrue);
      expect(state.mode, StitchMode.vertical);
    });

    testWidgets(
      'tapping orientation card while in subtitle mode flips to horizontal AND clears subtitleOnlyMode',
      (tester) async {
        final container = _makeContainer(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
          ],
        );
        addTearDown(container.dispose);
        await _pumpPanel(tester, container: container);

        container
            .read(stitchEditorControllerProvider.notifier)
            .selectMovieSubtitleMode();
        await tester.pumpAndSettle();
        expect(
          container.read(stitchEditorControllerProvider).subtitleOnlyMode,
          isTrue,
        );

        await tester.tap(find.byType(StitchOrientationCard));
        await tester.pumpAndSettle();

        final state = container.read(stitchEditorControllerProvider);
        expect(state.mode, StitchMode.horizontal);
        expect(
          state.subtitleOnlyMode,
          isFalse,
          reason:
              'Switching to horizontal must clear the subtitle flag in the '
              'same emission (PRD §D1).',
        );
      },
    );
  });

  group('StitchControlsPanel — subtitle Tab content', () {
    testWidgets(
      'subtitle Tab body shows band-height slider + auto-trim switch',
      (tester) async {
        final container = _makeContainer(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
          ],
        );
        addTearDown(container.dispose);
        await _pumpPanel(tester, container: container);

        container
            .read(stitchEditorControllerProvider.notifier)
            .selectMovieSubtitleMode();
        await tester.pumpAndSettle();

        // The subtitle Tab is now in the TabBar at index 1; navigate to
        // it via the controller's animateTo by tapping the Tab text. Find
        // the Tab label (text wrapped inside a Tab widget) — there are
        // two "电影台词" texts now (basic-tab card + Tab label). Tap the
        // Tab label specifically by finding it inside a Tab widget.
        final tabFinder = find.descendant(
          of: find.byType(Tab),
          matching: find.text('电影台词'),
        );
        expect(tabFinder, findsOneWidget);
        await tester.tap(tabFinder);
        await tester.pumpAndSettle();

        expect(find.text('字幕高度'), findsOneWidget);
        expect(find.text('自动剪裁黑边'), findsOneWidget);
        expect(find.text('12%'), findsOneWidget);
      },
    );

    testWidgets('auto-trim switch toggles state + shows hint snackbar', (
      tester,
    ) async {
      final container = _makeContainer(
        images: [
          _stub(tag: 'a'),
          _stub(tag: 'b'),
        ],
      );
      addTearDown(container.dispose);
      await _pumpPanel(tester, container: container);

      container
          .read(stitchEditorControllerProvider.notifier)
          .selectMovieSubtitleMode();
      await tester.pumpAndSettle();

      // Navigate to the subtitle Tab.
      await tester.tap(
        find.descendant(of: find.byType(Tab), matching: find.text('电影台词')),
      );
      await tester.pumpAndSettle();

      // Only the auto-trim switch is in the subtitle Tab body.
      final autoTrimSwitch = find.byType(Switch);
      expect(autoTrimSwitch, findsOneWidget);
      await tester.tap(autoTrimSwitch);
      await tester.pumpAndSettle();

      expect(
        container.read(stitchEditorControllerProvider).autoTrimBlackBars,
        isTrue,
      );
      expect(find.text('已开启自动剪裁黑边，请检查预览效果'), findsOneWidget);
    });
  });

  group('StitchControlsPanel — corners/spacing tab', () {
    testWidgets('spacing slider is disabled in vertical subtitle mode', (
      tester,
    ) async {
      final container = _makeContainer(
        images: [
          _stub(tag: 'a'),
          _stub(tag: 'b'),
        ],
      );
      addTearDown(container.dispose);
      await _pumpPanel(tester, container: container);

      container
          .read(stitchEditorControllerProvider.notifier)
          .selectMovieSubtitleMode();
      await tester.pumpAndSettle();

      // Navigate to the 圆角 / 间距 Tab.
      await tester.tap(
        find.descendant(of: find.byType(Tab), matching: find.text('圆角 / 间距')),
      );
      await tester.pumpAndSettle();

      // Hint text is shown.
      expect(find.text('字幕模式下间距由算法控制'), findsOneWidget);

      // The 图片间距 slider has onChanged == null (disabled).
      final spacingLabel = find.text('图片间距');
      expect(spacingLabel, findsOneWidget);

      // The slider is the second Slider widget (圆角 first, 图片间距 second).
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      expect(
        sliders[1].onChanged,
        isNull,
        reason: '图片间距 slider must be disabled in vertical subtitle mode',
      );
    });
  });
}
