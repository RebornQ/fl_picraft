/// Supported output formats for the export pipeline.
///
/// Mirrors the JPG / PNG segmented buttons in the export-screen mockup
/// (`docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`
/// lines 145–156). JPG is the default to match the active state shown
/// in the mockup.
enum ExportFormat {
  png,
  jpg;

  /// File extension without the leading dot, e.g. `png`, `jpg`.
  String get extension {
    switch (this) {
      case ExportFormat.png:
        return 'png';
      case ExportFormat.jpg:
        return 'jpg';
    }
  }

  /// MIME type used by the web blob download path.
  String get mimeType {
    switch (this) {
      case ExportFormat.png:
        return 'image/png';
      case ExportFormat.jpg:
        return 'image/jpeg';
    }
  }

  /// True when this format exposes a quality knob to the user.
  ///
  /// PNG is lossless — its quality slider has no effect and is hidden
  /// in the UI. JPG is lossy and uses the slider value as the encoder
  /// quality (1–100).
  bool get supportsQuality {
    switch (this) {
      case ExportFormat.png:
        return false;
      case ExportFormat.jpg:
        return true;
    }
  }

  /// Short label rendered on the segmented button (matches the
  /// mockup's `JPG` / `PNG` labels).
  String get label {
    switch (this) {
      case ExportFormat.png:
        return 'PNG';
      case ExportFormat.jpg:
        return 'JPG';
    }
  }
}
