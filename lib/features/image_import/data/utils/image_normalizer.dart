import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/imported_image.dart';

/// Files larger than this are decoded inside [Isolate.run] (via
/// [compute]) to keep the UI thread responsive (PRD constraint:
/// "Decode happens off the UI isolate for files >2MB").
@visibleForTesting
const int kDecodeIsolateThresholdBytes = 2 * 1024 * 1024;

/// Map from `image` package format -> IANA media type.
///
/// Kept in one place so the gallery / camera / clipboard / drag-drop
/// paths all surface the same MIME strings on identical bytes.
const Map<img.ImageFormat, String> _mimeByFormat = {
  img.ImageFormat.jpg: 'image/jpeg',
  img.ImageFormat.png: 'image/png',
  img.ImageFormat.gif: 'image/gif',
  img.ImageFormat.webp: 'image/webp',
  img.ImageFormat.tiff: 'image/tiff',
  img.ImageFormat.bmp: 'image/bmp',
  img.ImageFormat.ico: 'image/x-icon',
  img.ImageFormat.psd: 'image/vnd.adobe.photoshop',
  img.ImageFormat.pvr: 'image/x-pvr',
  img.ImageFormat.exr: 'image/x-exr',
  img.ImageFormat.tga: 'image/x-tga',
  img.ImageFormat.pnm: 'image/x-portable-anymap',
};

/// Pure result of decoding a byte buffer enough to satisfy
/// [ImportedImage]'s width / height / MIME requirements.
@immutable
class DecodedImageMetadata {
  const DecodedImageMetadata({
    required this.width,
    required this.height,
    required this.mimeType,
  });

  final int width;
  final int height;
  final String mimeType;
}

/// Pure-Dart helper extracted so it can run inside [compute].
///
/// Returns `null` when [bytes] aren't a recognized raster image. Uses
/// [Decoder.startDecode] to read just the header (avoiding full pixel
/// decode) so we get dimensions cheaply even on large files.
DecodedImageMetadata? decodeImageMetadata(Uint8List bytes) {
  // Smallest legitimate raster header in our format set is 8 bytes
  // (PNG magic). Anything shorter is guaranteed not an image, and the
  // `image` package's `isValidFile` checks are not bounds-safe on
  // sub-magic-length input.
  if (bytes.length < 8) return null;

  img.Decoder? decoder;
  try {
    decoder = img.findDecoderForData(bytes);
  } catch (_) {
    // Defensive: some decoders read past their magic prefix during the
    // sniff and throw RangeError on malformed input. Treat as "not an
    // image" rather than propagating.
    return null;
  }
  if (decoder == null) return null;

  img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    return null;
  }
  if (info == null) return null;

  return DecodedImageMetadata(
    width: info.width,
    height: info.height,
    mimeType: _mimeByFormat[decoder.format] ?? 'application/octet-stream',
  );
}

/// Stateless utility responsible for turning raw bytes into a validated
/// [ImportedImage].
///
/// Lives under `data/utils/` because it depends on the `image` package —
/// keeping it out of `domain/` preserves the rule that domain code only
/// uses pure Dart and Flutter primitives.
class ImageNormalizer {
  const ImageNormalizer({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Decode [bytes] into an [ImportedImage]. Returns `null` if the bytes
  /// don't represent a supported raster image format.
  ///
  /// Decoding happens inside [compute] when the buffer exceeds
  /// [kDecodeIsolateThresholdBytes] so the UI thread isn't blocked on
  /// large photos. In tests / pure-Dart callers there's no isolate
  /// support, so we fall back to in-thread decoding.
  Future<ImportedImage?> normalize(
    Uint8List bytes, {
    String? sourcePath,
    String? declaredMimeType,
  }) async {
    final metadata = await _decodeMetadata(bytes);
    if (metadata == null) return null;

    return ImportedImage(
      sourcePath: sourcePath,
      bytes: bytes,
      width: metadata.width,
      height: metadata.height,
      // Re-detect from magic bytes; ignore declaredMimeType when our
      // decoder disagrees (callers like image_picker sometimes report
      // generic 'application/octet-stream').
      mimeType: metadata.mimeType,
      importedAt: _now(),
    );
  }

  Future<DecodedImageMetadata?> _decodeMetadata(Uint8List bytes) {
    if (bytes.length >= kDecodeIsolateThresholdBytes) {
      // `compute` is unavailable in pure-Dart unit tests; fall back to
      // synchronous decoding when no Flutter binding is set up.
      try {
        return compute(decodeImageMetadata, bytes);
      } catch (_) {
        return Future.value(decodeImageMetadata(bytes));
      }
    }
    return Future.value(decodeImageMetadata(bytes));
  }
}
