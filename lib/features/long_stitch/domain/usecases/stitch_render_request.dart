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
  });

  final List<Uint8List> imageBytes;
  final StitchMode mode;
  final double spacing;
  final double borderWidth;
  final int borderColorArgb;
  final double cornerRadius;
  final StitchExportFormat format;
  final int jpegQuality;

  /// Convenience: build from the editor state. The export module
  /// (`05-08-export-watermark`) will swap [format] / [jpegQuality] in
  /// when it lands.
  factory StitchRenderRequest.fromState(
    StitchEditorState state, {
    StitchExportFormat format = StitchExportFormat.png,
    int jpegQuality = 92,
  }) {
    return StitchRenderRequest(
      imageBytes: [for (final i in state.images) i.bytes],
      mode: state.mode,
      spacing: state.spacing,
      borderWidth: state.border.width,
      borderColorArgb: _argb(state.border),
      cornerRadius: state.cornerRadius,
      format: format,
      jpegQuality: jpegQuality,
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
