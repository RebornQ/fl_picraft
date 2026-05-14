import 'package:flutter/material.dart';

import '../../domain/entities/grid_type.dart';
import 'grid_type_icons.dart';

/// Horizontal scrolling row of 80×80 grid-type cards.
///
/// Mirrors the design mock (`_3_宫格切图/code.html` lines 156–202): each
/// card shows a material symbol preview and the type label (e.g.
/// `3x3`). The active card uses [ColorScheme.primaryContainer] with a
/// primary-colored border; inactive cards use [ColorScheme.surfaceContainerHigh].
///
/// When [lockedTo] is non-null, only that one card is interactive and
/// the others are dimmed — used by the nine-grid-social mode to keep
/// the type fixed to `3x3` (PRD §九宫格朋友圈).
class GridTypeSelector extends StatelessWidget {
  const GridTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.lockedTo,
  });

  final GridType value;
  final ValueChanged<GridType> onChanged;

  /// When non-null, only this grid type's card is tappable. All other
  /// cards are rendered with reduced opacity and consume taps silently.
  final GridType? lockedTo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '宫格类型',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: kGridTypeSelectorOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final type = kGridTypeSelectorOrder[index];
              final isDisabled = lockedTo != null && type != lockedTo;
              return _GridTypeCard(
                key: ValueKey('grid-type-${type.name}'),
                type: type,
                selected: type == value,
                disabled: isDisabled,
                onTap: isDisabled ? null : () => onChanged(type),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GridTypeCard extends StatelessWidget {
  const _GridTypeCard({
    super.key,
    required this.type,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final GridType type;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final bg = selected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    final fg = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final borderColor = selected ? colorScheme.primary : Colors.transparent;

    final card = Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 2 : 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(type.icon, color: fg, size: 28),
              const SizedBox(height: 4),
              Text(
                type.displayLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: !disabled,
      selected: selected,
      enabled: !disabled,
      label: '${type.displayLabel} 宫格',
      child: Opacity(opacity: disabled ? 0.35 : 1, child: card),
    );
  }
}
