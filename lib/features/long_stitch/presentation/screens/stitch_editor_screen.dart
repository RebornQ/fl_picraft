import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/errors/user_facing_messages.dart';
import '../../../export/presentation/providers/export_dispatch.dart';
import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/stitch_editor_provider.dart';
import '../widgets/stitch_controls_panel.dart';
import '../widgets/stitch_controls_sheet.dart';
import '../widgets/stitch_image_strip.dart';
import '../widgets/stitch_preview_canvas.dart';
import '../widgets/stitch_vertical_image_list.dart';

/// Lower bound for the docked controls panel on expanded / large windows.
///
/// Picked to comfortably fit the longest slider label plus value
/// readout without wrapping on a tablet-class window.
const double _kStitchControlsPanelMinWidth = 380;

/// Upper bound for the docked controls panel. Past this width the panel
/// looks oversized next to the canvas on ultra-wide monitors — keep the
/// extra space on the canvas instead.
const double _kStitchControlsPanelMaxWidth = 480;

/// Long-stitch editor screen.
///
/// Layout (top → bottom on compact / medium widths):
/// 1. AppBar with back + title + export action
/// 2. Image strip (horizontal, drag-reorder)
/// 3. Preview canvas (fills remaining space — owns its own scroll;
///    the grey surface ALWAYS fills the Expanded height regardless of
///    canvas aspect ratio, so short canvases no longer leave dead
///    space below them)
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
/// | compact (<600 dp) | image strip on top, canvas in the middle (fills the Expanded slot, surface scrolls internally for tall canvases), controls docked as a bottom [StitchControlsSheet] |
/// | medium (600–840 dp) | same as compact — phone-landscape stays single-column to keep the touch sheet reachable |
/// | expanded (840–1200 dp) | two-column [Row]: canvas on the left (fills the Expanded slot) and a fluid right column docked at `clamp(380, container * 0.25, 480)` dp — the right column splits 50/50 between a vertical [StitchVerticalImageList] (top) and the [StitchControlsPanel] (bottom), each with its own internal scroll. The top image strip is **not** rendered on this size class. |
/// | large (≥1200 dp) | same as expanded — body fills the available width, side column stays in `[380, 480]` dp |
class StitchEditorScreen extends ConsumerWidget {
  const StitchEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);

    // Surface image-import failures the editor's import affordances
    // funnel into AsyncError on the stitch-scoped controller. Without
    // this listen the picker rejection / unsupported-source /
    // invalid-data failures were silently dropped (the editor reads
    // `importedImagesProvider(.stitch)` which collapses error to an
    // empty list). The grid editor listens to its own
    // `(.grid)` instance — errors never cross modes.
    ref.listen<AsyncValue<List<ImportedImage>>>(
      imageImportControllerProvider(ImageImportSessionKind.stitch),
      (previous, next) {
        if (next is! AsyncError) return;
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(content: Text(importFailureMessage(next.error))),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          '长图拼接',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // TODO 备注：勿删，保留备用
          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          //   child: FilledButton(
          //     onPressed: state.hasImages
          //         ? () => _onExportPressed(context, ref)
          //         : null,
          //     style: FilledButton.styleFrom(
          //       backgroundColor: colorScheme.primary,
          //       foregroundColor: colorScheme.onPrimary,
          //       shape: const StadiumBorder(),
          //     ),
          //     child: const Text('导出'),
          //   ),
          // ),
        ],
      ),
      floatingActionButton: state.hasImages
          ? FloatingActionButton.extended(
              onPressed: () => _onExportPressed(context, ref),
              tooltip: '导出拼接图',
              icon: const Icon(Icons.output),
              label: const Text('导出'),
            )
          : null,
      body: const SafeArea(
        child: ImageDropZone(
          sessionKind: ImageImportSessionKind.stitch,
          child: _StitchEditorBody(),
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
    context.push('/export');
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
      return LayoutBuilder(
        builder: (context, constraints) {
          // Fluid side-column width: 25% of the row, clamped to
          // [380, 480]. Keeping the math in one LayoutBuilder
          // (instead of `Flexible` + `ConstrainedBox` games)
          // sidesteps the gotcha where the column would be
          // squeezed by `Expanded(canvas)` competing for space.
          final panelWidth = (constraints.maxWidth * 0.25).clamp(
            _kStitchControlsPanelMinWidth,
            _kStitchControlsPanelMaxWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: StitchPreviewCanvas()),
              SizedBox(
                width: panelWidth,
                // 50/50 split between the vertical selected-images list
                // (top) and the controls panel (bottom). Each half owns
                // its own SingleChildScrollView so the two scroll
                // regions stay independent — required by the
                // responsive-layout spec ("side panel content must
                // scroll independently") and avoids RenderBox overflow
                // when either half has more content than its share.
                child: const Column(
                  children: [
                    Expanded(child: StitchVerticalImageList()),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: 80),
                        child: StitchControlsPanel(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    return const Column(
      children: [
        StitchImageStrip(),
        Expanded(child: StitchPreviewCanvas()),
        StitchControlsSheet(),
      ],
    );
  }
}
