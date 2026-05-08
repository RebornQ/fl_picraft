import 'dart:typed_data';

/// Library-agnostic representation of a single image candidate before
/// normalization.
///
/// Data sources (gallery, camera, clipboard, drag-drop) convert their
/// platform-specific result types into a list of [RawImageBytes] which
/// the repository then validates and decodes into [ImportedImage]s. This
/// keeps `image_picker` / `file_picker` / `super_clipboard` /
/// `super_drag_and_drop` types out of the domain and presentation layers.
class RawImageBytes {
  const RawImageBytes({
    required this.bytes,
    this.sourcePath,
    this.suggestedName,
    this.declaredMimeType,
  });

  /// Raw file bytes — may be a complete image file or a clipboard blob.
  final Uint8List bytes;

  /// Original on-disk path if the source provided one. `null` for
  /// clipboard / web blobs and for file_picker results that didn't
  /// surface a path (rare, but possible on web).
  final String? sourcePath;

  /// File name hint from the source (e.g. `IMG_0001.jpg`). May be used
  /// to fall back when sniffing magic bytes is inconclusive.
  final String? suggestedName;

  /// MIME type as reported by the source (e.g. `image/png` from
  /// `XFile.mimeType`). Treated as a hint — the normalizer always
  /// re-detects from the byte signature.
  final String? declaredMimeType;
}
