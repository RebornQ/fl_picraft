import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/entities/stitch_mode.dart';
import '../providers/stitch_editor_provider.dart';
import 'stitch_mode_segmented.dart';

/// Reusable controls panel for the long-stitch editor.
///
/// Carries the same controls historically rendered inside
/// [StitchControlsSheet] (mode segmented, "仅保留字幕" toggle, subtitle
/// band height slider, spacing / border / corner sliders, border color
/// swatches). The compact / medium screen widths wrap this widget in
/// [StitchControlsSheet] (which adds a top-rounded Material elevation)
/// and dock it to the bottom of the editor. The expanded / large
/// widths drop the elevation and dock this panel to the right edge of
/// the canvas instead — see
/// `stitch_editor_screen.dart` for the responsive switch.
///
/// Behavior matches the previous `StitchControlsSheet` exactly:
///
/// * Mode segmented control (vertical / horizontal)
/// * "仅保留字幕" toggle — wires the movie-subtitle flag-overlay
///   (PRD §3.3). Visible only when the active mode is vertical;
///   `onChanged` is `null` (Material auto-greys the switch) when the
///   editor holds fewer than 2 images, since the algorithm degrades to
///   plain vertical anyway.
/// * "字幕高度" slider — visible only when subtitle mode is actually
///   active (toggle on AND vertical AND ≥2 images), per the PRD edge
///   cases. Expressed as a percentage of the first image's scaled
///   height.
/// * "自动剪裁黑边" toggle — only visible when subtitle mode is
///   actually rendering bands. Drives the renderer-side letterbox
///   detection / trim.
/// * "图片间距" slider — hidden while subtitle mode renders bands
///   because the algorithm ignores spacing (bands butt up against each
///   other) and showing a no-op slider was a source of user confusion.
/// * Border-width / corner-radius sliders
/// * Border color picker (compact, 6 swatches)
class StitchControlsPanel extends ConsumerWidget {
  const StitchControlsPanel({super.key});

  static const _borderSwatches = <Color>[
    Colors.black,
    Colors.white,
    Color(0xFF4F378A), // primary
    Color(0xFF625B71), // secondary
    Color(0xFFBA1A1A), // error
    Color(0xFFCBC4D2), // outlineVariant
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final subtitleApplicable = state.mode == StitchMode.vertical;
    final subtitleEffective =
        subtitleApplicable && state.subtitleOnlyMode && state.imageCount >= 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StitchModeSegmented(value: state.mode, onChanged: notifier.setMode),
          const SizedBox(height: 12),
          // Subtitle toggle — hidden when horizontal mode is active
          // (PRD: "When horizontal mode active, the toggle is hidden").
          if (subtitleApplicable)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '仅保留字幕',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Switch(
                  value: state.subtitleOnlyMode,
                  // Disabled (greyed out) when fewer than 2 images
                  // because the algorithm has nothing to overlay.
                  onChanged: state.imageCount >= 2
                      ? (v) => _onToggleSubtitle(context, notifier, state, v)
                      : null,
                ),
              ],
            ),
          // Band-height slider — only meaningful while subtitle mode
          // is actually rendering bands. Expressed as a percentage of
          // the first image's scaled height so it stays meaningful
          // across different source resolutions.
          if (subtitleEffective)
            _SliderRow(
              label: '字幕高度',
              value: state.subtitleBandHeightPercent,
              min: kMinSubtitleBandHeightPercent,
              max: kMaxSubtitleBandHeightPercent,
              valueText: '${(state.subtitleBandHeightPercent * 100).round()}%',
              onChanged: notifier.setSubtitleBandHeightPercent,
            ),
          // Auto-trim toggle — same visibility rules as the band-height
          // slider so the two stay grouped in the subtitle-mode block.
          if (subtitleEffective)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自动剪裁黑边',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Switch(
                  value: state.autoTrimBlackBars,
                  onChanged: (v) => _onToggleAutoTrim(context, notifier, v),
                ),
              ],
            ),
          const Divider(height: 24),
          // Spacing slider — hidden in subtitle mode because the layout
          // algorithm butts bands together and the slider would have
          // no visible effect.
          if (!subtitleEffective)
            _SliderRow(
              label: '图片间距',
              value: state.spacing,
              min: 0,
              max: kMaxStitchSpacing,
              valueText: '${state.spacing.round()} px',
              onChanged: notifier.setSpacing,
            ),
          _SliderRow(
            label: '边框宽度',
            value: state.border.width,
            min: 0,
            max: kMaxStitchBorderWidth,
            valueText: '${state.border.width.round()} px',
            onChanged: notifier.setBorderWidth,
          ),
          const SizedBox(height: 4),
          // Wrap (instead of Row) so the 48×48 a11y-friendly swatch hit
          // areas can flow onto a second line on narrow phones without
          // forcing horizontal overflow. The label rides at the start
          // of the first run so wide screens still show "label · 6
          // swatches" on one line.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '边框颜色',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final swatch in _borderSwatches)
                _ColorSwatch(
                  color: swatch,
                  selected: swatch == state.border.color,
                  onTap: () => notifier.setBorderColor(swatch),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: '圆角',
            value: state.cornerRadius,
            min: 0,
            max: kMaxStitchCornerRadius,
            valueText: '${state.cornerRadius.round()} px',
            onChanged: notifier.setCornerRadius,
          ),
        ],
      ),
    );
  }

  /// Toggle handler that also surfaces the PRD's "image height < band
  /// height" warning via snackbar when the user enables subtitle mode
  /// on a list whose images are too short to fully fill the requested
  /// band.
  void _onToggleSubtitle(
    BuildContext context,
    StitchEditorController notifier,
    StitchEditorState state,
    bool enabled,
  ) {
    notifier.setSubtitleOnlyMode(enabled);
    if (!enabled) return;
    if (state.images.isEmpty) return;

    // Recompute the band height in pixels from the percent — the state
    // field is percent-relative, so the truncation check has to lift
    // the percent into the same scaled space the layout uses.
    final firstW = state.images.first.width;
    final firstH = state.images.first.height;
    if (firstW <= 0 || firstH <= 0) return;
    final bandPx = (firstH * state.subtitleBandHeightPercent).round();
    if (bandPx <= 0) return;
    var anyTruncated = false;
    for (var i = 1; i < state.images.length; i++) {
      final img = state.images[i];
      if (img.width <= 0) continue;
      final scaledHeight = img.height * firstW / img.width;
      if (scaledHeight < bandPx) {
        anyTruncated = true;
        break;
      }
    }
    if (anyTruncated) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('部分图片高度小于字幕条高度，将使用其完整高度')));
    }
  }

  /// Toggle handler for the auto-trim switch. Shows a one-shot hint
  /// snackbar every time the user flips the toggle ON so they know to
  /// double-check the preview — black-bar detection is a heuristic and
  /// can false-positive on dark scenes.
  void _onToggleAutoTrim(
    BuildContext context,
    StitchEditorController notifier,
    bool enabled,
  ) {
    notifier.setAutoTrimBlackBars(enabled);
    if (!enabled) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('已开启自动剪裁黑边，请检查预览效果')));
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                valueText,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 24×24 swatches are below the 48×48 a11y minimum on their own,
    // so we wrap the visible disc in a transparent 48×48 hit area and
    // expose `selected` semantics so screen readers announce the
    // active swatch.
    return Semantics(
      button: true,
      selected: selected,
      label: '边框颜色',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
