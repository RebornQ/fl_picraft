/// Layout strategy used by the long-stitch editor.
///
/// Modeled as an extensible enum so future modes (e.g. `movieSubtitle`,
/// added by the sibling `05-08-movie-subtitle` task) can be appended
/// without breaking existing call sites — every consumer must handle
/// every variant via an exhaustive `switch`.
enum StitchMode {
  /// Images are scaled to a common width and stacked top-to-bottom.
  vertical,

  /// Images are scaled to a common height and laid out left-to-right.
  horizontal,
}

/// Human-readable label used by the segmented control. Centralized here
/// so the UI layer never bakes in raw enum strings.
extension StitchModeLabel on StitchMode {
  String get displayLabel {
    switch (this) {
      case StitchMode.vertical:
        return '竖向';
      case StitchMode.horizontal:
        return '横向';
    }
  }
}
