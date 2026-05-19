import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/entities/imported_image.dart';

/// Files larger than this are decoded inside [Isolate.run] (via
/// [compute]) to keep the UI thread responsive (PRD constraint:
/// "Decode happens off the UI isolate for files >2MB").
@visibleForTesting
const int kDecodeIsolateThresholdBytes = 2 * 1024 * 1024;

/// JPEG re-encode quality used when baking EXIF Orientation. Chosen as
/// the visually-indistinguishable sweet spot — 100 produces noticeably
/// larger files for ~no perceptual gain over a single round-trip, while
/// values ≤ 90 start showing chroma block artifacts on smooth gradients.
/// See PRD R3 ("接近无损/高质量参数") for the requirement this satisfies.
const int _kJpegBakeQuality = 95;

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
    this.orientation = 1,
  });

  final int width;
  final int height;
  final String mimeType;

  /// EXIF Orientation tag value (1..8). Defaults to `1` (identity) when
  /// the format doesn't carry EXIF, the tag is missing, or the tag is
  /// unreadable. Values 2..8 indicate the source bytes are rotated
  /// and/or mirrored relative to how the user expects to see them
  /// (Flutter's `Image.memory` applies the rotation automatically, but
  /// the `image` package's header-only `startDecode` does not — see the
  /// 05-19 grid-split squish bug for the failure mode this field
  /// addresses).
  final int orientation;
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

  // Cheap JPEG-only EXIF orientation read. `decodeJpgExif` parses just
  // APP1 segments — it does NOT trigger Huffman decode of the image
  // body, so the fast path (orientation == 1) stays cheap on large
  // photos. Non-JPEG formats default to orientation 1; PNG/WebP/etc.
  // either don't ship EXIF in practice or aren't covered by our
  // bake/re-encode path anyway.
  var orientation = 1;
  if (decoder.format == img.ImageFormat.jpg) {
    try {
      final exif = img.decodeJpgExif(bytes);
      if (exif != null && exif.imageIfd.hasOrientation) {
        orientation = exif.imageIfd.orientation ?? 1;
      }
    } catch (_) {
      // Malformed EXIF — fall back to identity. The bytes will still
      // render correctly via Flutter's `Image.memory` because the
      // underlying SOF dimensions are valid; we just won't bake.
    }
  }

  return DecodedImageMetadata(
    width: info.width,
    height: info.height,
    mimeType: _mimeByFormat[decoder.format] ?? 'application/octet-stream',
    orientation: orientation,
  );
}

/// Single-argument request shape for [bakeOrientationToBytes] so it can
/// run under [compute] (which only accepts a top-level / static
/// function with a single isolate-serializable parameter).
@immutable
class BakeOrientationRequest {
  const BakeOrientationRequest({
    required this.bytes,
    required this.mimeType,
    required this.orientation,
  });

  final Uint8List bytes;
  final String mimeType;
  final int orientation;
}

/// Result of [bakeOrientationToBytes]: the rotated/flipped bytes plus
/// the post-bake dimensions (which differ from the input when the
/// source's EXIF Orientation is 5..8 — a 90°/270° rotation that swaps
/// width and height).
@immutable
class BakedImage {
  const BakedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Pure-Dart helper extracted so it can run inside [compute].
///
/// Decodes the source bytes (which pulls every pixel into memory via
/// `image:` — significantly more work than the header-only
/// [decodeImageMetadata]), applies the EXIF Orientation transform via
/// [img.bakeOrientation], and re-encodes back to the source MIME type.
/// JPEG is re-encoded at quality 95 to keep the visual delta minimal;
/// PNG is lossless so quality doesn't apply.
///
/// Returns `null` when:
///
/// * the MIME type isn't one we can both decode AND re-encode
///   (we only support `image/jpeg` and `image/png` — other formats
///   pass through unchanged because we don't ship encoders for them
///   in this layer),
/// * full-pixel decoding fails,
/// * re-encoding fails.
///
/// Callers fall back to the original bytes + raw metadata on `null`,
/// which preserves the pre-fix behavior (Flutter rotates on display,
/// metadata is technically wrong) rather than crashing the import.
///
/// Isolate-safe: imports only `dart:typed_data` (via the
/// `flutter/foundation.dart` re-export) and `package:image/image.dart`
/// — no Flutter binding, no `dart:ui`. See
/// `.trellis/spec/frontend/directory-structure.md` → "Pattern:
/// Isolate-safe rasterizer in `data/`".
BakedImage? bakeOrientationToBytes(BakeOrientationRequest request) {
  // Only formats we have an encoder for can round-trip.
  final canEncode =
      request.mimeType == 'image/jpeg' || request.mimeType == 'image/png';
  if (!canEncode) return null;

  // Orientation outside the EXIF-defined range (2..8) is a no-op for
  // `img.bakeOrientation` (its switch falls through), so we'd burn a
  // full decode/encode cycle for nothing. Cheap guard.
  if (request.orientation < 2 || request.orientation > 8) return null;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(request.bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  // `img.decodeImage` for JPEG (via `getImageFromJpeg`) already
  // applies the EXIF orientation to the pixel buffer AND clears the
  // `imageIfd.orientation` field on the returned Image's exif. For
  // PNG and other formats it won't have done that work, so we call
  // `bakeOrientation` defensively — it's a no-op when the exif is
  // already clean.
  final baked = img.bakeOrientation(decoded);

  Uint8List bytes;
  try {
    if (request.mimeType == 'image/jpeg') {
      // Quality kept at [_kJpegBakeQuality] to keep the JPEG-vs-JPEG
      // re-encode visually indistinguishable from the source while
      // still meaningfully smaller than the 100% setting. See PRD R3.
      bytes = Uint8List.fromList(
        img.encodeJpg(baked, quality: _kJpegBakeQuality),
      );
    } else {
      bytes = Uint8List.fromList(img.encodePng(baked));
    }
  } catch (_) {
    return null;
  }

  return BakedImage(bytes: bytes, width: baked.width, height: baked.height);
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

    var finalBytes = bytes;
    var finalWidth = metadata.width;
    var finalHeight = metadata.height;

    // EXIF Orientation bake — see top-of-file doc on
    // [bakeOrientationToBytes] for why and the fast-path criteria. The
    // typical photo path (orientation == 1) short-circuits here and
    // skips full decode + re-encode entirely (PRD R7).
    if (metadata.orientation >= 2 && metadata.orientation <= 8) {
      final baked = await _bake(
        BakeOrientationRequest(
          bytes: bytes,
          mimeType: metadata.mimeType,
          orientation: metadata.orientation,
        ),
      );
      if (baked != null) {
        finalBytes = baked.bytes;
        finalWidth = baked.width;
        finalHeight = baked.height;
      }
      // else: bake failed (decode/encode error, unsupported MIME). Fall
      // back to the original bytes + raw metadata — that preserves the
      // pre-fix display behavior (Flutter's `Image.memory` will still
      // apply the rotation visually). Better than dropping the import.
    }

    return ImportedImage(
      sourcePath: sourcePath,
      bytes: finalBytes,
      width: finalWidth,
      height: finalHeight,
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

  Future<BakedImage?> _bake(BakeOrientationRequest request) {
    if (request.bytes.length >= kDecodeIsolateThresholdBytes) {
      // Same isolate-fallback pattern as `_decodeMetadata`: `compute`
      // throws in pure-Dart unit tests where no Flutter binding is
      // bound, so we degrade gracefully to a synchronous call.
      try {
        return compute(bakeOrientationToBytes, request);
      } catch (_) {
        return Future.value(bakeOrientationToBytes(request));
      }
    }
    return Future.value(bakeOrientationToBytes(request));
  }
}
