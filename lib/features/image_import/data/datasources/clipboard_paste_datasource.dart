import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

import '../../domain/entities/raw_image_bytes.dart';

/// Image formats we attempt to read from the clipboard, in priority
/// order. PNG / JPEG cover the vast majority of "right-click → copy
/// image" flows; the rest are best-effort for desktop screenshot tools.
const List<SimpleFileFormat> _kImageFormats = [
  Formats.png,
  Formats.jpeg,
  Formats.gif,
  Formats.webp,
  Formats.bmp,
  Formats.tiff,
];

/// Data source for the system clipboard.
///
/// `SystemClipboard` is available on all platforms except Firefox where
/// the underlying API is gated behind a user pref — `instance` returns
/// `null` in that case and we surface that as a no-op.
class ClipboardPasteDataSource {
  /// Override hook for tests. When set, [readImages] uses this instead
  /// of `SystemClipboard.instance`.
  ClipboardPasteDataSource({ClipboardReader Function()? overrideReader})
    : _overrideReader = overrideReader;

  final ClipboardReader Function()? _overrideReader;

  /// Read all image items currently on the clipboard.
  ///
  /// Returns an empty list when the clipboard is empty, doesn't contain
  /// an image, or the clipboard API is unavailable on the current
  /// platform.
  Future<List<RawImageBytes>> readImages() async {
    final reader = await _readClipboard();
    if (reader == null) return const [];

    final results = <RawImageBytes>[];
    for (final item in reader.items) {
      final raw = await _extractImage(item);
      if (raw != null) results.add(raw);
    }
    return results;
  }

  Future<ClipboardReader?> _readClipboard() async {
    if (_overrideReader != null) return _overrideReader();
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    return clipboard.read();
  }

  Future<RawImageBytes?> _extractImage(ClipboardDataReader item) async {
    for (final format in _kImageFormats) {
      if (!item.canProvide(format)) continue;

      final bytes = await _readFile(item, format);
      if (bytes != null) {
        final suggested = await item.getSuggestedName();
        return RawImageBytes(
          bytes: bytes,
          // Clipboard items rarely carry a real path; super_clipboard
          // exposes only the data stream.
          sourcePath: null,
          suggestedName: suggested,
          declaredMimeType: _mimeForFormat(format),
        );
      }
    }
    return null;
  }

  Future<Uint8List?> _readFile(
    ClipboardDataReader item,
    SimpleFileFormat format,
  ) {
    final completer = Completer<Uint8List?>();
    final progress = item.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) {
      // Format not actually present despite canProvide returning true
      // (super_clipboard documents this can happen with synthesized
      // formats whose payload turns out to be empty).
      return Future.value(null);
    }
    return completer.future;
  }

  String? _mimeForFormat(SimpleFileFormat format) {
    if (format == Formats.png) return 'image/png';
    if (format == Formats.jpeg) return 'image/jpeg';
    if (format == Formats.gif) return 'image/gif';
    if (format == Formats.webp) return 'image/webp';
    if (format == Formats.bmp) return 'image/bmp';
    if (format == Formats.tiff) return 'image/tiff';
    return null;
  }
}
