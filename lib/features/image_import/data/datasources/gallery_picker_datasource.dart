import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/raw_image_bytes.dart';

/// Data source for the system gallery picker.
///
/// On mobile and web (`image_picker.pickMultiImage`) the platform's
/// native picker handles multi-select with rich previews. On desktop
/// `image_picker` is unsupported, so we fall back to
/// `file_picker.pickFiles(type: FileType.image, allowMultiple: true)`
/// which uses the OS file dialog.
class GalleryPickerDataSource {
  GalleryPickerDataSource({
    ImagePicker? imagePicker,
    Future<FilePickerResult?> Function({
      required FileType type,
      required bool allowMultiple,
      required bool withData,
      List<String>? allowedExtensions,
    })?
    filePicker,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _filePicker = filePicker ?? _defaultFilePicker;

  final ImagePicker _imagePicker;

  /// Indirection so unit tests can inject a fake. The default just
  /// forwards to `FilePicker.platform.pickFiles`.
  final Future<FilePickerResult?> Function({
    required FileType type,
    required bool allowMultiple,
    required bool withData,
    List<String>? allowedExtensions,
  })
  _filePicker;

  static Future<FilePickerResult?> _defaultFilePicker({
    required FileType type,
    required bool allowMultiple,
    required bool withData,
    List<String>? allowedExtensions,
  }) {
    return FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: allowMultiple,
      withData: withData,
      allowedExtensions: allowedExtensions,
    );
  }

  /// `true` on macOS / Windows / Linux. We need this branch because
  /// `image_picker` doesn't ship a desktop implementation for
  /// multi-image selection.
  bool get _useFilePickerFallback {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Open the picker and return the user's selection.
  ///
  /// Returns an empty list if the user cancelled. Limits the result to
  /// [limit] entries before normalization (the repository enforces the
  /// 20-image hard cap from PRD §5.2 — passing it down here just lets
  /// platforms that support a native limit show the right cue).
  Future<List<RawImageBytes>> pickImages({required int limit}) async {
    if (_useFilePickerFallback) {
      return _pickViaFilePicker(limit: limit);
    }
    return _pickViaImagePicker(limit: limit);
  }

  Future<List<RawImageBytes>> _pickViaImagePicker({required int limit}) async {
    final files = await _imagePicker.pickMultiImage(limit: limit);
    if (files.isEmpty) return const [];

    return Future.wait(
      files.map((file) async {
        final bytes = await file.readAsBytes();
        return RawImageBytes(
          bytes: bytes,
          sourcePath: kIsWeb ? null : file.path,
          suggestedName: file.name,
          declaredMimeType: file.mimeType,
        );
      }),
    );
  }

  Future<List<RawImageBytes>> _pickViaFilePicker({required int limit}) async {
    final result = await _filePicker(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return const [];

    final files = result.files.take(limit);
    return [
      for (final f in files)
        if (f.bytes != null)
          RawImageBytes(
            bytes: f.bytes!,
            sourcePath: f.path,
            suggestedName: f.name,
            declaredMimeType: null,
          ),
    ];
  }
}
