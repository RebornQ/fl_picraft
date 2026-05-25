import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_mode.dart';
import '../providers/stitch_editor_provider.dart';
import 'stitch_mode_card.dart';
import 'stitch_orientation_card.dart';

/// Horizontal card list rendered by the "基础" Tab.
///
/// In vertical mode three cards render in fixed order:
///
/// 1. Orientation card — single, taps flip vertical ⇄ horizontal
/// 2. Normal-stitch card — selected when `subtitleOnlyMode == false`
/// 3. Movie-subtitle card — selected when `subtitleOnlyMode == true`
///
/// In horizontal mode the **movie-subtitle card is hidden**:
/// [StitchEditorController.toggleOrientation] force-clears
/// `subtitleOnlyMode` the moment the orientation flips to horizontal,
/// so the renderer never honors it there. Exposing the card in
/// horizontal would be a misleading affordance — taps would have to
/// silently re-enter vertical, contradicting the orientation the user
/// just chose. The "普通拼接" card stays visible and is naturally
/// selected (`!subtitleOnlyMode == true` in horizontal). The atomic
/// setter `selectMovieSubtitleMode` itself still works programmatically
/// (and is covered by `stitch_editor_provider_atomic_setters_test.dart`);
/// it just loses its UI entry point while horizontal is active.
/// This mirrors the existing guard on the dynamic "电影台词" Tab,
/// which only appears when `subtitleOnlyMode == true` (impossible in
/// horizontal mode).
///
/// Card visuals come from
/// [StitchOrientationCard] / [StitchModeCard]; this widget only owns
/// the row layout (horizontal `ListView`, 92×100 dp slots, 12 dp
/// gap). State wiring routes through the atomic setters
/// (`toggleOrientation` / `selectNormalMode` / `selectMovieSubtitleMode`)
/// so the side-effects from PRD §D1 stay consistent.
class StitchBasicTabCards extends ConsumerWidget {
  const StitchBasicTabCards({super.key});

  static const double _cardHeight = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final showMovieSubtitleCard = state.mode == StitchMode.vertical;

    return SizedBox(
      height: _cardHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          StitchOrientationCard(
            mode: state.mode,
            onTap: notifier.toggleOrientation,
          ),
          const SizedBox(width: 12),
          StitchModeCard(
            label: '普通拼接',
            variant: StitchModeCardVariant.normal,
            selected: !state.subtitleOnlyMode,
            onTap: notifier.selectNormalMode,
          ),
          if (showMovieSubtitleCard) ...[
            const SizedBox(width: 12),
            StitchModeCard(
              label: '电影台词',
              variant: StitchModeCardVariant.movieSubtitle,
              selected: state.subtitleOnlyMode,
              onTap: notifier.selectMovieSubtitleMode,
            ),
          ],
        ],
      ),
    );
  }
}
