import 'package:flutter/material.dart';

import 'stitch_controls_panel.dart';
import 'stitch_sheet_grip_handle.dart';

/// Open the parameter sheet on compact viewports.
///
/// Wraps [StitchControlsPanel] inside a [DraggableScrollableSheet]
/// with three snap stops:
///
/// * `0.3` — minimal preview-friendly height (≥ 70% canvas visible)
/// * `0.55` — default initial height (≈ 40% canvas still visible)
/// * `0.9` — maxed-out height for adjusting many parameters at once
///
/// The panel itself is the same widget docked on the right column
/// for expanded / large widths — this sheet is the compact-viewport
/// form, invoked from [StitchEditorBottomBar]'s `[⚙ 参数]` chip.
///
/// `backgroundColor: Colors.transparent` on the modal sheet lets the
/// inner `Material` (with top-rounded corners) own the visible
/// chrome — required so `DraggableScrollableSheet` can resize without
/// the host modal painting a competing background underneath.
Future<void> showStitchParamsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        snap: true,
        snapSizes: const [0.3, 0.55, 0.9],
        expand: false,
        builder: (ctx, scrollController) {
          return Material(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              controller: scrollController,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StitchSheetGripHandle(),
                  StitchControlsPanel(),
                  // Bottom breathing room so the last slider's value
                  // chip never sits against the system inset / sheet
                  // edge when the user expands to maxChildSize.
                  SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
