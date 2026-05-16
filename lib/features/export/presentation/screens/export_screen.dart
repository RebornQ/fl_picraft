import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../providers/export_dispatch.dart';
import '../widgets/format_quality_card.dart';
import '../widgets/save_action_button.dart';
import '../widgets/save_disclaimer.dart';
import '../widgets/watermark_card.dart';

/// Export screen — composes format / quality picker, watermark
/// settings, save CTA, and the local-processing disclaimer.
///
/// Source plumbing dispatches on [currentExportSourceKindProvider]:
/// stitch sources render through the long-stitch composer, grid
/// sources run cell-by-cell. See `export_controller.dart` for the
/// dispatch contract.
///
/// Responsive behavior (driven by [windowSizeClassOf]):
///
/// | size class | layout |
/// |------------|--------|
/// | compact    | single column: FormatQuality → Watermark → Save → Disclaimer |
/// | medium     | two-column row for FormatQuality + Watermark; Save and Disclaimer span the full row |
/// | expanded / large | same as medium, with the content capped at [Breakpoints.maxContentWidth] |
///
/// **Why a bare `Scaffold` (no shell-owned bottom nav)**: per
/// `.trellis/spec/frontend/component-guidelines.md` →
/// "StatefulShellRoute + per-branch screen", `/export` is registered as
/// a sibling top-level route **outside** the `StatefulShellRoute`. It
/// therefore renders above the bottom nav (covering it), which is the
/// behavior we want for a modal flow: users shouldn't accidentally
/// walk off to another tab mid-save. The back button in the app bar
/// is the only way out, and it routes back to the editor that
/// initiated the export (tracked via [currentExportSourceKindProvider]).
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => _onBackPressed(context, ref),
        ),
        title: const Text('导出'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.maxContentWidth,
            ),
            child: const _ExportBody(),
          ),
        ),
      ),
    );
  }

  /// Return to the editor the user came from. The kind provider
  /// records who launched the export session, so we route back to
  /// that editor rather than relying on the navigator stack (which
  /// `context.go` doesn't preserve across top-level routes).
  void _onBackPressed(BuildContext context, WidgetRef ref) {
    final kind = ref.read(currentExportSourceKindProvider);
    switch (kind) {
      case ExportSourceKind.stitch:
        context.go('/stitch');
      case ExportSourceKind.grid:
        context.go('/grid');
    }
  }
}

class _ExportBody extends StatelessWidget {
  const _ExportBody();

  @override
  Widget build(BuildContext context) {
    final isCompact = windowSizeClassOf(context) == WindowSizeClass.compact;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCompact) ...const [
            _SectionCard(child: FormatQualityCard()),
            SizedBox(height: 16),
            _SectionCard(child: WatermarkCard()),
          ] else
            // Medium+ packs FormatQuality and Watermark side-by-side
            // so the two settings cards share a row instead of
            // stacking vertically (which leaves big slabs of empty
            // space on tablet / desktop windows). We deliberately
            // skip `IntrinsicHeight` here: this row lives inside the
            // outer `SingleChildScrollView`, whose viewport refuses
            // intrinsic-dimension queries. Top-aligning the two cards
            // is fine because they have similar internal heights.
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SectionCard(child: FormatQualityCard())),
                SizedBox(width: 16),
                Expanded(child: _SectionCard(child: WatermarkCard())),
              ],
            ),
          const SizedBox(height: 16),
          // Save CTA + disclaimer keep their full-width single-column
          // treatment on every size class so the primary action stays
          // visually anchored.
          const SaveActionButton(),
          const SizedBox(height: 16),
          const SaveDisclaimer(),
        ],
      ),
    );
  }
}

/// Visual wrapper that gives each settings section the rounded
/// "surface-container" look from the mockup's right-hand panel.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
