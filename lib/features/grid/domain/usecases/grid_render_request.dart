import 'dart:typed_data';

import '../entities/grid_editor_state.dart';
import '../entities/grid_type.dart';
import 'compute_source_crop.dart';

/// Serializable render request handed off to an isolate.
///
/// Keeps every field as a primitive / `Uint8List` so it can cross the
/// isolate boundary without leaking Flutter widgets into the data
/// layer (per `frontend/directory-structure.md` → "Pattern: Isolate-
/// safe rasterizer in `data/`").
class GridRenderRequest {
  const GridRenderRequest({
    required this.sourceBytes,
    required this.gridType,
    required this.spacing,
    required this.cornerRadius,
    this.sourceOffset = kDefaultSourceOffset,
    this.sourceScale = kDefaultSourceScale,
  });

  final Uint8List sourceBytes;
  final GridType gridType;
  final double spacing;
  final double cornerRadius;

  /// Normalized center of the user-selected crop rectangle (PRD ST-C,
  /// R-RENDER-01). The renderer carves this rect (sized to aspect
  /// `cols / rows`) out of the source **before** running
  /// `computeGridLayout`, so every grid mode operates on a region whose
  /// shape matches the canvas it will render onto.
  final SourceOffset sourceOffset;

  /// Cover-relative scale of the user-selected crop rectangle, in
  /// `[1.0, 4.0]`. `1.0` = the largest inscribed rectangle of aspect
  /// `cols / rows`; `4.0` = zoom in 4x.
  final double sourceScale;

  /// Convenience: build from the editor state. Throws when the state
  /// has no source image — callers must check `state.hasSource` first.
  factory GridRenderRequest.fromState(GridEditorState state) {
    final src = state.source;
    if (src == null) {
      throw StateError('GridRenderRequest.fromState: state has no source');
    }
    return GridRenderRequest(
      sourceBytes: src.bytes,
      gridType: state.gridType,
      spacing: state.spacing,
      cornerRadius: state.cornerRadius,
      sourceOffset: state.sourceOffset,
      sourceScale: state.sourceScale,
    );
  }
}
