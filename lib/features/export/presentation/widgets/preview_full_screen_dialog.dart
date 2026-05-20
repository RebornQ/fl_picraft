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
/// Layout contract for the viewer (load-bearing — see the PRD bug fix
/// note in `.trellis/tasks/05-20-preview-ui/prd.md`):
///
/// * The [InteractiveViewer] fills the entire [Scaffold] body so pan /
///   zoom always operates against the **full-screen viewport**, not
///   the image's intrinsic display rect. If we wrapped the viewer in
///   `Center` instead, the parent constraints would be stripped and
///   the viewer would shrink to the image's `BoxFit.contain` rect —
///   leaving the magnified-out-of-rect regions un-pannable.
/// * [InteractiveViewer.boundaryMargin] is `EdgeInsets.all(double.infinity)`
///   so the user can pan freely after zoom-in (typical photo-viewer
///   feel — no hard wall against the visible viewport edge).
/// * The [Image.memory] sits inside a [Center] **inside** the viewer
///   so the image stays centered at the initial 1.0 scale.
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
        body: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: Center(
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
