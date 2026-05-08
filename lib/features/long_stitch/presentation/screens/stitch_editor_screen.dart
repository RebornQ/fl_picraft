import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/stitch_editor_provider.dart';
import '../widgets/stitch_controls_sheet.dart';
import '../widgets/stitch_image_strip.dart';
import '../widgets/stitch_preview_canvas.dart';

/// Long-stitch editor screen.
///
/// Layout (top → bottom):
/// 1. AppBar with back + title + export action
/// 2. Image strip (horizontal, drag-reorder)
/// 3. Preview canvas (scrollable, fills remaining space)
/// 4. Sticky controls sheet (mode segmented + parameter sliders)
///
/// The whole body is wrapped in [ImageDropZone] so desktop / web
/// drag-drop also funnels images into the editor.
class StitchEditorScreen extends ConsumerWidget {
  const StitchEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(stitchEditorControllerProvider);

    return AppScaffold(
      appBar: AppBar(
        title: const Text(
          'Fl PiCraft',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton(
              onPressed: state.hasImages
                  ? () => _onExportPressed(context, ref)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: const StadiumBorder(),
              ),
              child: const Text('导出'),
            ),
          ),
        ],
      ),
      child: ImageDropZone(
        child: Column(
          children: const [
            StitchImageStrip(),
            Expanded(
              child: SingleChildScrollView(child: StitchPreviewCanvas()),
            ),
            StitchControlsSheet(),
          ],
        ),
      ),
    );
  }

  Future<void> _onExportPressed(BuildContext context, WidgetRef ref) async {
    // The full export pipeline (format chooser + save dialog + share)
    // ships with `05-08-export-watermark`. For now we just kick the
    // renderer so the perf path is exercised end-to-end and surface a
    // confirmation snackbar.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在生成长图...')));
    try {
      final bytes = await ref
          .read(stitchEditorControllerProvider.notifier)
          .render();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已生成 ${bytes.lengthInBytes ~/ 1024} KB（导出对话框待 05-08-export-watermark 接入）',
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }
}
