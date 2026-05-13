/// Outcome of persisting one (or all) exported file(s) to the
/// platform-native destination.
///
/// Sealed so the UI can exhaustively switch on the variants when
/// composing the snackbar copy without forgetting an edge case.
sealed class SaveResult {
  const SaveResult();
}

/// File(s) landed on disk / in the gallery without error.
class SaveSuccess extends SaveResult {
  const SaveSuccess({this.location, this.count = 1});

  /// Where the file landed. May be a fully-qualified path (desktop),
  /// a human-readable hint like "Photos" or "相册" (mobile), or
  /// "Downloads" (web). `null` when the platform exposes no path
  /// (rare).
  final String? location;

  /// How many files were saved. `1` for the stitch path, `n` for
  /// grid cells. The UI uses this to pluralize the snackbar.
  final int count;
}

/// User dismissed the save dialog. Treated separately from
/// [SaveFailure] so the UI can stay silent (no scary "error" toast
/// for a deliberate cancel).
class SaveCancelled extends SaveResult {
  const SaveCancelled();
}

/// Something went wrong — bubbled to the UI as an error snackbar.
class SaveFailure extends SaveResult {
  const SaveFailure(this.message);

  /// Human-readable reason. Already localized to the user's locale by
  /// the time it reaches this class (or a generic English fallback).
  final String message;
}
