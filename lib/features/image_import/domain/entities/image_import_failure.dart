/// Sealed failure hierarchy for the image import flow.
///
/// Used inside [ImportResult.failure] so callers can pattern-match on the
/// specific failure mode without inspecting strings. See
/// `.trellis/spec/frontend/type-safety.md` "Sealed Classes (Dart 3)".
sealed class ImageImportFailure {
  const ImageImportFailure();
}

/// User dismissed the system picker without selecting anything. Not really
/// an error — UI should silently no-op.
class ImportCancelled extends ImageImportFailure {
  const ImportCancelled();
}

/// The requested import source is not available on the current platform
/// (e.g. camera capture on desktop / web).
class UnsupportedSource extends ImageImportFailure {
  const UnsupportedSource(this.source);

  /// Short identifier for the source that wasn't available
  /// (e.g. `'camera'`, `'clipboard'`).
  final String source;
}

/// One or more candidate items did not contain valid image data
/// (wrong MIME type, undecodable bytes, etc.).
class InvalidImageData extends ImageImportFailure {
  const InvalidImageData(this.reason);

  final String reason;
}

/// Caller attempted to import more than the per-session cap (PRD §5.2).
/// The repository truncates rather than failing outright; this failure is
/// emitted alongside the truncated success so the UI can show a snackbar.
class TooManyImages extends ImageImportFailure {
  const TooManyImages({required this.attempted, required this.maxAllowed});

  final int attempted;
  final int maxAllowed;
}

/// OS denied access (camera or photo library permission rejection).
class PermissionDenied extends ImageImportFailure {
  const PermissionDenied(this.source);

  final String source;
}

/// Catch-all for unexpected exceptions surfaced from a data source.
class UnknownImportFailure extends ImageImportFailure {
  const UnknownImportFailure(this.message);

  final String message;
}
