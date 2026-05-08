import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/raw_image_bytes.dart';

/// Data source for capturing a single photo with the device camera.
///
/// Backed by `image_picker.pickImage(source: ImageSource.camera)`.
/// Camera capture is intentionally **mobile-only** — the PRD's import
/// table marks it as iOS / Android only, and `image_picker` returns
/// `UnimplementedError` from desktop / web platforms.
class CameraCaptureDataSource {
  CameraCaptureDataSource({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// `true` on iOS / Android (the only platforms `image_picker` supports
  /// for camera capture).
  ///
  /// Static so callers (e.g. the Home screen) can toggle camera-related
  /// UI affordances without instantiating the data source.
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// Capture a photo and return its bytes.
  ///
  /// Returns `null` when the user cancels the camera UI. Throws
  /// [UnsupportedError] on platforms where camera capture isn't
  /// available (callers should guard with [isSupported]).
  Future<RawImageBytes?> capture() async {
    if (!isSupported) {
      throw UnsupportedError(
        'Camera capture is only supported on iOS and Android.',
      );
    }
    final file = await _imagePicker.pickImage(source: ImageSource.camera);
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return RawImageBytes(
      bytes: bytes,
      sourcePath: file.path,
      suggestedName: file.name,
      declaredMimeType: file.mimeType,
    );
  }
}
