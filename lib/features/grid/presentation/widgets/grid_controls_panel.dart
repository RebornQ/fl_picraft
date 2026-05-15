import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/grid_type.dart';
import '../providers/grid_editor_provider.dart';
import 'grid_parameter_cards.dart';
import 'grid_type_selector.dart';

/// Reusable controls panel for the grid-split editor.
///
/// Groups the nine-grid-social toggle, grid-type selector, and bento
/// parameter cards. Used in two contexts:
///
/// * compact / medium screen widths — inlined into the [ListView] that
///   stacks the preview canvas, optional source-size warning, and
///   these controls vertically.
/// * expanded / large screen widths — docked into the side panel next
///   to the canvas; see `grid_editor_screen.dart`.
///
/// The widget watches [gridEditorControllerProvider] itself so callers
/// don't need to thread state through props.
class GridControlsPanel extends ConsumerWidget {
  const GridControlsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NineGridSocialRow(
          enabled: state.nineGridSocialMode,
          onChanged: notifier.setNineGridSocialMode,
        ),
        const SizedBox(height: 16),
        GridTypeSelector(
          value: state.gridType,
          onChanged: notifier.setGridType,
          lockedTo: state.nineGridSocialMode ? GridType.g3x3 : null,
        ),
        const SizedBox(height: 16),
        const GridParameterCards(),
      ],
    );
  }
}

/// Toggle row that flips the [GridEditorState.nineGridSocialMode] flag.
///
/// Promoted to a public widget so it can be reused inside
/// [GridControlsPanel] (and exercised by tests directly). Visual
/// treatment matches `_3_宫格切图/code.html` lines ~144–155 — a tinted
/// `surface-container-low` card with a title, subtitle, and a [Switch].
class NineGridSocialRow extends StatelessWidget {
  const NineGridSocialRow({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '九宫格朋友圈模式',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '开启 3x3 布局并支持中心图片替换',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
