import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/errors/user_facing_messages.dart';
import '../../../export/presentation/providers/export_dispatch.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/stitch_editor_provider.dart';
import '../widgets/stitch_controls_panel.dart';
import '../widgets/stitch_controls_sheet.dart';
import '../widgets/stitch_image_strip.dart';
import '../widgets/stitch_preview_canvas.dart';

/// Width of the docked controls panel on expanded / large windows.
///
/// Picked to comfortably fit the longest slider label plus value
/// readout without wrapping. Smaller than the canvas flex so the
/// preview keeps the visual primacy on tablet / desktop.
const double _kStitchControlsPanelWidth = 380;

/// Long-stitch editor screen.
///
/// Layout (top → bottom on compact / medium widths):
/// 1. AppBar with back + title + export action
/// 2. Image strip (horizontal, drag-reorder)
/// 3. Preview canvas (scrollable, fills remaining space)
/// 4. Sticky controls sheet (mode segmented + parameter sliders)
///
/// The whole body is wrapped in [ImageDropZone] so desktop / web
/// drag-drop also funnels images into the editor. The "导出" CTA in
/// the app bar marks the session as stitch-sourced (via
/// [currentExportSourceKindProvider]) and routes to the unified
/// `/export` screen.
///
/// The bottom nav and surrounding `Scaffold` chrome are owned by the
/// surrounding `AppShell`; this screen returns only its own `Scaffold`
/// (for `AppBar` + body) without a `bottomNavigationBar`.
///
/// Responsive behavior (driven by [windowSizeClassOf]):
///
/// | size class | layout |
/// |------------|--------|
/// | compact (<600 dp) | image strip on top, scrollable canvas in the middle, controls docked as a bottom [StitchControlsSheet] |
/// | medium (600–840 dp) | same as compact — phone-landscape stays single-column to keep the touch sheet reachable |
/// | expanded (840–1200 dp) | image strip on top; below it a two-column [Row] with the canvas on the left and a [_kStitchControlsPanelWidth]-wide [StitchControlsPanel] docked on the right |
/// | large (≥1200 dp) | same as expanded, with the body capped at [Breakpoints.maxContentWidth] via [Center] + [ConstrainedBox] |
class StitchEditorScreen extends ConsumerWidget {
  const StitchEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(stitchEditorControllerProvider);

    // Surface image-import failures the editor's import affordances
    // funnel into AsyncError on the shared controller. Without this
    // listen the picker rejection / unsupported-source / invalid-data
    // failures were silently dropped (the editor reads
    // `importedImagesProvider` which collapses error to an empty
    // list). One attach per editor screen is enough — both editors
    // wrap their bodies in [ImageDropZone] but neither is mounted at
    // the same time as the other, so we won't see duplicate snackbars.
    ref.listen<AsyncValue<List<ImportedImage>>>(imageImportControllerProvider, (
      previous,
      next,
    ) {
      if (next is! AsyncError) return;
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text(importFailureMessage(next.error))),
      );
    });

    return Scaffold(
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
      body: SafeArea(
        child: ImageDropZone(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.maxContentWidth,
              ),
              child: const _StitchEditorBody(),
            ),
          ),
        ),
      ),
    );
  }

  void _onExportPressed(BuildContext context, WidgetRef ref) {
    // Mark the export session as "stitch-sourced" before navigating so
    // ExportController.save() dispatches its render pipeline to
    // StitchEditorController.render instead of the grid path.
    ref.read(currentExportSourceKindProvider.notifier).state =
        ExportSourceKind.stitch;
    context.go('/export');
  }
}

class _StitchEditorBody extends StatelessWidget {
  const _StitchEditorBody();

  @override
  Widget build(BuildContext context) {
    final sizeClass = windowSizeClassOf(context);
    final useSidePanel =
        sizeClass == WindowSizeClass.expanded ||
        sizeClass == WindowSizeClass.large;

    if (useSidePanel) {
      return const Column(
        children: [
          StitchImageStrip(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(child: StitchPreviewCanvas()),
                ),
                SizedBox(
                  width: _kStitchControlsPanelWidth,
                  child: SingleChildScrollView(child: StitchControlsPanel()),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return const Column(
      children: [
        StitchImageStrip(),
        Expanded(child: SingleChildScrollView(child: StitchPreviewCanvas())),
        StitchControlsSheet(),
      ],
    );
  }
}
