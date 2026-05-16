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
import '../providers/grid_editor_provider.dart';
import '../widgets/grid_controls_panel.dart';
import '../widgets/grid_preview_canvas.dart';

/// Lower bound for the docked controls panel on expanded / large windows.
///
/// Matches the analogous stitch editor minimum so the two editors keep a
/// consistent side-panel rhythm on tablet / desktop windows.
const double _kGridControlsPanelMinWidth = 380;

/// Upper bound for the docked controls panel. Past this width the
/// panel looks oversized next to the preview on ultra-wide monitors —
/// the extra space stays with the canvas.
const double _kGridControlsPanelMaxWidth = 480;

/// Key for the docked controls panel's surface chrome container in the
/// expanded / large layout.
///
/// Exposed so widget tests can locate the chrome to assert visual
/// behavior (height fills the row, decoration colors match the
/// `surfaceContainerLow` + `outlineVariant` palette, etc.) without
/// reaching for fragile structural finders. Lives alongside the
/// panel-width clamp constants because both are visual contracts of
/// the side-panel variant — see `.trellis/spec/frontend/responsive-layout.md`
/// → "Caller decoration variants".
const Key kGridControlsPanelChromeKey = ValueKey('grid_controls_panel_chrome');

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
/// The bottom nav and surrounding `Scaffold` chrome are owned by the
/// surrounding `AppShell`; this screen returns only its own `Scaffold`
/// (for `AppBar` + body + FAB) without a `bottomNavigationBar`.
///
/// Responsive behavior (driven by [windowSizeClassOf]) — every size
/// class follows the same **height-first** principle: the canvas claims
/// the remaining vertical space inside a `Column`, kept square via
/// `Center` + `AspectRatio(1)`. The controls live below the canvas on
/// phones and dock to the right on tablets / desktops, but the
/// preview slot is always bounded by the container's height.
///
/// | size class | layout |
/// |------------|--------|
/// | compact (<600 dp) | single-column height-first [Column] skeleton: `Expanded(Center(AspectRatio(1, canvas)))` + optional source-size warning + `Flexible(loose) > SingleChildScrollView > GridControlsPanel` (overflow scrolls *inside* the controls panel; no page-level scroll). |
/// | medium (600–840 dp) | same as compact — phone-landscape keeps the height-first single-column skeleton. |
/// | expanded (840–1200 dp) | two-column [Row] (`crossAxisAlignment: stretch`): canvas claims the left `Expanded` slot via `Column(stretch) > Expanded(Center(AspectRatio(1, canvas)))` so it fits by height; right panel docks [GridControlsPanel] at `clamp(380, container * 0.25, 480)` dp inside a `surfaceContainerLow` + `outlineVariant` 16 dp rounded chrome container (`kGridControlsPanelChromeKey`) that fills the row's full height and scrolls internally. |
/// | large (≥1200 dp) | same as expanded — body fills the available width, side panel stays in `[380, 480]` dp with the surface chrome, canvas square is `min(leftColWidth, rowHeight)`. |
///
/// The square (1:1) shape of the canvas is the caller's responsibility
/// — [GridPreviewCanvas] no longer wraps itself in `AspectRatio`. Every
/// layout branch above feeds the canvas through the same
/// `Center + AspectRatio(1)` idiom, so a single height-first sizing
/// contract covers all four size classes.
class GridEditorScreen extends ConsumerWidget {
  const GridEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);

    // Surface image-import failures (same rationale as the stitch
    // editor — see `stitch_editor_screen.dart`). The grid editor
    // listens to its own `(.grid)` family instance so stitch-side
    // import errors never surface here.
    ref.listen<AsyncValue<List<ImportedImage>>>(
      imageImportControllerProvider(ImageImportSessionKind.grid),
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
      body: const SafeArea(
        child: ImageDropZone(
          sessionKind: ImageImportSessionKind.grid,
          child: _GridEditorBody(),
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
      // GridControlsPanel docked on the right at a fluid width. The
      // left column applies the same height-first skeleton as compact /
      // medium so the canvas never grows taller than the container —
      // see the "side-panel variant" section of
      // `.trellis/spec/frontend/responsive-layout.md`. FAB clearance is
      // not strictly needed at this width (the FAB floats over the
      // canvas column), but we keep a comfortable bottom inset so the
      // user can scroll past the parameter cards.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Reserve 16 dp for the inter-column gap so the clamp
            // sees the actual content room.
            final available = (constraints.maxWidth - 16).clamp(
              0.0,
              double.infinity,
            );
            final panelWidth = (available * 0.25).clamp(
              _kGridControlsPanelMinWidth,
              _kGridControlsPanelMaxWidth,
            );
            return Row(
              // Stretch the row's children to the row's full height so
              // the left column inherits a bounded vertical extent.
              // Without stretch the column's height becomes unbounded
              // and `AspectRatio(1)` collapses back onto width — the
              // exact root cause of the prior "canvas overflows
              // ultra-wide screens" bug.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Canvas claims the leftover vertical space.
                      // `Center + AspectRatio(1)` yields a square sized
                      // `min(leftColWidth, leftColHeight)` — the canvas
                      // never exceeds the container's height.
                      const Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: GridPreviewCanvas(),
                          ),
                        ),
                      ),
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
                const SizedBox(width: 16),
                SizedBox(
                  width: panelWidth,
                  // Surface chrome: paints a `surfaceContainerLow` slab
                  // with a 1 px `outlineVariant` outline and 16 dp
                  // rounded corners. Stretched by the parent `Row` to
                  // the row's full height, so the chrome visually
                  // anchors the controls column from top to bottom even
                  // when the inner controls don't fill the height. The
                  // bare [GridControlsPanel] stays decoration-free per
                  // the "panel has no outer padding" convention; the
                  // caller (this screen) supplies the chrome here. The
                  // stitch editor's analogous side panel keeps its
                  // bare layout — see
                  // `.trellis/spec/frontend/responsive-layout.md`
                  // → "Caller decoration variants".
                  child: Container(
                    key: kGridControlsPanelChromeKey,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    // `clipBehavior: antiAlias` keeps the scroll
                    // viewport (and any future overflow indicators)
                    // confined inside the rounded corners.
                    clipBehavior: Clip.antiAlias,
                    // Padding lives **inside** the scroll view so the
                    // top/bottom margins scroll with the content — the
                    // chrome itself stays flush against the row edges.
                    child: const SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: GridControlsPanel(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    // Height-first single-column skeleton for compact / medium widths.
    //
    // The body is a [Column] (not a [ListView]) so the canvas can claim
    // the **remaining** vertical space via [Expanded] rather than
    // sizing itself by container width. This keeps the canvas + first
    // controls card visible on the first screen — without this skeleton
    // the AspectRatio(1) canvas plus the controls panel together
    // overflow a typical phone viewport and force the user to scroll
    // before they can adjust spacing / corner radius.
    //
    // Layout breakdown:
    // * `Expanded` slot → `Center(AspectRatio(1, GridPreviewCanvas))`
    //   pins the canvas to a centered square that grows with the
    //   available height (bounded to width when the viewport is wide).
    // * Optional `_SourceSizeWarning` lives just below the canvas as a
    //   non-scrolling fixed-height banner.
    // * `Flexible(fit: FlexFit.loose) + SingleChildScrollView` for the
    //   controls panel — `loose` means it sizes to its content when
    //   there is room, but never grows past the remaining vertical
    //   space (any overflow scrolls *inside* the controls panel, not
    //   the whole page). `Expanded` would force the panel to fill all
    //   leftover height even when its content is much shorter, which
    //   would visually disconnect the controls from the canvas.
    return Padding(
      // Bottom 96 dp clears the floating action button.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Center(
              child: AspectRatio(aspectRatio: 1, child: GridPreviewCanvas()),
            ),
          ),
          if (sourceTooSmall) ...[
            const SizedBox(height: 12),
            _SourceSizeWarning(colorScheme: colorScheme, textTheme: textTheme),
          ],
          const SizedBox(height: 16),
          const Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(child: GridControlsPanel()),
          ),
        ],
      ),
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
