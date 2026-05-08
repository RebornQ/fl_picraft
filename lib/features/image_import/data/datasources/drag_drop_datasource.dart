import 'dart:async';

import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../domain/entities/raw_image_bytes.dart';

/// Image formats accepted from a drag-drop session, ordered by
/// preference. We accept the same set as the clipboard so the two
/// surfaces are interchangeable from the user's POV.
const List<SimpleFileFormat> _kAcceptedDropFormats = [
  Formats.png,
  Formats.jpeg,
  Formats.gif,
  Formats.webp,
  Formats.bmp,
  Formats.tiff,
  Formats.heic,
  Formats.heif,
];

/// Data source helper for `super_drag_and_drop`.
///
/// Doesn't host its own widget — `super_drag_and_drop` requires the
/// `DropRegion` to live in the widget tree. The presentation layer
/// (`ImageDropZone`) wires the `DropRegion` callbacks and delegates the
/// actual reading-bytes-from-DataReader work here so library imports
/// stay concentrated in `data/datasources/`.
class DragDropDataSource {
  const DragDropDataSource();

  /// Formats this data source knows how to extract; expose to the
  /// presentation widget so it can pass them to `DropRegion(formats:)`
  /// without re-importing `super_clipboard`.
  List<DataFormat> get acceptedFormats => _kAcceptedDropFormats;

  /// Decide whether to accept an in-flight drop given the formats
  /// currently advertised by the source. Returns
  /// [DropOperation.copy] when at least one image format is on offer,
  /// otherwise [DropOperation.none].
  DropOperation evaluateDropOver(DropOverEvent event) {
    final allowed = event.session.allowedOperations;
    final hasImage = event.session.items.any(
      (item) => _kAcceptedDropFormats.any(item.canProvide),
    );
    if (!hasImage) return DropOperation.none;
    if (allowed.contains(DropOperation.copy)) return DropOperation.copy;
    return allowed.firstOrNull ?? DropOperation.none;
  }

  /// Extract image bytes from a completed drop session. Items that
  /// aren't images (or fail to read) are skipped silently — the
  /// repository is responsible for surfacing the partial-success case.
  Future<List<RawImageBytes>> extractDroppedImages(
    PerformDropEvent event,
  ) async {
    final results = <RawImageBytes>[];
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;
      final raw = await _readFirstSupported(reader);
      if (raw != null) results.add(raw);
    }
    return results;
  }

  Future<RawImageBytes?> _readFirstSupported(DataReader reader) async {
    for (final format in _kAcceptedDropFormats) {
      if (!reader.canProvide(format)) continue;
      final raw = await _readFormat(reader, format);
      if (raw != null) return raw;
    }
    return null;
  }

  Future<RawImageBytes?> _readFormat(
    DataReader reader,
    SimpleFileFormat format,
  ) {
    final completer = Completer<RawImageBytes?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!completer.isCompleted) {
            completer.complete(
              RawImageBytes(
                bytes: bytes,
                sourcePath: null,
                suggestedName: file.fileName,
                declaredMimeType: _mimeForFormat(format),
              ),
            );
          }
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) {
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
    if (format == Formats.heic) return 'image/heic';
    if (format == Formats.heif) return 'image/heif';
    return null;
  }
}
