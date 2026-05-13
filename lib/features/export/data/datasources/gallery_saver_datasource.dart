import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

import '../../domain/entities/save_result.dart';

/// Default album name on iOS / Android. PRD §5.4: "Album: 'Fl PiCraft'
/// if API allows".
const String kGalleryAlbumName = 'Fl PiCraft';

/// Saves bytes into the device's native Photos library via the `gal`
/// plugin.
///
/// Mobile-only (iOS / Android). Apply the **three-layer defense** from
/// `.trellis/spec/frontend/directory-structure.md` →
/// "Pattern: Platform-aware datasource dispatch":
///   1. UI hides the gallery entry point via [isSupported].
///   2. The repository short-circuits with [SaveFailure] before
///      calling this class on unsupported platforms.
///   3. [save] throws [UnsupportedError] as a last-line guarantee.
class GallerySaverDataSource {
  const GallerySaverDataSource();

  /// True only on iOS / Android — the only platforms `gal` ships
  /// implementations for.
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// Save [bytes] to the Photos library.
  ///
  /// * [fileName] should NOT include the file extension — `gal` adds
  ///   the right one from the bytes' magic numbers, and on iOS the
  ///   "image" extension is appended automatically.
  /// * [album] optionally pins the asset to a named album. Falls back
  ///   to the system library when null.
  ///
  /// Returns [SaveSuccess] on success, [SaveFailure] when the user
  /// denies the permission prompt or the platform refuses the save.
  /// Throws [UnsupportedError] if called on a non-mobile target.
  Future<SaveResult> save(
    Uint8List bytes, {
    required String fileName,
    String? album = kGalleryAlbumName,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'GallerySaverDataSource: not supported on '
        '${kIsWeb ? "web" : defaultTargetPlatform}.',
      );
    }

    final wantsAlbum = album != null && album.isNotEmpty;

    try {
      var granted = await Gal.hasAccess(toAlbum: wantsAlbum);
      if (!granted) {
        granted = await Gal.requestAccess(toAlbum: wantsAlbum);
      }
      if (!granted) {
        return const SaveFailure('Photos permission denied');
      }

      await Gal.putImageBytes(
        bytes,
        name: fileName,
        album: wantsAlbum ? album : null,
      );
      return SaveSuccess(location: wantsAlbum ? album : 'Photos');
    } on GalException catch (e) {
      return SaveFailure('Photos save failed: ${e.type.message}');
    } catch (e) {
      return SaveFailure('Photos save failed: $e');
    }
  }
}
