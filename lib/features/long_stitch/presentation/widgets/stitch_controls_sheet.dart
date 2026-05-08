import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/entities/stitch_mode.dart';
import '../providers/stitch_editor_provider.dart';
import 'stitch_mode_segmented.dart';

/// Bottom-sticky parameter sheet matching the design mock
/// (`_2_长图拼接/code.html` lines ~196–260):
///
/// * Mode segmented control (vertical / horizontal)
/// * "仅保留字幕" toggle — wires the movie-subtitle flag-overlay
///   (PRD §3.3). Visible only when the active mode is vertical;
///   `onChanged` is `null` (Material auto-greys the switch) when the
///   editor holds fewer than 2 images, since the algorithm degrades to
///   plain vertical anyway.
/// * "字幕高度" slider — visible only when subtitle mode is actually
///   active (toggle on AND vertical AND ≥2 images), per the PRD edge
///   cases.
/// * Spacing / border-width / corner-radius sliders
/// * Border color picker (compact, 6 swatches)
class StitchControlsSheet extends ConsumerWidget {
  const StitchControlsSheet({super.key});

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

    return Material(
      elevation: 8,
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
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
            // is actually rendering bands.
            if (subtitleEffective)
              _SliderRow(
                label: '字幕高度',
                value: state.subtitleBandHeight,
                min: kMinSubtitleBandHeight,
                max: kMaxSubtitleBandHeight,
                valueText: '${state.subtitleBandHeight.round()} px',
                onChanged: notifier.setSubtitleBandHeight,
              ),
            const Divider(height: 24),
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
            Row(
              children: [
                Text(
                  '边框颜色',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                for (final swatch in _borderSwatches)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ColorSwatch(
                      color: swatch,
                      selected: swatch == state.border.color,
                      onTap: () => notifier.setBorderColor(swatch),
                    ),
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

    final bandPx = state.subtitleBandHeight;
    final firstW = state.images.first.width;
    if (firstW <= 0) return;
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
