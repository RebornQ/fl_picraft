import '../../../image_import/domain/entities/imported_image.dart';
import '../usecases/compute_center_transform.dart';
import '../usecases/compute_source_crop.dart';
import 'grid_type.dart';

/// Slider bounds surfaced to the UI. Centralizing keeps the parameter
/// cards and the controller in agreement on validation limits.
const double kMaxGridSpacing = 50;
const double kMaxGridCornerRadius = 48;

/// Initial corner radius (per prd L59 — `radius=12`).
const double kDefaultGridCornerRadius = 12;

/// Minimum source-image dimension before we warn the user that the
/// resulting cells will be very small (prd L75 edge case).
const int kMinSourceDimensionForGrid = 100;

/// Snapshot of every parameter the grid-split editor exposes.
///
/// Immutable; mutate via [copyWith]. The [nineGridSocialMode] flag plus
/// the [centerImage] / [centerScale] / [centerOffset] triplet drive the
/// sibling `05-08-nine-grid-social` subtask's center-cell-replacement
/// UX — they are inert (zero-effect) while social mode is off.
class GridEditorState {
  const GridEditorState({
    required this.source,
    required this.gridType,
    required this.spacing,
    required this.cornerRadius,
    required this.nineGridSocialMode,
    required this.centerImage,
    required this.centerScale,
    required this.centerOffset,
    required this.sourceOffset,
    required this.sourceScale,
  });

  /// Default initial state. No source image, 3x3 grid, spacing 0,
  /// radius [kDefaultGridCornerRadius], social mode off, no center
  /// replacement.
  factory GridEditorState.initial() => const GridEditorState(
    source: null,
    gridType: GridType.g3x3,
    spacing: 0,
    cornerRadius: kDefaultGridCornerRadius,
    nineGridSocialMode: false,
    centerImage: null,
    centerScale: kDefaultCenterScale,
    centerOffset: kCenterOffsetZero,
    sourceOffset: kDefaultSourceOffset,
    sourceScale: kDefaultSourceScale,
  );

  /// The source image being split. `null` until the user imports an
  /// image — UI uses this to render the empty state.
  final ImportedImage? source;

  /// Active grid type (one of the 11 PRD §4.1 variants).
  final GridType gridType;

  /// Gap (in pixels) between adjacent cells. 0–[kMaxGridSpacing].
  final double spacing;

  /// Corner radius applied to every cell. 0–[kMaxGridCornerRadius].
  final double cornerRadius;

  /// When `true` the editor locks [gridType] to 3x3 and exposes the
  /// center-cell-replacement UI (PRD §4.2 九宫格朋友圈切图).
  final bool nineGridSocialMode;

  /// User-picked replacement image for the center cell. `null` until
  /// the user invokes the picker. Ignored when [nineGridSocialMode] is
  /// `false`.
  final ImportedImage? centerImage;

  /// User-controlled scale factor for [centerImage]. Bounded by
  /// [kMinCenterScale] / [kMaxCenterScale]; the controller clamps it
  /// further when an image's aspect ratio would expose transparent
  /// area at 0.5x.
  final double centerScale;

  /// User-controlled pan offset for [centerImage], in source-image
  /// pixels measured in cell-local coordinates. Centered = `(0, 0)`.
  final CenterOffset centerOffset;

  /// Normalized [0,1] offset of the **center** of the square crop that
  /// the user picked via the canvas drag gesture (PRD ST-C, R-DRAG-01).
  /// `(0.5, 0.5)` = source center (default cover-fit crop).
  final SourceOffset sourceOffset;

  /// Cover-relative scale of the user-selected square crop. `1.0` = the
  /// largest inscribed square fits the source's shortest side; `4.0` =
  /// zoom in 4x. Bounded by [kMinSourceScale] / [kMaxSourceScale].
  final double sourceScale;

  bool get hasSource => source != null;
  bool get hasCenterImage => centerImage != null;

  /// `true` when the user's crop selection deviates from the defaults
  /// (cover-fit, centered). Used by the controls panel to gate the
  /// visibility of the "重置裁剪" button (PRD ST-C, AC6).
  bool get hasNonDefaultCrop =>
      sourceOffset != kDefaultSourceOffset ||
      sourceScale != kDefaultSourceScale;

  /// `true` when the social toggle is on **and** a replacement image
  /// has been picked. Convenience for the renderer / preview.
  bool get isSocialModeActiveWithReplacement =>
      nineGridSocialMode && centerImage != null;

  /// `true` when the source image is below the minimum recommended
  /// dimension on either axis — UI surfaces a warning copy.
  bool get sourceTooSmall {
    final s = source;
    if (s == null) return false;
    return s.width < kMinSourceDimensionForGrid ||
        s.height < kMinSourceDimensionForGrid;
  }

  GridEditorState copyWith({
    ImportedImage? source,
    bool clearSource = false,
    GridType? gridType,
    double? spacing,
    double? cornerRadius,
    bool? nineGridSocialMode,
    ImportedImage? centerImage,
    bool clearCenterImage = false,
    double? centerScale,
    CenterOffset? centerOffset,
    SourceOffset? sourceOffset,
    double? sourceScale,
  }) {
    return GridEditorState(
      source: clearSource ? null : (source ?? this.source),
      gridType: gridType ?? this.gridType,
      spacing: spacing ?? this.spacing,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      nineGridSocialMode: nineGridSocialMode ?? this.nineGridSocialMode,
      centerImage: clearCenterImage ? null : (centerImage ?? this.centerImage),
      centerScale: centerScale ?? this.centerScale,
      centerOffset: centerOffset ?? this.centerOffset,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceScale: sourceScale ?? this.sourceScale,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GridEditorState &&
        other.source == source &&
        other.gridType == gridType &&
        other.spacing == spacing &&
        other.cornerRadius == cornerRadius &&
        other.nineGridSocialMode == nineGridSocialMode &&
        other.centerImage == centerImage &&
        other.centerScale == centerScale &&
        other.centerOffset == centerOffset &&
        other.sourceOffset == sourceOffset &&
        other.sourceScale == sourceScale;
  }

  @override
  int get hashCode => Object.hash(
    source,
    gridType,
    spacing,
    cornerRadius,
    nineGridSocialMode,
    centerImage,
    centerScale,
    centerOffset,
    sourceOffset,
    sourceScale,
  );
}
