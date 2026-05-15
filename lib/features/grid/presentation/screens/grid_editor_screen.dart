import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/errors/user_facing_messages.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../export/presentation/providers/export_dispatch.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/grid_editor_provider.dart';
import '../widgets/grid_controls_panel.dart';
import '../widgets/grid_preview_canvas.dart';

/// Width of the docked controls panel on expanded / large windows.
///
/// Matches the analogous stitch editor panel so the two editors keep a
/// consistent side-panel rhythm on tablet / desktop windows.
const double _kGridControlsPanelWidth = 380;

/// Grid-split editor screen.
///
/// Layout on compact / medium widths (matching `_3_宫格切图/code.html`):
/// 1. AppBar with back + title + import action
/// 2. Square preview canvas with grid overlay
/// 3. Optional source-size warning
/// 4. Nine-grid-social toggle, grid type selector, bento parameter
///    cards (all grouped inside [GridControlsPanel])
/// 5. FAB to launch the unified `/export` screen
///
/// The body is wrapped in [ImageDropZone] so desktop / web users can
/// drag-drop a new source image at any point. The FAB sets
/// [currentExportSourceKindProvider] to [ExportSourceKind.grid] before
/// navigating so the export controller dispatches its render pipeline
/// to [GridEditorController.renderCells].
///
/// Responsive behavior (driven by [windowSizeClassOf]):
///
/// | size class | layout |
/// |------------|--------|
/// | compact (<600 dp) | single column: preview → warning → controls panel, stacked in a [ListView] |
/// | medium (600–840 dp) | same as compact — phone-landscape stays single-column to keep the canvas tappable |
/// | expanded (840–1200 dp) | two-column [Row]: preview (+ optional warning) on the left, [GridControlsPanel] docked on the right at [_kGridControlsPanelWidth] |
/// | large (≥1200 dp) | same as expanded, with the body capped at [Breakpoints.maxContentWidth] via [Center] + [ConstrainedBox] |
class GridEditorScreen extends ConsumerWidget {
  const GridEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);

    // Surface image-import failures (same rationale as the stitch
    // editor — see `stitch_editor_screen.dart`). Both editors wrap
    // their bodies in [ImageDropZone], which is how drag-drop failures
    // also flow through `imageImportControllerProvider`.
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

    return AppScaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          '宫格切图编辑',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '导入图片',
            onPressed: () => notifier.addFromGallery(),
          ),
        ],
      ),
      floatingActionButton: state.hasSource
          ? FloatingActionButton.extended(
              onPressed: () => _onExportPressed(context, ref),
              tooltip: '导出每张子图',
              icon: const Icon(Icons.output),
              label: const Text('导出'),
            )
          : null,
      child: ImageDropZone(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.maxContentWidth,
            ),
            child: const _GridEditorBody(),
          ),
        ),
      ),
    );
  }

  void _onExportPressed(BuildContext context, WidgetRef ref) {
    // Mark the export session as "grid-sourced" before navigating so
    // ExportController.save() dispatches its render pipeline to
    // GridEditorController.renderCells instead of the stitch path.
    ref.read(currentExportSourceKindProvider.notifier).state =
        ExportSourceKind.grid;
    context.go('/export');
  }
}

class _GridEditorBody extends ConsumerWidget {
  const _GridEditorBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceTooSmall = ref.watch(
      gridEditorControllerProvider.select((s) => s.sourceTooSmall),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sizeClass = windowSizeClassOf(context);
    final useSidePanel =
        sizeClass == WindowSizeClass.expanded ||
        sizeClass == WindowSizeClass.large;

    if (useSidePanel) {
      // Two-column layout: canvas (+ optional warning) on the left,
      // GridControlsPanel docked on the right. FAB clearance is not
      // strictly needed at this width (the FAB floats over the canvas
      // column), but we keep a comfortable bottom inset so the user
      // can scroll past the parameter cards.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GridPreviewCanvas(),
                    if (sourceTooSmall) ...[
                      const SizedBox(height: 12),
                      _SourceSizeWarning(
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            const SizedBox(
              width: _kGridControlsPanelWidth,
              child: SingleChildScrollView(child: GridControlsPanel()),
            ),
          ],
        ),
      );
    }

    return ListView(
      // Bottom 96 dp clears the floating action button on compact /
      // medium widths.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const GridPreviewCanvas(),
        if (sourceTooSmall) ...[
          const SizedBox(height: 12),
          _SourceSizeWarning(colorScheme: colorScheme, textTheme: textTheme),
        ],
        const SizedBox(height: 16),
        const GridControlsPanel(),
      ],
    );
  }
}

class _SourceSizeWarning extends StatelessWidget {
  const _SourceSizeWarning({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // Compose the warning tint on top of the surface color so the
    // banner stays readable in dark mode. `errorContainer` already
    // skews dark in the dark scheme, and a flat 40% alpha against the
    // dark surface would dissolve into the page background.
    final tintedSurface = Color.alphaBlend(
      colorScheme.errorContainer.withValues(alpha: 0.4),
      colorScheme.surface,
    );
    final tintedBorder = Color.alphaBlend(
      colorScheme.error.withValues(alpha: 0.4),
      colorScheme.surface,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tintedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tintedBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '图片过小，子图可能模糊',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
