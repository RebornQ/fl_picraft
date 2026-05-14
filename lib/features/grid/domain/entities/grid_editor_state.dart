import '../../../image_import/domain/entities/imported_image.dart';
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
/// Immutable; mutate via [copyWith]. Carries a reserved
/// [nineGridSocialMode] flag so the sibling `05-08-nine-grid-social`
/// task can layer its center-cell replacement on top without forking
/// the state class.
class GridEditorState {
  const GridEditorState({
    required this.source,
    required this.gridType,
    required this.spacing,
    required this.cornerRadius,
    required this.nineGridSocialMode,
  });

  /// Default initial state. No source image, 3x3 grid, spacing 0,
  /// radius [kDefaultGridCornerRadius], social mode off.
  factory GridEditorState.initial() => const GridEditorState(
    source: null,
    gridType: GridType.g3x3,
    spacing: 0,
    cornerRadius: kDefaultGridCornerRadius,
    nineGridSocialMode: false,
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

  /// Reserved for the sibling `05-08-nine-grid-social` subtask. When
  /// `false` (default) the field has no effect; the social subtask
  /// will gate its center-cell-replacement UI on this flag and force
  /// [gridType] to 3x3 when active.
  final bool nineGridSocialMode;

  bool get hasSource => source != null;

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
  }) {
    return GridEditorState(
      source: clearSource ? null : (source ?? this.source),
      gridType: gridType ?? this.gridType,
      spacing: spacing ?? this.spacing,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      nineGridSocialMode: nineGridSocialMode ?? this.nineGridSocialMode,
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
        other.nineGridSocialMode == nineGridSocialMode;
  }

  @override
  int get hashCode =>
      Object.hash(source, gridType, spacing, cornerRadius, nineGridSocialMode);
}
