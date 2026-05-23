import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/stitch_editor_provider.dart';
import 'stitch_sheet_grip_handle.dart';

/// Open the "add image" action sheet on compact viewports.
///
/// Surfaces three import sources via [ListTile] rows: gallery,
/// clipboard, camera. Tapping any row pops the sheet first (so the
/// async picker / clipboard / camera call doesn't race the close
/// animation) and then delegates to the corresponding controller
/// method on [StitchEditorController].
///
/// The sheet is invoked from [StitchEditorBottomBar]'s `[+ 添加]`
/// chip on compact widths — medium / expanded / large widths keep
/// their existing "添加" affordance inside [StitchImageStrip] /
/// [StitchVerticalImageList] and do NOT use this sheet.
Future<void> showStitchAddActionSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StitchSheetGripHandle(),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('从相册'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref
                    .read(stitchEditorControllerProvider.notifier)
                    .addFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.paste),
              title: const Text('剪贴板粘贴'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref
                    .read(stitchEditorControllerProvider.notifier)
                    .pasteFromClipboard();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref
                    .read(stitchEditorControllerProvider.notifier)
                    .addFromCamera();
              },
            ),
          ],
        ),
      );
    },
  );
}
