import 'package:flutter/services.dart';

import '../../domain/entities/image_import_failure.dart';
import '../../domain/entities/image_import_result.dart';
import '../../domain/entities/imported_image.dart';
import '../../domain/entities/raw_image_bytes.dart';
import '../../domain/repositories/image_import_repository.dart';
import '../datasources/camera_capture_datasource.dart';
import '../datasources/clipboard_paste_datasource.dart';
import '../datasources/gallery_picker_datasource.dart';
import '../utils/image_normalizer.dart';

/// Default [ImageImportRepository] implementation.
///
/// Composes the four data sources, runs all candidate bytes through
/// [ImageNormalizer], applies the 20-image cap, and turns the resulting
/// `(images, dropped?)` tuple into a sealed [ImportResult].
class ImageImportRepositoryImpl implements ImageImportRepository {
  ImageImportRepositoryImpl({
    GalleryPickerDataSource? galleryPicker,
    CameraCaptureDataSource? cameraCapture,
    ClipboardPasteDataSource? clipboardPaste,
    ImageNormalizer? normalizer,
  }) : _galleryPicker = galleryPicker ?? GalleryPickerDataSource(),
       _cameraCapture = cameraCapture ?? CameraCaptureDataSource(),
       _clipboardPaste = clipboardPaste ?? ClipboardPasteDataSource(),
       _normalizer = normalizer ?? const ImageNormalizer();

  final GalleryPickerDataSource _galleryPicker;
  final CameraCaptureDataSource _cameraCapture;
  final ClipboardPasteDataSource _clipboardPaste;
  final ImageNormalizer _normalizer;

  @override
  Future<ImportResult> pickFromGallery({
    int limit = kMaxImportSessionImages,
  }) async {
    try {
      final raw = await _galleryPicker.pickImages(limit: limit);
      if (raw.isEmpty) return const ImportFailure(ImportCancelled());
      return _normalizeAndPackage(raw, limit: limit);
    } on PlatformException catch (e) {
      return ImportFailure(_mapPlatformException(e, 'gallery'));
    } catch (e) {
      return ImportFailure(UnknownImportFailure(e.toString()));
    }
  }

  @override
  Future<ImportResult> captureFromCamera() async {
    if (!CameraCaptureDataSource.isSupported) {
      return const ImportFailure(UnsupportedSource('camera'));
    }
    try {
      final raw = await _cameraCapture.capture();
      if (raw == null) return const ImportFailure(ImportCancelled());
      return _normalizeAndPackage([raw], limit: 1);
    } on PlatformException catch (e) {
      return ImportFailure(_mapPlatformException(e, 'camera'));
    } catch (e) {
      return ImportFailure(UnknownImportFailure(e.toString()));
    }
  }

  @override
  Future<ImportResult> pasteFromClipboard() async {
    try {
      final raw = await _clipboardPaste.readImages();
      if (raw.isEmpty) {
        return const ImportFailure(
          InvalidImageData('Clipboard does not contain a supported image.'),
        );
      }
      return _normalizeAndPackage(raw, limit: kMaxImportSessionImages);
    } on PlatformException catch (e) {
      return ImportFailure(_mapPlatformException(e, 'clipboard'));
    } catch (e) {
      return ImportFailure(UnknownImportFailure(e.toString()));
    }
  }

  @override
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw) async {
    if (raw.isEmpty) return const ImportFailure(ImportCancelled());
    try {
      return await _normalizeAndPackage(raw, limit: kMaxImportSessionImages);
    } catch (e) {
      return ImportFailure(UnknownImportFailure(e.toString()));
    }
  }

  /// Decode each [RawImageBytes] into an [ImportedImage], drop entries
  /// that aren't valid raster images, and apply the per-session cap.
  ///
  /// Returns:
  /// - [ImportSuccess] with `partial=false` when every input survived.
  /// - [ImportSuccess] with `partial=true` when some inputs were
  ///   dropped due to MIME / cap violations.
  /// - [ImportFailure] with [InvalidImageData] when nothing survived.
  Future<ImportResult> _normalizeAndPackage(
    List<RawImageBytes> raw, {
    required int limit,
  }) async {
    final cap = limit.clamp(1, kMaxImportSessionImages);
    final attempted = raw.length;
    final truncated = raw.take(cap).toList();
    final overflowed = attempted > cap;

    final accepted = <ImportedImage>[];
    var invalid = 0;
    for (final r in truncated) {
      final image = await _normalizer.normalize(
        r.bytes,
        sourcePath: r.sourcePath,
        declaredMimeType: r.declaredMimeType,
      );
      if (image != null) {
        accepted.add(image);
      } else {
        invalid++;
      }
    }

    if (accepted.isEmpty) {
      return const ImportFailure(
        InvalidImageData('No supported image data was found.'),
      );
    }

    final partial = overflowed || invalid > 0;
    ImageImportFailure? skippedReason;
    if (overflowed) {
      skippedReason = TooManyImages(attempted: attempted, maxAllowed: cap);
    } else if (invalid > 0) {
      skippedReason = InvalidImageData(
        '$invalid of $attempted items were not valid images.',
      );
    }

    return ImportSuccess(
      List.unmodifiable(accepted),
      partial: partial,
      skippedReason: skippedReason,
    );
  }

  ImageImportFailure _mapPlatformException(PlatformException e, String source) {
    final code = e.code.toLowerCase();
    if (code.contains('permission') || code.contains('denied')) {
      return PermissionDenied(source);
    }
    return UnknownImportFailure(e.message ?? e.code);
  }
}
