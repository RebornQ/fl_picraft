import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../providers/export_dispatch.dart';
import '../widgets/format_quality_card.dart';
import '../widgets/preview_card.dart';
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
/// | compact    | single column: Preview → FormatQuality → Watermark → Disclaimer; Save CTA floats as a Scaffold FAB |
/// | medium     | Preview spans the full row; FormatQuality + Watermark share a row; Disclaimer spans the full row; Save CTA floats as a Scaffold FAB |
/// | expanded / large | same as medium — body fills the available width (no outer cap); Save CTA floats as a Scaffold FAB |
///
/// **Why a bare `Scaffold` (no shell-owned bottom nav)**: per
/// `.trellis/spec/frontend/component-guidelines.md` →
/// "StatefulShellRoute + per-branch screen", `/export` is registered as
/// a sibling top-level route **outside** the `StatefulShellRoute`. It
/// therefore renders above the bottom nav (covering it), which is the
/// behavior we want for a modal flow: users shouldn't accidentally
/// walk off to another tab mid-save.
///
/// **How to exit**: the AppBar back button and the system / gesture
/// back are both routed through [_onBackPressed]. We prefer
/// `context.pop()` when the navigator can pop (normal entry via
/// `context.push('/export')` from an editor — gives a natural reverse
/// pop transition that matches the mobile back-gesture idiom). When
/// `canPop` is false (deep-link directly into `/export`, hot reload,
/// share-sheet entry), we fall back to `context.go('/stitch'|'/grid')`
/// keyed by [currentExportSourceKindProvider] so the user still lands
/// in the right editor. Hardware / gesture back is intercepted via
/// [PopScope] so both routes share the same logic.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      // We always intercept the pop so the same `_onBackPressed`
      // (with deep-link fallback) handles AppBar tap, Android system
      // back, and iOS edge-swipe uniformly.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackPressed(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: () => _onBackPressed(context, ref),
          ),
          title: const Text('导出'),
        ),
        body: const SafeArea(child: _ExportBody()),
        floatingActionButton: const SaveActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  /// Return to the editor the user came from.
  ///
  /// Preferred path: when the navigator stack can pop (the user
  /// reached `/export` via `context.push` from an editor), call
  /// `context.pop()` so the route slides off with the standard
  /// reverse-pop transition (matches the mobile back-gesture idiom).
  ///
  /// Fallback path: when `canPop` is false (deep-link entry, fresh
  /// process start on `/export`, web refresh), read
  /// [currentExportSourceKindProvider] and `context.go` to the
  /// matching editor. The kind provider records who launched the
  /// session, so we still land in the right editor.
  void _onBackPressed(BuildContext context, WidgetRef ref) {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
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
          // Preview card spans the full row on every size class — per
          // the parent task's decision 4 (顶部跨行), the user sees the
          // current export's rendered preview before any settings.
          const _SectionCard(child: PreviewCard()),
          const SizedBox(height: 16),
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
          // Disclaimer sits at the very bottom of the body. The Save
          // CTA lives in the Scaffold's `floatingActionButton` slot
          // (see [ExportScreen]); the trailing 88dp spacer below
          // reserves clearance so the FAB doesn't visually cover the
          // disclaimer when the user scrolls to the bottom
          // (~56dp FAB + 16dp endFloat margin + 16dp breathing room).
          const SaveDisclaimer(),
          const SizedBox(height: 88),
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
