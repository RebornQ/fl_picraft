import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
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
/// [SizedBox] or [Expanded]). The image is rendered via
/// [ExtendedImage.memory] (with [ExtendedImageMode.none], i.e. no
/// gesture stack — gestures live in the full-screen dialog) and
/// [BoxFit.contain] so a tall stitch composite or a square grid cell
/// both fit cleanly inside the preview card's fixed-height row.
///
/// Tap behavior: opens the [PreviewFullScreenDialog] with the supplied
/// bytes so the user can pinch-zoom to inspect the full resolution.
class PreviewThumbnail extends StatelessWidget {
  const PreviewThumbnail({
    super.key,
    required this.bytes,
    this.semanticLabel,
    this.allBytes,
    this.initialIndex = 0,
  });

  /// Encoded image bytes (PNG or JPG, decided by the export format).
  final Uint8List bytes;

  /// Optional accessibility label used by screen-readers. Defaults to
  /// a generic "预览图片" when omitted.
  final String? semanticLabel;

  /// Optional siblings shown alongside [bytes] inside the full-screen
  /// dialog so the user can swipe between them.
  ///
  /// When null (the single-image path — e.g. the stitch preview) the
  /// dialog opens with just [bytes] and no page navigation.
  /// When non-null (the multi-image grid path) the dialog opens
  /// at [initialIndex] inside the full list.
  final List<Uint8List>? allBytes;

  /// Page index used when [allBytes] is non-null. Ignored otherwise.
  final int initialIndex;

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
            child: ExtendedImage.memory(
              bytes,
              fit: BoxFit.contain,
              mode: ExtendedImageMode.none,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    final list = allBytes ?? [bytes];
    final startIndex = allBytes != null ? initialIndex : 0;
    showDialog<void>(
      context: context,
      // The full-screen dialog covers the entire viewport — there is
      // no visible barrier the user could tap, so `barrierDismissible`
      // is effectively dead. Keep it `false` to express intent.
      barrierDismissible: false,
      builder: (_) =>
          PreviewFullScreenDialog(bytes: list, initialIndex: startIndex),
    );
  }
}
