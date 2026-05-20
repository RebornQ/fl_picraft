import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../grid/presentation/widgets/grid_preview_canvas.dart';
import '../../../long_stitch/presentation/widgets/stitch_preview_canvas.dart';
import '../providers/export_dispatch.dart';

/// Loading placeholder for the preview card.
///
/// Two visual modes — driven by the [staleBytes] argument supplied by
/// the controller's `PreviewLoading.staleBytes`:
///
/// * **First load** (`staleBytes == null`) — fall back to the editor's
///   widget canvas (`StitchPreviewCanvas` / `GridPreviewCanvas`,
///   selected by [currentExportSourceKindProvider]). Wrapped in
///   `Opacity(0.6)` + an "加载中..." chip so the placeholder reads as
///   "in progress" rather than "this is the final preview".
///
/// * **Re-render after a successful preview** (`staleBytes != null`) —
///   show the stale bytes via [Image.memory] with a "刷新中..." chip
///   overlay so the user knows the system is recomputing in response
///   to a config change.
///
/// The transition from skeleton → real `PreviewReady` is handled by
/// the parent `AnimatedSwitcher` in `PreviewCard`; this widget only
/// owns the loading visual itself.
class PreviewSkeleton extends ConsumerWidget {
  const PreviewSkeleton({super.key, this.staleBytes});

  /// Previously-rendered bytes, when the loading state was reached from
  /// `PreviewReady`. `null` on first entry — in that case the widget
  /// falls back to the editor canvas.
  final List<Uint8List>? staleBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStale = staleBytes != null && staleBytes!.isNotEmpty;
    final chipLabel = hasStale ? '刷新中...' : '加载中...';

    final body = hasStale
        ? Center(
            child: Image.memory(
              staleBytes!.first,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          )
        : _EditorCanvasFallback(
            sourceKind: ref.watch(currentExportSourceKindProvider),
          );

    return Stack(
      children: [
        // The body sits beneath the chip overlay.
        Positioned.fill(child: body),
        Positioned(top: 8, left: 8, child: _LoadingChip(label: chipLabel)),
      ],
    );
  }
}

/// Renders the source editor's widget canvas (chrome included) at 60%
/// opacity. We can't tell from here whether the canvas itself is
/// meaningful — when the editor is empty it falls through to its own
/// empty hint, which still reads as "preview pending".
class _EditorCanvasFallback extends StatelessWidget {
  const _EditorCanvasFallback({required this.sourceKind});

  final ExportSourceKind sourceKind;

  @override
  Widget build(BuildContext context) {
    final canvas = switch (sourceKind) {
      ExportSourceKind.stitch => const StitchPreviewCanvas(),
      ExportSourceKind.grid => const GridPreviewCanvas(),
    };
    return Opacity(opacity: 0.6, child: canvas);
  }
}

/// Small leading chip painted in the top-left corner of the skeleton.
class _LoadingChip extends StatelessWidget {
  const _LoadingChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(colorScheme.primary),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
