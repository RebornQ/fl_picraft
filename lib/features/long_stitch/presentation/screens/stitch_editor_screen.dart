import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/errors/user_facing_messages.dart';
import '../../../../core/widgets/discard_editor_dialog.dart';
import '../../../export/presentation/providers/export_dispatch.dart';
import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/stitch_editor_provider.dart';
import '../widgets/stitch_controls_panel.dart';
import '../widgets/stitch_controls_sheet.dart';
import '../widgets/stitch_editor_bottom_bar.dart';
import '../widgets/stitch_image_strip.dart';
import '../widgets/stitch_inline_controls_container.dart';
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
/// Layout (top → bottom on medium widths; compact + expanded / large
/// each use their own shape — see the responsive table below):
/// 1. AppBar with title + (compact / medium) export action — no leading
///    back button: this screen is a `StatefulShellRoute` tab branch root,
///    so the user uses the bottom nav to switch tabs (see
///    `.trellis/spec/frontend/component-guidelines.md`
///    → "StatefulShellRoute + per-branch screen + Android back-key
///    contract"). System back / iOS edge-swipe still works via
///    `AppShell.PopScope`.
/// 2. Image strip (horizontal, drag-reorder) — medium only
/// 3. Preview canvas (fills remaining space — owns its own scroll;
///    the grey surface ALWAYS fills the Expanded height regardless of
///    canvas aspect ratio, so short canvases no longer leave dead
///    space below them)
/// 4. Sticky controls sheet (mode segmented + parameter sliders) —
///    medium only
///
/// The whole body is wrapped in [ImageDropZone] so desktop / web
/// drag-drop also funnels images into the editor. The "导出" CTA
/// (AppBar IconButton on compact / medium, floating action button
/// on expanded / large) marks the session as stitch-sourced (via
/// [currentExportSourceKindProvider]) and routes to the unified
/// `/export` screen.
///
/// The bottom nav and surrounding `Scaffold` chrome are owned by the
/// surrounding `AppShell`; this screen returns its own `Scaffold`
/// (with its own `AppBar` and — on compact — a
/// [StitchEditorBottomBar] in the inner Scaffold's
/// `bottomNavigationBar` slot stacked above the outer
/// `AppShell.bottomNavigationBar`).
///
/// Responsive behavior (driven by [windowSizeClassOf]):
///
/// | size class | layout |
/// |------------|--------|
/// | compact (<600 dp) | canvas fills the entire body ([Column] with one [Expanded(StitchPreviewCanvas)] child). The image strip / controls sheet move into modal sheets surfaced from the 3-chip [StitchEditorBottomBar] in the inner Scaffold's `bottomNavigationBar` slot. AppBar's export IconButton is **retained** (same position as medium) — it stays the primary export CTA on compact too. |
/// | medium (600–840 dp) | image strip on top, canvas in the middle (fills the Expanded slot, surface scrolls internally for tall canvases), controls docked as a bottom [StitchControlsSheet]; AppBar's export IconButton is the primary CTA. |
/// | expanded (840–1200 dp) | two-column [Row]: canvas on the left (fills the Expanded slot) and a fluid right column docked at `clamp(380, container * 0.25, 480)` dp — the right column splits 50/50 between a vertical [StitchVerticalImageList] (top) and the [StitchControlsPanel] (bottom), each with its own internal scroll. The top image strip is **not** rendered on this size class; the export CTA moves to a floating action button. |
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

    final sizeClass = windowSizeClassOf(context);
    final isCompact = sizeClass == WindowSizeClass.compact;
    final useSidePanel =
        sizeClass == WindowSizeClass.expanded ||
        sizeClass == WindowSizeClass.large;
    // Compact secondary-page entry (`/m/stitch`): the screen sits on top
    // of the AppShell's root navigator, so `Navigator.canPop` is true.
    // Branch tab roots (the `/stitch` shell branch) return false because
    // the branch's own Navigator is at its root. Use this single check
    // to drive both the PopScope confirmation contract and the AppBar
    // leading back-arrow — both should fire on compact secondary pages
    // and never on the desktop tab. See ADR-2 in
    // `.trellis/tasks/05-26-mobile-stitch-secondary-page/prd.md`.
    final isSecondaryPage = Navigator.canPop(context);

    return PopScope(
      // Block the auto-pop while there are images to lose; let it
      // through (canPop: true) when the editor is empty so the back
      // gesture is instant. Branch tab roots never get here because
      // `isSecondaryPage` is false and we plug a passthrough PopScope
      // (canPop: true, no-op callback) — the shell's own PopScope above
      // handles tab-root pops.
      canPop: !isSecondaryPage || !state.hasImages,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!isSecondaryPage) return; // defensive — shell handles tab roots
        final confirmed = await showDiscardEditorDialog(context);
        if (!confirmed) return;
        // Clear the session before popping so re-entering the editor
        // from the home FeatureCard lands on an empty canvas (per
        // ADR-4 in the PRD; matches the "未导出的拼图将丢失" dialog
        // copy).
        ref.read(stitchEditorControllerProvider.notifier).clear();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          // Show the back arrow only on the compact secondary-page entry.
          // Branch tab roots stay leading-less (canPop is false there
          // anyway so Flutter wouldn't paint one) — this is the explicit
          // toggle so a future refactor that wraps the AppBar in a
          // hand-rolled `Row` doesn't accidentally lose the arrow.
          automaticallyImplyLeading: isSecondaryPage,
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
            //
            // AppBar export IconButton is rendered on compact + medium
            // (`!useSidePanel`). On expanded / large the
            // [FloatingActionButton.extended] below takes over as the
            // export CTA. Compact keeps the IconButton in the AppBar
            // (rather than moving the CTA into the
            // [StitchEditorBottomBar]) so the export position stays
            // aligned with users' existing muscle memory; the bar only
            // hosts add / images / params chips.
            if (!useSidePanel)
              Container(
                margin: EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: const Icon(Icons.save_outlined, size: 28),
                  tooltip: '导出拼图',
                  style: ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  alignment: AlignmentGeometry.center,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 6,
                  ),
                  onPressed: state.hasImages
                      ? () => _onExportPressed(context, ref)
                      : null,
                ),
              ),
          ],
        ),
        // TODO 备注：勿删，保留备用
        floatingActionButton: useSidePanel && state.hasImages
            ? FloatingActionButton.extended(
                // Namespaced hero tag so this FAB doesn't collide with the
                // grid editor's export FAB when both editor branches are
                // kept alive by `StatefulShellRoute`. Without a unique tag
                // Flutter's default `_kDefaultHeroTag` triggers the
                // "multiple heroes share the same tag within a subtree"
                // assertion the moment the user taps either FAB.
                heroTag: 'stitch-export-fab',
                onPressed: () => _onExportPressed(context, ref),
                tooltip: '导出拼接图',
                icon: const Icon(Icons.output),
                label: const Text('导出'),
              )
            : null,
        // Compact-only editor bottom bar — sits in the inner Scaffold's
        // `bottomNavigationBar` slot so Flutter stacks it above the
        // outer `AppShell.bottomNavigationBar` (the outer shell's nav
        // bar still owns tab switching; this one owns
        // add / images / params within the editor; export stays in the
        // AppBar). medium keeps its existing `StitchControlsSheet` +
        // AppBar IconButton pair; expanded / large rely on the side
        // panel + FAB above — neither needs the editor bottom bar.
        bottomNavigationBar: isCompact ? const StitchEditorBottomBar() : null,
        body: const SafeArea(
          child: ImageDropZone(
            sessionKind: ImageImportSessionKind.stitch,
            child: _StitchEditorBody(),
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
    context.push('/export');
  }
}

class _StitchEditorBody extends StatelessWidget {
  const _StitchEditorBody();

  @override
  Widget build(BuildContext context) {
    final sizeClass = windowSizeClassOf(context);
    final isCompact = sizeClass == WindowSizeClass.compact;
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

    if (isCompact) {
      // The image strip and (legacy) parameter sheet move into modal
      // sheets surfaced from [StitchEditorBottomBar] (mounted in the
      // surrounding Scaffold's `bottomNavigationBar` slot). The
      // parameter sheet has been replaced by an inline expandable
      // panel ([StitchInlineControlsContainer]) — toggling the `[⚙ 参数]`
      // chip animates the panel between the canvas and the bottom
      // bar so the canvas keeps live visual feedback during parameter
      // edits (PRD `05-26-compact`).
      //
      // The bar itself is **not** rendered here — it lives outside
      // the body in the Scaffold's `bottomNavigationBar` slot so the
      // canvas can claim every pixel between the AppBar and the bar
      // (minus the inline panel's height when expanded).
      return const Column(
        children: [
          Expanded(child: StitchPreviewCanvas()),
          StitchInlineControlsContainer(),
        ],
      );
    }

    // Medium (600–840 dp): keep the single-column strip + canvas +
    // sheet layout. Phone-landscape stays here because the bottom
    // sheet remains thumb-reachable.
    return const Column(
      children: [
        StitchImageStrip(),
        Expanded(child: StitchPreviewCanvas()),
        StitchControlsSheet(),
      ],
    );
  }
}
