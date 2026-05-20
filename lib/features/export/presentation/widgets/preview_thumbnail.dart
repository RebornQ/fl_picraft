import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'preview_full_screen_dialog.dart';

/// Single preview thumbnail rendered inside [PreviewCard].
///
/// Reused by both the stitch path (single image) and the grid path
/// (one per cell, laid out in a horizontal [ListView]). The widget is
/// passive — it doesn't watch any provider — so the same instance can
/// be embedded in either path without coupling to the source kind.
///
/// Sizing contract: the caller decides the outer width / height (via
/// [SizedBox] or [Expanded]). The image is rendered with
/// [BoxFit.contain] so a tall stitch composite or a square grid cell
/// both fit cleanly inside the preview card's fixed-height row.
///
/// Tap behavior: opens the [PreviewFullScreenDialog] with the supplied
/// bytes so the user can pinch-zoom to inspect the full resolution.
class PreviewThumbnail extends StatelessWidget {
  const PreviewThumbnail({super.key, required this.bytes, this.semanticLabel});

  /// Encoded image bytes (PNG or JPG, decided by the export format).
  final Uint8List bytes;

  /// Optional accessibility label used by screen-readers. Defaults to
  /// a generic "预览图片" when omitted.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel ?? '预览图片',
      child: InkWell(
        onTap: () => _openFullScreen(context),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: colorScheme.surfaceContainerHighest,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PreviewFullScreenDialog(bytes: bytes),
    );
  }
}
