import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/grid_editor_provider.dart';
import 'grid_parameter_cards.dart';
import 'grid_type_selector.dart';

/// Reusable controls panel for the grid-split editor.
///
/// Groups the grid-type selector and bento parameter cards. Used in two
/// contexts:
///
/// * compact / medium screen widths — placed in an [Expanded] slot of
///   the height-first body [Column], wrapped in the shared chrome
///   container built by `_buildControlsPanelChrome` (a
///   `surfaceContainerLow` + `outlineVariant` 16 dp rounded slab) with
///   an inner [SingleChildScrollView], so the panel scrolls **inside**
///   its own viewport without dragging the canvas off-screen.
/// * expanded / large screen widths — docked into the side panel next
///   to the canvas inside the same chrome container; see
///   `grid_editor_screen.dart`.
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
        GridTypeSelector(
          value: state.gridType,
          onChanged: notifier.setGridType,
        ),
        const SizedBox(height: 16),
        // PRD ST-C AC6: a "重置裁剪" button restores the drag-select
        // crop to its defaults. Only visible when the user has moved
        // the crop off-default to avoid panel clutter.
        if (state.hasNonDefaultCrop) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('resetCropButton'),
              onPressed: notifier.resetCrop,
              icon: const Icon(Icons.crop_free),
              label: const Text('重置裁剪'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const GridParameterCards(),
      ],
    );
  }
}
