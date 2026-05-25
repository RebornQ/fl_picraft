import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_editor_state.dart';
import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the atomic setters introduced by
/// `05-26-long-stitch-toolbar-tab-redesign`:
///
/// * `selectMovieSubtitleMode()` — emits `subtitleOnlyMode=true +
///   mode=vertical` in a single state mutation
/// * `selectNormalMode()` — clears `subtitleOnlyMode` while leaving
///   `mode` untouched
/// * `toggleOrientation()` — flips orientation; clears
///   `subtitleOnlyMode` only when entering horizontal
///
/// These run as plain `test`s — no widget tree involved.
void main() {
  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        importedImagesProvider(
          ImageImportSessionKind.stitch,
        ).overrideWith((ref) => const []),
      ],
    );
  }

  group('selectMovieSubtitleMode', () {
    test('horizontal → vertical AND flips subtitle in a single emission', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(stitchEditorControllerProvider.notifier);
      notifier.setMode(StitchMode.horizontal);
      expect(
        container.read(stitchEditorControllerProvider).mode,
        StitchMode.horizontal,
      );

      // Count emissions: the listener should fire exactly once for
      // selectMovieSubtitleMode (not twice — single state mutation).
      var emissions = 0;
      StitchEditorState? lastState;
      container.listen<StitchEditorState>(stitchEditorControllerProvider, (
        _,
        next,
      ) {
        emissions += 1;
        lastState = next;
      });

      notifier.selectMovieSubtitleMode();

      expect(
        emissions,
        1,
        reason: 'selectMovieSubtitleMode must emit exactly once',
      );
      expect(lastState!.subtitleOnlyMode, isTrue);
      expect(lastState!.mode, StitchMode.vertical);
    });

    test('idempotent — no emission when already in target state', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(stitchEditorControllerProvider.notifier);
      notifier.selectMovieSubtitleMode();

      var emissions = 0;
      container.listen<StitchEditorState>(
        stitchEditorControllerProvider,
        (_, _) => emissions += 1,
      );

      notifier.selectMovieSubtitleMode();
      expect(emissions, 0);
    });
  });

  group('selectNormalMode', () {
    test('clears subtitleOnlyMode but leaves mode untouched', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(stitchEditorControllerProvider.notifier);
      notifier.selectMovieSubtitleMode();
      expect(
        container.read(stitchEditorControllerProvider).mode,
        StitchMode.vertical,
      );

      notifier.selectNormalMode();
      final state = container.read(stitchEditorControllerProvider);
      expect(state.subtitleOnlyMode, isFalse);
      expect(state.mode, StitchMode.vertical);
    });
  });

  group('toggleOrientation', () {
    test('vertical → horizontal clears subtitleOnlyMode in one emission', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(stitchEditorControllerProvider.notifier);
      notifier.selectMovieSubtitleMode(); // vertical + subtitle ON

      var emissions = 0;
      StitchEditorState? lastState;
      container.listen<StitchEditorState>(stitchEditorControllerProvider, (
        _,
        next,
      ) {
        emissions += 1;
        lastState = next;
      });

      notifier.toggleOrientation();
      expect(emissions, 1);
      expect(lastState!.mode, StitchMode.horizontal);
      expect(lastState!.subtitleOnlyMode, isFalse);
    });

    test('horizontal → vertical leaves subtitleOnlyMode false', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(stitchEditorControllerProvider.notifier);
      notifier.setMode(StitchMode.horizontal);

      notifier.toggleOrientation();
      final state = container.read(stitchEditorControllerProvider);
      expect(state.mode, StitchMode.vertical);
      expect(state.subtitleOnlyMode, isFalse);
    });
  });
}
