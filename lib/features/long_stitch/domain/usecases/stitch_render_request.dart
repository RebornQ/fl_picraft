import 'dart:typed_data';

import '../entities/stitch_border.dart';
import '../entities/stitch_editor_state.dart';
import '../entities/stitch_mode.dart';

/// Serializable render request handed off to an isolate.
///
/// Keeps every field as a primitive / `Uint8List` so it can cross the
/// isolate boundary without leaking Flutter widgets into the data layer.
class StitchRenderRequest {
  const StitchRenderRequest({
    required this.imageBytes,
    required this.mode,
    required this.spacing,
    required this.borderWidth,
    required this.borderColorArgb,
    required this.cornerRadius,
    required this.format,
    required this.jpegQuality,
    required this.subtitleOnlyMode,
    required this.subtitleBandHeight,
    this.autoTrimBlackBars = false,
  });

  final List<Uint8List> imageBytes;
  final StitchMode mode;
  final double spacing;
  final double borderWidth;
  final int borderColorArgb;
  final double cornerRadius;
  final StitchExportFormat format;
  final int jpegQuality;

  /// Movie-subtitle flag-overlay (PRD §3.3). When `true` AND [mode] is
  /// vertical AND there are ≥2 images, the renderer crops each
  /// non-first image down to its bottom [subtitleBandHeight] band.
  final bool subtitleOnlyMode;
  final double subtitleBandHeight;

  /// When `true` and the movie-subtitle path is active, the renderer
  /// scans each decoded image for top / bottom letterbox bars and
  /// shrinks the band crops to skip them. Off by default; the field
  /// is inert outside subtitle mode.
  final bool autoTrimBlackBars;

  /// Convenience: build from the editor state.
  ///
  /// The stitch renderer always produces a working PNG (with optional
  /// JPEG fallback for the legacy direct-export path); the final
  /// user-visible format is decided by [encodeForExport] inside the
  /// export pipeline, not here. Defaults stay PNG / quality 92 so
  /// any caller that bypasses the export pipeline still gets a
  /// reasonable output.
  factory StitchRenderRequest.fromState(
    StitchEditorState state, {
    StitchExportFormat format = StitchExportFormat.png,
    int jpegQuality = 92,
  }) {
    // Convert the percent-based band height into the absolute scaled
    // pixels the layout / renderer consume. The first image's width is
    // the targetWidth, so its scaled height equals its native height.
    final firstScaledHeight = state.images.isEmpty
        ? 0
        : state.images.first.height;
    final bandPx = firstScaledHeight <= 0
        ? 1.0
        : (firstScaledHeight * state.subtitleBandHeightPercent)
              .clamp(1.0, double.infinity)
              .toDouble();
    return StitchRenderRequest(
      imageBytes: [for (final i in state.images) i.bytes],
      mode: state.mode,
      spacing: state.spacing,
      borderWidth: state.border.width,
      borderColorArgb: _argb(state.border),
      cornerRadius: state.cornerRadius,
      format: format,
      jpegQuality: jpegQuality,
      subtitleOnlyMode: state.subtitleOnlyMode,
      subtitleBandHeight: bandPx,
      autoTrimBlackBars: state.autoTrimBlackBars,
    );
  }

  static int _argb(StitchBorder border) {
    final c = border.color;
    // toARGB32() returns the canonical packed value irrespective of
    // whether `Color` is initialized via opacity or component channels.
    return c.toARGB32();
  }
}

/// Output container format for the stitched image.
enum StitchExportFormat { png, jpeg }
