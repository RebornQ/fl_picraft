import 'package:flutter/material.dart';

import '../../domain/entities/stitch_mode.dart';

/// Segmented control matching the bottom-bar pill in the design mock
/// (`_2_长图拼接/code.html` lines 200–203). The active segment is filled
/// with [ColorScheme.primary]; inactive segments are flat with
/// [ColorScheme.onSurfaceVariant] text.
class StitchModeSegmented extends StatelessWidget {
  const StitchModeSegmented({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final StitchMode value;
  final ValueChanged<StitchMode> onChanged;

  static const _modes = StitchMode.values;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final mode in _modes)
            Expanded(
              child: _Segment(
                key: ValueKey('stitch-mode-${mode.name}'),
                label: mode.displayLabel,
                selected: mode == value,
                textStyle: textTheme.labelLarge,
                onTap: () => onChanged(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.textStyle,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fill = selected ? colorScheme.primary : Colors.transparent;
    final fg = selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              label,
              style: textStyle?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
