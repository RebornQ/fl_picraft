import '../../../image_import/domain/entities/imported_image.dart';
import '../usecases/compute_cell_transform.dart';

/// Per-cell replacement bundle.
///
/// When the user taps a cell and picks a replacement image, the editor
/// stores one of these in `GridEditorState.cellReplacements[i]`. The
/// renderer composes the cell from this bundle (`image` cropped /
/// transformed by `scale` + `offset`) instead of slicing the source.
///
/// Immutable; mutate via [copyWith].
///
/// **Scale convention**: cover-relative — `1.0` means the image just
/// fully covers the cell with no transparent border. See
/// `compute_cell_transform.dart`.
///
/// **Offset units**: cell-target pixels (positive `dx` shifts the image
/// right, positive `dy` shifts it down).
class CellReplacement {
  const CellReplacement({
    required this.image,
    this.scale = kDefaultCellScale,
    this.offset = kCellOffsetZero,
  });

  final ImportedImage image;
  final double scale;
  final CellOffset offset;

  CellReplacement copyWith({
    ImportedImage? image,
    double? scale,
    CellOffset? offset,
  }) {
    return CellReplacement(
      image: image ?? this.image,
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CellReplacement &&
        other.image == image &&
        other.scale == scale &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(image, scale, offset);

  @override
  String toString() =>
      'CellReplacement(image: $image, scale: $scale, offset: $offset)';
}
