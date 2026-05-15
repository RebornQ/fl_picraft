import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_editor_state.dart';
import '../providers/grid_editor_provider.dart';

/// Pair of asymmetric bento-style cards exposing the grid editor's
/// numeric parameters (spacing + corner radius).
///
/// Mirrors `_3_宫格切图/code.html` lines 204–220: a 2-column grid with
/// a tertiary-container "宫格间距" card and a secondary-container "圆角"
/// card. Tapping a card reveals a slider sheet — keeps the bento
/// surface readable while still letting users adjust precisely.
class GridParameterCards extends ConsumerWidget {
  const GridParameterCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _BentoCard(
                icon: Icons.straighten,
                label: '宫格间距',
                value: '${state.spacing.round()} px',
                background: colorScheme.tertiaryContainer,
                foreground: colorScheme.onTertiaryContainer,
                onTap: () => _openSliderSheet(
                  context,
                  title: '宫格间距',
                  value: state.spacing,
                  min: 0,
                  max: kMaxGridSpacing,
                  suffix: 'px',
                  onChanged: notifier.setSpacing,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BentoCard(
                icon: Icons.rounded_corner,
                label: '圆角大小',
                value: '${state.cornerRadius.round()} px',
                background: colorScheme.secondaryContainer,
                foreground: colorScheme.onSecondaryContainer,
                onTap: () => _openSliderSheet(
                  context,
                  title: '圆角大小',
                  value: state.cornerRadius,
                  min: 0,
                  max: kMaxGridCornerRadius,
                  suffix: 'px',
                  onChanged: notifier.setCornerRadius,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openSliderSheet(
    BuildContext context, {
    required String title,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      builder: (sheetContext) {
        return _SliderSheet(
          title: title,
          initial: value,
          min: min,
          max: max,
          suffix: suffix,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _BentoCard extends StatelessWidget {
  const _BentoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      // Read out the parameter the card adjusts plus its current value
      // so screen-reader users can confirm the active setting without
      // opening the slider sheet.
      label: '$label，当前 $value',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 128,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 28, color: foreground),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      value,
                      style: textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderSheet extends StatefulWidget {
  const _SliderSheet({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String title;
  final double initial;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderSheet> createState() => _SliderSheetState();
}

class _SliderSheetState extends State<_SliderSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.clamp(widget.min, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_value.round()} ${widget.suffix}',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _value,
            min: widget.min,
            max: widget.max,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
