/// Which top-level editor mode owns an image-import session.
///
/// Used as the family key for the per-mode `imageImportControllerProvider`
/// and `importedImagesProvider` (see
/// `presentation/providers/image_import_provider.dart`). Each editor
/// (long-stitch, grid-split, …) carries its own independent session so
/// the user's import work in one editor never leaks into another.
///
/// ### Why a separate enum from `ExportSourceKind`?
///
/// `ExportSourceKind` (in `features/export/presentation/providers/export_dispatch.dart`)
/// happens to enumerate the same set of editors today, but its semantics
/// are different: it answers "which editor is the user exporting from?"
/// while this enum answers "which editor owns this import session?".
/// Future export sources (PDF-merge, social-template composer …) may not
/// carry an associated import session at all, which would make a shared
/// type awkward. Keeping the two enums independent is cheap and keeps
/// the concerns separated.
///
/// ### Stability contract
///
/// The names of these values become part of the Riverpod family cache
/// key. Renaming a value is a **breaking change** — every test override
/// that targets a specific family instance has to be updated, and any
/// persisted reference (none today, but watch out) would silently
/// re-bind to a different session. When adding a new editor mode, append
/// a new value here without touching existing ones.
enum ImageImportSessionKind {
  /// Long-stitch editor (vertical / horizontal / movie-subtitle modes).
  stitch,

  /// Grid-split editor (n×m cell split, nine-grid-social variant).
  grid,
}
