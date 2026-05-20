import 'dart:typed_data';

import '../entities/export_format.dart';
import '../entities/export_request.dart';
import '../entities/save_result.dart';

/// Abstract contract for the export pipeline.
///
/// Implementations live in `data/repositories/`. Presentation code
/// depends on this interface so the export controller can stay
/// agnostic of `gal` / `file_picker` / `package:web` plugin imports.
abstract class ExportRepository {
  /// Compose, encode, and persist the request's source to the
  /// platform-native destination.
  ///
  /// For [StitchExportSource] returns a single [SaveResult].
  /// For [GridExportSource] returns a single aggregate result — the
  /// `count` field on [SaveSuccess] reflects how many cells were
  /// saved; any failure short-circuits and surfaces [SaveFailure].
  Future<SaveResult> exportAndSave(ExportRequest request);

  /// Persist already-processed (watermarked + encoded) bytes to the
  /// platform-native destination, skipping the watermark composite and
  /// re-encode steps.
  ///
  /// Used by the save path when the preview controller has already
  /// rendered identical bytes for the same input — the cache hit lets
  /// the user-visible save tap respond instantly instead of waiting on
  /// a redundant 1~2 s isolate hop.
  ///
  /// The caller is responsible for passing bytes produced from the
  /// same `(source, watermark, format, quality)` tuple — the
  /// implementation does not re-validate. Pass each grid cell's bytes
  /// in order; the implementation derives the per-cell suggested name
  /// from `processed.length`.
  Future<SaveResult> persistOnly(
    List<Uint8List> processed,
    ExportFormat format,
  );
}
