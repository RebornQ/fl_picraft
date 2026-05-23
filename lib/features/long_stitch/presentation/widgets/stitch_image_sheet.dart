import 'package:flutter/material.dart';

import 'stitch_sheet_grip_handle.dart';
import 'stitch_vertical_image_list.dart';

/// Open the "selected images" sheet on compact viewports.
///
/// The sheet hosts the existing [StitchVerticalImageList] widget —
/// the same widget docked on the right column for expanded / large
/// widths — so the two layouts share one source of truth for image
/// management (add / clear / per-row remove / long-press reorder).
///
/// The sheet height is capped at 70% of the viewport height so the
/// user can still see a strip of the canvas above the sheet. The
/// inner [StitchVerticalImageList] carries its own
/// `ReorderableColumn` scroll position so the list scrolls
/// independently inside the sheet.
///
/// This sheet is invoked from [StitchEditorBottomBar]'s
/// `[🖼 N/20]` chip on compact widths.
Future<void> showStitchImageSheet(BuildContext context) async {
  final screenHeight = MediaQuery.sizeOf(context).height;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheetContext) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.7),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StitchSheetGripHandle(),
            Expanded(child: StitchVerticalImageList()),
          ],
        ),
      );
    },
  );
}
