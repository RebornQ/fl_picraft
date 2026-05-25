import 'package:flutter/material.dart';

/// Basic-tab mode card (普通拼接 / 电影台词).
///
/// Mutually exclusive within the basic-tab card row — one of the two
/// is always selected. The "selected" state is purely visual; the
/// caller drives state via the [onTap] callback (which should bind to
/// [StitchEditorController.selectNormalMode] /
/// `selectMovieSubtitleMode` respectively for atomic emission per PRD
/// §D1).
///
/// Two cosmetic flavors are switched on [variant]:
///
/// * [StitchModeCardVariant.normal] — 3 rectangles stacked vertically
///   with a 1 dp gap, no subtitle band painted
/// * [StitchModeCardVariant.movieSubtitle] — 3 overlapping film frames
///   in a [Stack]; only the top frame is fully visible, and the lower
///   frames peek out below it as thin amber subtitle strips (one strip
///   per hidden frame), evoking a stack of subtitled film stills
class StitchModeCard extends StatelessWidget {
  const StitchModeCard({
    super.key,
    required this.label,
    required this.variant,
    required this.selected,
    required this.onTap,
    this.width = 92,
    this.height = 100,
  });

  final String label;
  final StitchModeCardVariant variant;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final fillColor = selected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainer;
    final outlineColor = selected ? colorScheme.primary : Colors.transparent;
    final illustrationColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final illustrationBorderColor = fillColor;
    final labelColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: outlineColor, width: selected ? 2 : 0),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Center(
                        child: _ModeIllustration(
                          variant: variant,
                          color: illustrationColor,
                          borderColor: illustrationBorderColor,
                        ),
                      ),
                    ),
                    Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cosmetic illustration variant for [StitchModeCard]. Only affects
/// the drawing of the in-card illustration; the caller decides which
/// editor state each variant maps to.
enum StitchModeCardVariant { normal, movieSubtitle }

class _ModeIllustration extends StatelessWidget {
  const _ModeIllustration({
    required this.variant,
    required this.color,
    required this.borderColor,
  });

  final StitchModeCardVariant variant;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    const barWidth = 36.0;
    const barHeight = 12.0;

    if (variant == StitchModeCardVariant.normal) {
      // Normal variant: 3 bars stacked vertically with a 1 dp gap, no
      // subtitle band painted.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _normalBar(width: barWidth, height: barHeight),
          const SizedBox(height: 1),
          _normalBar(width: barWidth, height: barHeight),
          const SizedBox(height: 1),
          _normalBar(width: barWidth, height: barHeight),
        ],
      );
    }

    // Movie-subtitle variant: 3 frames overlapping in a Stack so only
    // the amber subtitle band of each lower frame peeks out below the
    // top frame. Each frame is the same shape as the normal-variant
    // bar (`barWidth × barHeight`) but composed of a top `illustration`
    // body and a bottom `exposeHeight`-tall amber subtitle strip. The
    // top frame is drawn last so it covers the bodies of the lower
    // frames — only their bottom amber strips remain visible.
    //
    // Stack bounding box: `barWidth × (barHeight + 2 × exposeHeight)`
    // ≈ 36 × 20 dp. Centered in the parent Expanded slot.
    const exposeHeight = 8.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Bottom-most frame, offset down by `2 × exposeHeight`. Only
        // its amber strip (bottom `exposeHeight` dp) ends up uncovered.
        Padding(
          padding: const EdgeInsets.only(top: exposeHeight * 2),
          child: _subtitleFrame(
            width: barWidth,
            height: barHeight * 2,
            bandHeight: exposeHeight,
            borderColor: borderColor,
          ),
        ),
        // Middle frame, offset down by `exposeHeight`. Only its amber
        // strip ends up uncovered.
        Padding(
          padding: const EdgeInsets.only(top: exposeHeight),
          child: _subtitleFrame(
            width: barWidth,
            height: barHeight * 2,
            bandHeight: exposeHeight,
            borderColor: borderColor,
          ),
        ),
        // Top frame at the Stack's top edge — drawn last, fully visible.
        _subtitleFrame(
          width: barWidth,
          height: barHeight * 2,
          bandHeight: exposeHeight,
          borderColor: borderColor,
        ),
      ],
    );
  }

  Widget _normalBar({required double width, required double height}) {
    return Container(width: width, height: height, color: color);
  }

  Widget _subtitleFrame({
    required double width,
    required double height,
    required double bandHeight,
    required Color borderColor,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: color,
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
            ),
          ),
          // Container(height: bandHeight, color: Colors.amber.shade100),
        ],
      ),
    );
  }
}
