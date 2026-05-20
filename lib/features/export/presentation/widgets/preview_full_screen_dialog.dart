import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen preview dialog opened by tapping a [PreviewThumbnail].
///
/// Uses [Dialog.fullscreen] (Material 3's recommended shape for a
/// full-screen modal) wrapped around an [InteractiveViewer] so the user
/// can pinch-zoom and pan the rendered preview to inspect detail. The
/// top [AppBar] keeps a close button so the user can dismiss without
/// having to know about barrier taps / system back.
///
/// Dismissal:
/// * The close button → `Navigator.of(context).pop()`.
/// * `barrierDismissible: true` (set by the caller on `showDialog`) →
///   tapping outside the dialog dismisses.
/// * System back / iOS edge-swipe → routes through the dialog's own
///   navigator pop.
class PreviewFullScreenDialog extends StatelessWidget {
  const PreviewFullScreenDialog({super.key, required this.bytes});

  /// Encoded image bytes shown at full size inside the dialog.
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('预览'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
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
}
