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
}
