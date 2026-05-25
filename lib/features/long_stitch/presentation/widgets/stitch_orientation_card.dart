import 'package:flutter/material.dart';

import '../../domain/entities/stitch_mode.dart';

/// Basic-tab orientation toggle card (vertical ⇄ horizontal).
///
/// Single card with no "selected" highlight — it represents a *state
/// toggle*, not a member of a mutually-exclusive group. Tapping flips
/// the active [StitchMode]; the caller is expected to wire `onTap` to
/// [StitchEditorController.toggleOrientation] so the subtitle flag
/// side-effect (cleared when entering horizontal) stays in lock-step
/// with the basic-tab semantics (PRD §D1).
///
/// Visual is drawn with bare Flutter shapes (rounded rectangles) so the
/// card carries no asset dependency — matching the "no new asset"
/// constraint from PRD's Decision Log.
class StitchOrientationCard extends StatelessWidget {
  const StitchOrientationCard({
    super.key,
    required this.mode,
    required this.onTap,
    this.width = 92,
    this.height = 100,
  });

  /// Active orientation — drives the illustration + caption.
  final StitchMode mode;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isVertical = mode == StitchMode.vertical;
    final caption = isVertical ? '竖向' : '横向';

    return Semantics(
      button: true,
      label: '切换方向，当前$caption',
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Center(
                      child: _OrientationIllustration(
                        isVertical: isVertical,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        caption,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrientationIllustration extends StatelessWidget {
  const _OrientationIllustration({
    required this.isVertical,
    required this.color,
  });

  final bool isVertical;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (isVertical) {
      // Three small stacked rectangles, top-to-bottom.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Icon(Icons.vertical_distribute_outlined, size: 28)],
      );
    }
    // Three small rectangles laid out left-to-right.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [Icon(Icons.horizontal_distribute_outlined, size: 28)],
    );
  }
}
