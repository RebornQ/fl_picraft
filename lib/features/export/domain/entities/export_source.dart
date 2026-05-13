import 'dart:typed_data';

/// Tagged union for the two payload shapes the export pipeline can
/// consume — a single composite image (long-stitch) or a list of cell
/// images (grid-split).
///
/// Sealed so the repository can exhaustively switch on the variant and
/// pick the right per-cell vs. single-shot branch.
sealed class ExportSource {
  const ExportSource();
}

/// Single composite image bytes produced by the long-stitch renderer.
class StitchExportSource extends ExportSource {
  const StitchExportSource(this.bytes);

  /// The encoded image bytes (PNG/JPG — format-agnostic, the encoder
  /// will re-encode in the user-selected output format).
  final Uint8List bytes;
}

/// Multiple cell images produced by the grid-split renderer. Each
/// cell will be watermarked, encoded, and saved as its own file.
class GridExportSource extends ExportSource {
  const GridExportSource(this.cells);

  final List<Uint8List> cells;
}
