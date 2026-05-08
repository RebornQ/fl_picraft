import 'dart:typed_data';

/// Normalized in-memory representation of an image brought into the app
/// through any supported import source (gallery, camera, clipboard,
/// drag-drop).
///
/// Downstream features (Long Stitch, Grid Split) consume this shape and
/// remain agnostic to where the bytes originated. See
/// `.trellis/tasks/05-08-image-import/prd.md` for the source-of-truth
/// definition.
class ImportedImage {
  const ImportedImage({
    this.sourcePath,
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.importedAt,
  });

  /// Original on-disk path when available. `null` for clipboard or web blob
  /// imports where the data was delivered as raw bytes only.
  final String? sourcePath;

  /// The decoded image bytes. Always populated so processing pipelines can
  /// work uniformly regardless of source.
  final Uint8List bytes;

  /// Pixel width of the decoded image.
  final int width;

  /// Pixel height of the decoded image.
  final int height;

  /// IANA media type (e.g. `image/png`, `image/jpeg`) inferred from the
  /// magic bytes via the `image` package.
  final String mimeType;

  /// Timestamp when the import was completed (used for sort order /
  /// debugging).
  final DateTime importedAt;

  /// Returns a copy with the supplied fields overridden.
  ImportedImage copyWith({
    String? sourcePath,
    Uint8List? bytes,
    int? width,
    int? height,
    String? mimeType,
    DateTime? importedAt,
  }) {
    return ImportedImage(
      sourcePath: sourcePath ?? this.sourcePath,
      bytes: bytes ?? this.bytes,
      width: width ?? this.width,
      height: height ?? this.height,
      mimeType: mimeType ?? this.mimeType,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ImportedImage &&
        other.sourcePath == sourcePath &&
        other.width == width &&
        other.height == height &&
        other.mimeType == mimeType &&
        other.importedAt == importedAt &&
        _bytesEqual(other.bytes, bytes);
  }

  @override
  int get hashCode => Object.hash(
    sourcePath,
    width,
    height,
    mimeType,
    importedAt,
    bytes.length,
  );

  @override
  String toString() {
    return 'ImportedImage('
        'sourcePath: $sourcePath, '
        'bytes: ${bytes.length}B, '
        'size: ${width}x$height, '
        'mimeType: $mimeType, '
        'importedAt: $importedAt'
        ')';
  }
}

/// Pure-Dart byte equality. Avoids pulling in `collection` for a single
/// helper.
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
