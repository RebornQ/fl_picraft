import '../entities/image_import_result.dart';
import '../entities/raw_image_bytes.dart';

/// Maximum number of images allowed per import session (PRD §5.2).
///
/// Surfaced as a top-level constant so data sources passing a `limit`
/// argument and the repository's truncation logic share a single source
/// of truth.
const int kMaxImportSessionImages = 20;

/// Abstract contract for the image import flow.
///
/// Implementations live in `data/repositories/`. Presentation code MUST
/// depend on this interface (or the Riverpod provider that exposes it)
/// rather than the concrete implementation, so feature code never
/// imports `image_picker` / `file_picker` / `super_clipboard` /
/// `super_drag_and_drop` directly.
abstract class ImageImportRepository {
  /// Open the system gallery picker and return the user's selection.
  ///
  /// On mobile / web, backed by `image_picker.pickMultiImage`; on desktop,
  /// backed by `file_picker.pickFiles` with an image type filter.
  Future<ImportResult> pickFromGallery({int limit = kMaxImportSessionImages});

  /// Capture a single photo with the device camera.
  ///
  /// Returns [ImportFailure] with [UnsupportedSource] on platforms that
  /// don't expose a camera through `image_picker` (desktop / web).
  Future<ImportResult> captureFromCamera();

  /// Read an image from the system clipboard.
  ///
  /// Returns [ImportFailure] with [InvalidImageData] if the clipboard
  /// contents aren't a recognized raster image.
  Future<ImportResult> pasteFromClipboard();

  /// Normalize raw byte payloads (typically extracted from a
  /// `PerformDropEvent` by the drag-drop data source) into validated
  /// [ImportedImage]s.
  ///
  /// Exposed on the repository — rather than having the drop widget call
  /// the normalizer directly — so the 20-image cap and MIME validation
  /// stay in one place.
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw);
}
