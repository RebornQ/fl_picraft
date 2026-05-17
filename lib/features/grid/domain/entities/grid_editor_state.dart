import '../../../image_import/domain/entities/imported_image.dart';
import '../usecases/compute_source_crop.dart';
import 'cell_replacement.dart';
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
/// Immutable; mutate via [copyWith]. Subtask C (05-17) generalizes the
/// legacy center-cell replacement into a per-cell `Map<int,
/// CellReplacement>` keyed by row-major cell index.
class GridEditorState {
  const GridEditorState({
    required this.source,
    required this.gridType,
    required this.spacing,
    required this.cornerRadius,
    required this.sourceOffset,
    required this.sourceScale,
    this.cellReplacements = const {},
  });

  /// Default initial state. No source image, 3x3 grid, spacing 0,
  /// radius [kDefaultGridCornerRadius].
  factory GridEditorState.initial() => const GridEditorState(
    source: null,
    gridType: GridType.g3x3,
    spacing: 0,
    cornerRadius: kDefaultGridCornerRadius,
    sourceOffset: kDefaultSourceOffset,
    sourceScale: kDefaultSourceScale,
    cellReplacements: {},
  );

  /// The source image being split. `null` until the user imports an
  /// image — UI uses this to render the empty state.
  final ImportedImage? source;

  /// Active grid type (one of the 5 PRD §4.1 variants — see
  /// [GridType]).
  final GridType gridType;

  /// Gap (in pixels) between adjacent cells. 0–[kMaxGridSpacing].
  final double spacing;

  /// Corner radius applied to every cell. 0–[kMaxGridCornerRadius].
  final double cornerRadius;

  /// Normalized [0,1] offset of the **center** of the rectangular crop
  /// (aspect `cols / rows`) that the user picked via the canvas drag
  /// gesture (PRD ST-C, R-DRAG-01). `(0.5, 0.5)` = source center
  /// (default cover-fit crop).
  final SourceOffset sourceOffset;

  /// Cover-relative scale of the user-selected crop. `1.0` = the
  /// largest inscribed rectangle of aspect `cols / rows` fits the
  /// source; `4.0` = zoom in 4x. Bounded by [kMinSourceScale] /
  /// [kMaxSourceScale].
  final double sourceScale;

  /// Per-cell replacement bundles keyed by row-major cell index.
  ///
  /// Empty by default; entries are added by [GridEditorController]'s
  /// per-cell APIs when the user picks a replacement image for a
  /// specific cell. Changing the active [GridType] clears this map
  /// (the cell layout reshuffles, so the old indices no longer make
  /// sense).
  ///
  /// Always treated as immutable — [copyWith] replaces the whole map
  /// rather than mutating it in place.
  final Map<int, CellReplacement> cellReplacements;

  bool get hasSource => source != null;

  /// `true` when the user's crop selection deviates from the defaults
  /// (cover-fit, centered). Used by the controls panel to gate the
  /// visibility of the "重置裁剪" button (PRD ST-C, AC6).
  bool get hasNonDefaultCrop =>
      sourceOffset != kDefaultSourceOffset ||
      sourceScale != kDefaultSourceScale;

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
    SourceOffset? sourceOffset,
    double? sourceScale,
    Map<int, CellReplacement>? cellReplacements,
  }) {
    return GridEditorState(
      source: clearSource ? null : (source ?? this.source),
      gridType: gridType ?? this.gridType,
      spacing: spacing ?? this.spacing,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceScale: sourceScale ?? this.sourceScale,
      cellReplacements: cellReplacements ?? this.cellReplacements,
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
        other.sourceOffset == sourceOffset &&
        other.sourceScale == sourceScale &&
        _mapEquals(other.cellReplacements, cellReplacements);
  }

  @override
  int get hashCode => Object.hash(
    source,
    gridType,
    spacing,
    cornerRadius,
    sourceOffset,
    sourceScale,
    Object.hashAllUnordered(
      cellReplacements.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

bool _mapEquals(Map<int, CellReplacement> a, Map<int, CellReplacement> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
