import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/export_format.dart';
import '../../domain/entities/export_quality.dart';
import '../providers/export_controller.dart';

/// Card containing the format picker (JPG / PNG segmented buttons)
/// and the quality slider.
///
/// Mirrors the layout in
/// `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`
/// lines 145–167:
///
/// * Section header "格式与质量"
/// * Two-column segmented button row
/// * Quality slider with "最小体积" / "最高质量" endpoint labels and
///   percentage readout, hidden when the active format is PNG
///   (lossless).
class FormatQualityCard extends ConsumerWidget {
  const FormatQualityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final notifier = ref.read(exportControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '格式与质量',
          style: textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _FormatButton(
                format: ExportFormat.jpg,
                selected: state.format == ExportFormat.jpg,
                onTap: () => notifier.setFormat(ExportFormat.jpg),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FormatButton(
                format: ExportFormat.png,
                selected: state.format == ExportFormat.png,
                onTap: () => notifier.setFormat(ExportFormat.png),
              ),
            ),
          ],
        ),
        // Hide the quality slider when PNG is selected (lossless ⇒
        // no quality knob). The PRD calls this out explicitly:
        // "PNG hides the quality slider".
        if (state.format.supportsQuality) ...[
          const SizedBox(height: 16),
          _QualitySlider(value: state.quality, onChanged: notifier.setQuality),
        ],
      ],
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Selected state uses `primary` + `onPrimary` (white foreground on
    // the brand purple fill) to match the recipe used by
    // `StitchModeSegmented` — guarantees WCAG AA contrast on both the
    // light and the seed-derived dark scheme. The earlier
    // `primaryContainer` + `primary` pairing produced a "purple-on-
    // purple" combination because this project's `primaryContainer`
    // token is a mid-saturation purple (see `app_colors.dart`), not
    // the light tint Material 3 normally ships.
    final fg = selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Export format ${format.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : colorScheme.surface,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                format == ExportFormat.jpg
                    ? Icons.image
                    : Icons.photo_library_outlined,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text(
                format.label,
                style: textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualitySlider extends StatelessWidget {
  const _QualitySlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '质量',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '$value%',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(
            kMinExportQuality.toDouble(),
            kMaxExportQuality.toDouble(),
          ),
          min: kMinExportQuality.toDouble(),
          max: kMaxExportQuality.toDouble(),
          divisions: kMaxExportQuality - kMinExportQuality,
          onChanged: (v) => onChanged(v.round()),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '最小体积',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '最高质量',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
