/// Application-wide metadata constants surfaced by the About screen.
///
/// Aggregated as `static const` fields on a private-constructor class
/// (same convention as [Breakpoints] / [AppNavDestination]) so callers
/// reference values via `AppInfo.name` etc. and the type can't be
/// instantiated by mistake.
///
/// Version / build number live in `pubspec.yaml` and are read at runtime
/// via `package_info_plus` — they are intentionally NOT mirrored here.
class AppInfo {
  AppInfo._();

  /// Human-readable application name. Matches the in-app branding
  /// (`HomeScreen`'s AppBar wordmark and `MaterialApp.title`).
  static const String name = 'Fl PiCraft';

  /// Short one-line product description. Matches `pubspec.yaml`'s
  /// `description:` field so the About page stays in sync with the
  /// package manifest.
  static const String description = 'A picture craft for Flutter project.';

  /// Bundled asset path of the app icon used by the About screen and
  /// the [showLicensePage] header. Sourced from
  /// `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.webp` (192×192,
  /// alpha-baked launcher rounded shape) — see this task's PRD §D4 for
  /// the asset selection rationale.
  static const String iconAssetPath = 'assets/icon/app_icon.webp';

  /// Public GitHub source repository URL.
  static const String gitHubRepoUrl = 'https://github.com/RebornQ/fl_picraft';

  /// Public GitHub issues URL for user feedback / bug reports.
  static const String gitHubIssuesUrl =
      'https://github.com/RebornQ/fl_picraft/issues';
}
