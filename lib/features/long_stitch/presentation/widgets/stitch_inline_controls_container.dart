import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/stitch_editor_provider.dart';
import 'stitch_controls_panel.dart';

/// Total height (px) of the expanded inline panel on compact viewports.
///
/// The panel itself adapts to this bounded height via a LayoutBuilder
/// inside [StitchControlsPanel] — the TabBar stays pinned at the top
/// while the `TabBarView` slot absorbs the remaining height with
/// `Expanded`. Each per-Tab body owns its own `SingleChildScrollView`,
/// so content taller than the slot scrolls **inside the active tab**
/// without dragging the TabBar offscreen.
///
/// Why 200 instead of 300:
///
/// * **More canvas, less chrome.** On a 720-dp phone body (e.g. iPhone
///   14 portrait: 844 dp − AppBar 56 − BottomBar 64 − Status 47 ≈
///   677 dp), 200 dp leaves ≥ 470 dp for the canvas when the panel is
///   open versus only ≥ 370 dp at 300 dp. The extra 100 dp materially
///   helps the user preview the stitch while tweaking parameters.
/// * **Scroll is acceptable for parameter rows.** The taller Tabs
///   (基础's horizontal card row, 圆角/间距's dual sliders) remain
///   reachable via a short vertical drag inside the tab body — a
///   familiar gesture for any compact form sheet.
/// * **Visual proportion.** A ~30% body-height panel reads as a
///   companion control surface; ~45% (the 300 dp value) starts to feel
///   like a competing half-modal that crowds the canvas.
const double kStitchInlineControlsHeight = 200;

/// Animation duration for the inline parameter panel show/hide.
///
/// 250 ms matches the MD3 "medium" motion bucket and pairs well with
/// [Curves.easeInOutCubicEmphasized] (PRD §"动画规范").
const Duration kStitchInlineControlsAnimationDuration = Duration(
  milliseconds: 250,
);

/// Compact-only inline parameter panel that lives between the
/// [StitchPreviewCanvas] and the [StitchEditorBottomBar].
///
/// Visibility is driven by [stitchControlsInlineVisibleProvider]; the
/// `[⚙ 参数]` chip in the bottom bar toggles the flag. When the flag
/// flips, this widget animates the panel's height between
/// `0 → kStitchInlineControlsHeight` (and fades in the inner
/// [StitchControlsPanel]) using MD3 emphasized easing.
///
/// Design intent (PRD `05-26-compact`):
///
/// * **Squeezes the canvas, not overlays it.** The parent
///   `Column { Expanded(canvas), StitchInlineControlsContainer }`
///   shrinks the canvas as this widget grows, so the user keeps live
///   visual feedback while adjusting parameters.
/// * **Bare layout chrome.** A top `outlineVariant` divider plus
///   M3 `elevation: 3` and `surface` background visually separate the
///   panel from both the canvas and the bottom bar without competing
///   with the existing [StitchEditorBottomBar] chrome.
/// * **Mounted only when expanded.** The inner panel is built only
///   while the provider is `true`; when hidden the [AnimatedSize]
///   collapses to zero height and the child is replaced by
///   [SizedBox.shrink], so the [TabController] inside
///   [StitchControlsPanel] is released. The next expansion rebuilds
///   it fresh — matches PRD §D3 (no persisted tab) for the same
///   reason the toolbar redesign chose it.
///
/// Only rendered by the compact branch of `_StitchEditorBody`. Medium
/// uses the always-docked [StitchControlsSheet]; expanded / large
/// dock the panel on the right column. Both ignore this widget /
/// provider.
class StitchInlineControlsContainer extends ConsumerWidget {
  const StitchInlineControlsContainer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(stitchControlsInlineVisibleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: AnimatedSize(
        duration: kStitchInlineControlsAnimationDuration,
        curve: Curves.easeInOutCubicEmphasized,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: kStitchInlineControlsAnimationDuration,
          switchInCurve: Curves.easeInOutCubicEmphasized,
          switchOutCurve: Curves.easeInOutCubicEmphasized,
          // Cross-fade between the expanded panel and an empty box so
          // the AnimatedSize transition reads as both "growing" and
          // "fading in", matching the design's slide+fade motion.
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: visible
              ? Material(
                  // ValueKey makes the AnimatedSwitcher treat the
                  // expanded / collapsed states as two distinct children
                  // so the cross-fade fires on toggle (otherwise the
                  // SizedBox.shrink and the Material would share the
                  // default `null` key and skip the transition).
                  key: const ValueKey('stitch-inline-controls-expanded'),
                  elevation: 3,
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: const SizedBox(
                      height: kStitchInlineControlsHeight,
                      child: StitchControlsPanel(),
                    ),
                  ),
                )
              : const SizedBox.shrink(
                  key: ValueKey('stitch-inline-controls-collapsed'),
                ),
        ),
      ),
    );
  }
}
