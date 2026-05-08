import 'image_import_failure.dart';
import 'imported_image.dart';

/// Sealed result type for an import attempt.
///
/// All four import sources funnel through this type so callers can
/// pattern-match exhaustively. The `partial` flag on [ImportSuccess]
/// signals that some candidate items were dropped (e.g. exceeded the
/// 20-image cap or failed MIME validation) while others succeeded —
/// callers typically show a warning snackbar but still take the
/// `images` list.
sealed class ImportResult {
  const ImportResult();
}

/// At least one [ImportedImage] was produced.
class ImportSuccess extends ImportResult {
  const ImportSuccess(this.images, {this.partial = false, this.skippedReason});

  /// The successfully imported images. Always non-empty for an
  /// [ImportSuccess]; an empty result becomes [ImportFailure] with
  /// [ImportCancelled].
  final List<ImportedImage> images;

  /// `true` when the original input contained more candidates than
  /// returned in [images] (truncation due to the 20-image cap or
  /// dropped invalid items).
  final bool partial;

  /// Human-readable reason explaining the truncation, present only
  /// when [partial] is `true`.
  final ImageImportFailure? skippedReason;
}

/// No images could be imported. The reason is in [failure].
class ImportFailure extends ImportResult {
  const ImportFailure(this.failure);

  final ImageImportFailure failure;
}
