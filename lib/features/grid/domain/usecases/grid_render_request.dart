import 'dart:typed_data';

import '../entities/grid_editor_state.dart';
import '../entities/grid_type.dart';

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
  });

  final Uint8List sourceBytes;
  final GridType gridType;
  final double spacing;
  final double cornerRadius;

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
    );
  }
}
