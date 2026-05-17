import 'dart:typed_data';

import '../entities/grid_editor_state.dart';
import '../entities/grid_type.dart';
import 'compute_center_transform.dart';
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
    this.nineGridSocialMode = false,
    this.centerImageBytes,
    this.centerScale = kDefaultCenterScale,
    this.centerOffset = kCenterOffsetZero,
    this.sourceOffset = kDefaultSourceOffset,
    this.sourceScale = kDefaultSourceScale,
  });

  final Uint8List sourceBytes;
  final GridType gridType;
  final double spacing;
  final double cornerRadius;

  /// `true` when the user has enabled the nine-grid-social toggle and
  /// the grid type is `3x3`. Triggers PRD §4.2 step 1 — the renderer
  /// centre-crops the source to its shortest-side square before laying
  /// out the 9 cells, so the output is always 9 *equal squares* as the
  /// spec requires. Independent of [centerImageBytes]: the crop still
  /// runs when the user toggles the mode on but has not yet picked a
  /// replacement (PRD edge case L66).
  final bool nineGridSocialMode;

  /// Optional replacement image for the 9-grid social mode's center
  /// cell. When `null` the renderer keeps the original 5th cell —
  /// allowing the social toggle to be flipped on before the user picks
  /// a replacement (PRD edge case L66).
  final Uint8List? centerImageBytes;

  /// User-controlled scale for [centerImageBytes]. Ignored when
  /// [centerImageBytes] is `null`.
  final double centerScale;

  /// User-controlled pan offset for [centerImageBytes]. Ignored when
  /// [centerImageBytes] is `null`.
  final CenterOffset centerOffset;

  /// Normalized center of the user-selected square crop (PRD ST-C,
  /// R-RENDER-01). The renderer carves this square out of the source
  /// **before** running `computeGridLayout`, so every grid mode (social
  /// or not) operates on a 1:1 region.
  final SourceOffset sourceOffset;

  /// Cover-relative scale of the user-selected square crop, in `[1.0,
  /// 4.0]`. `1.0` = the largest inscribed square; `4.0` = zoom in 4x.
  final double sourceScale;

  /// `true` when the renderer should compose [centerImageBytes] into
  /// the 5th cell. Implied — kept as a computed getter rather than a
  /// separate flag so callers can't accidentally desync the two.
  bool get hasCenterReplacement =>
      gridType == GridType.g3x3 &&
      centerImageBytes != null &&
      centerImageBytes!.isNotEmpty;

  /// Convenience: build from the editor state. Throws when the state
  /// has no source image — callers must check `state.hasSource` first.
  factory GridRenderRequest.fromState(GridEditorState state) {
    final src = state.source;
    if (src == null) {
      throw StateError('GridRenderRequest.fromState: state has no source');
    }
    final socialMode =
        state.nineGridSocialMode && state.gridType == GridType.g3x3;
    final usesCenter = socialMode && state.centerImage != null;
    return GridRenderRequest(
      sourceBytes: src.bytes,
      gridType: state.gridType,
      spacing: state.spacing,
      cornerRadius: state.cornerRadius,
      nineGridSocialMode: socialMode,
      centerImageBytes: usesCenter ? state.centerImage!.bytes : null,
      centerScale: state.centerScale,
      centerOffset: state.centerOffset,
      sourceOffset: state.sourceOffset,
      sourceScale: state.sourceScale,
    );
  }
}
