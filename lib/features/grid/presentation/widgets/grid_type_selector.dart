import 'package:flutter/material.dart';

import '../../domain/entities/grid_type.dart';

/// Horizontal scrolling row of text-only grid-type cards (05-17 Subtask A).
///
/// Each card surfaces the Chinese [GridType.displayTitle] on the first
/// line and a short [GridType.displayDescription] on the second. The
/// active card uses [ColorScheme.primaryContainer] with a 2 px
/// primary-colored border + elevation 2; inactive cards use
/// [ColorScheme.surfaceContainerHigh] with a transparent border.
///
/// When [lockedTo] is non-null, only that one card is interactive and
/// the others are dimmed. Subtask A hides the toggle that flips this
/// flag on, so today every caller passes `null`; the API stays in place
/// for forward compatibility with Subtask B's geometry work.
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
          height: 104,
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
    final titleColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final descColor = selected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
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
          constraints: const BoxConstraints(
            minWidth: 120,
            maxWidth: 140,
            minHeight: 92,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                type.displayDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: descColor),
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
      label: '${type.displayTitle} ${type.displayDescription}',
      child: Opacity(opacity: disabled ? 0.35 : 1, child: card),
    );
  }
}
