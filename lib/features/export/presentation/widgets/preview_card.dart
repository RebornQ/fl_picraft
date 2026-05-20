import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preview_controller.dart';
import '../providers/preview_state.dart';
import 'preview_skeleton.dart';
import 'preview_thumbnail.dart';

/// Fixed height of the preview surface inside the card (excluding
/// header / padding). 240 dp per the parent task's PRD §1.
const double kPreviewSurfaceHeight = 240;

/// Top-of-export-screen preview card.
///
/// Watches [previewControllerProvider] (which returns the sealed
/// [PreviewState] directly — not wrapped in `AsyncValue`) and performs
/// a **single-layer** exhaustive switch over the four variants. Per
/// the parent task's PRD §D1, the sealed variants already cover
/// loading / ready / error / empty so an `AsyncValue.when` wrapper
/// would force a 4×4 product of cases.
///
/// Visual style mirrors [FormatQualityCard] / [WatermarkCard]:
/// `surfaceContainer` background (the parent `_SectionCard` in
/// `export_screen.dart` paints that) + rounded corners + a header row.
/// The header shows the title "预览" on the left; in [PreviewReady]
/// it also surfaces the estimated total file size on the right
/// (`约 X.X MB`).
class PreviewCard extends ConsumerWidget {
  const PreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header — title + (optional) size label.
        Row(
          children: [
            Expanded(
              child: Text(
                '预览',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (state is PreviewReady)
              _SizeLabel(totalBytes: state.totalSizeBytes),
          ],
        ),
        const SizedBox(height: 12),
        // Preview surface — fixed height, content swapped through
        // AnimatedSwitcher so the loading → ready transition fades
        // rather than snaps.
        SizedBox(
          height: kPreviewSurfaceHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildBody(state),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Single-layer dispatch over the sealed [PreviewState]. Per PRD
  /// §1.1 this must NOT nest an `AsyncValue.when` — the controller's
  /// state IS the sealed.
  Widget _buildBody(PreviewState state) {
    return switch (state) {
      PreviewEmpty() => const _EmptyView(key: ValueKey('empty')),
      PreviewLoading(:final staleBytes) => PreviewSkeleton(
        key: const ValueKey('loading'),
        staleBytes: staleBytes,
      ),
      PreviewReady(:final bytes) => _ReadyView(
        key: const ValueKey('ready'),
        bytes: bytes,
      ),
      PreviewError(:final message, :final staleBytes) => _ErrorView(
        key: const ValueKey('error'),
        message: message,
        staleBytes: staleBytes,
      ),
    };
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 32,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '没有可预览的图片',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the rendered preview bytes:
/// * stitch path (`bytes.length == 1`) → single [PreviewThumbnail]
/// * grid path (`bytes.length > 1`) → horizontal [ListView.builder]
class _ReadyView extends StatelessWidget {
  const _ReadyView({super.key, required this.bytes});

  final List<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes.isEmpty) {
      return const _EmptyView();
    }
    if (bytes.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: PreviewThumbnail(bytes: bytes.first, semanticLabel: '预览图片'),
      );
    }
    // Grid mode — horizontal carousel, one thumbnail per cell.
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      itemCount: bytes.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(right: index == bytes.length - 1 ? 0 : 8),
          child: AspectRatio(
            aspectRatio: 1,
            child: PreviewThumbnail(
              bytes: bytes[index],
              semanticLabel: '预览图片 ${index + 1} / ${bytes.length}',
            ),
          ),
        );
      },
    );
  }
}

/// Error overlay. When [staleBytes] is non-null we still render the
/// last good preview behind the overlay (at 50 % opacity) so the user
/// can see what they had before the failure.
class _ErrorView extends ConsumerWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.staleBytes,
  });

  final String message;
  final List<Uint8List>? staleBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasStale = staleBytes != null && staleBytes!.isNotEmpty;

    return Stack(
      children: [
        if (hasStale)
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: Center(
                child: Image.memory(
                  staleBytes!.first,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 32, color: colorScheme.error),
                  const SizedBox(height: 8),
                  Text(
                    '预览暂不可用',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(previewControllerProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "约 X.X MB" label rendered next to the preview header in
/// [PreviewReady]. Reads the controller's pre-summed [totalSizeBytes]
/// to avoid re-summing on every rebuild.
class _SizeLabel extends StatelessWidget {
  const _SizeLabel({required this.totalBytes});

  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mb = totalBytes / 1024 / 1024;
    return Text(
      '约 ${mb.toStringAsFixed(1)} MB',
      style: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// (Preview surface routes taps through PreviewThumbnail →
// PreviewFullScreenDialog; PreviewCard itself does not directly
// reference the dialog widget.)
