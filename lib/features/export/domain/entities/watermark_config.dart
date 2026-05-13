import 'watermark_anchor.dart';
import 'watermark_font_size.dart';

/// Default watermark text matching the UI mockup
/// (`_4_导出页面/code.html` line 181, `value="Fl PiCraft"`).
const String kDefaultWatermarkText = 'Fl PiCraft';

/// Default opacity (50%) matching the mockup slider value.
const double kDefaultWatermarkOpacity = 0.5;

/// Default anchor (bottom-right) matching the highlighted button in
/// the mockup (`_4_导出页面/code.html` line 195).
const WatermarkAnchor kDefaultWatermarkAnchor = WatermarkAnchor.bottomRight;

/// PRD §5.5: max length is 40 characters.
const int kMaxWatermarkTextLength = 40;

/// Opacity slider bounds (10% – 100%), per PRD §5.5.
const double kMinWatermarkOpacity = 0.1;
const double kMaxWatermarkOpacity = 1.0;

/// Immutable configuration the export pipeline reads to compose the
/// optional text watermark.
///
/// Lives in `domain/` so it carries zero plugin imports and can be
/// shared across the UI (`presentation/`) and the rasterizer
/// (`data/`).
class WatermarkConfig {
  const WatermarkConfig({
    required this.enabled,
    required this.text,
    required this.anchor,
    required this.opacity,
    required this.fontSize,
  });

  /// Default initial state. Toggled OFF so the export pipeline is a
  /// no-op until the user explicitly opts in. Defaults still mirror
  /// the mockup so the toggle reveals a sensible preview.
  factory WatermarkConfig.initial() => const WatermarkConfig(
    enabled: false,
    text: kDefaultWatermarkText,
    anchor: kDefaultWatermarkAnchor,
    opacity: kDefaultWatermarkOpacity,
    fontSize: WatermarkFontSize.medium,
  );

  /// Master toggle — when `false` the rasterizer returns the source
  /// untouched.
  final bool enabled;

  /// User-supplied watermark text. Capped at [kMaxWatermarkTextLength]
  /// chars by the notifier; the rasterizer additionally treats an
  /// empty string as "disabled" so the user can clear the field
  /// without flipping the toggle.
  final String text;

  /// Which of the 9 corners/edges the watermark snaps to.
  final WatermarkAnchor anchor;

  /// Alpha multiplier, range [kMinWatermarkOpacity]–[kMaxWatermarkOpacity].
  final double opacity;

  /// Nominal font size preset.
  final WatermarkFontSize fontSize;

  /// True only when the rasterizer should actually composite a glyph.
  /// Used by the rasterizer and the live preview alike so both share
  /// the "empty text == disabled" rule.
  bool get hasVisibleWatermark => enabled && text.trim().isNotEmpty;

  WatermarkConfig copyWith({
    bool? enabled,
    String? text,
    WatermarkAnchor? anchor,
    double? opacity,
    WatermarkFontSize? fontSize,
  }) {
    return WatermarkConfig(
      enabled: enabled ?? this.enabled,
      text: text ?? this.text,
      anchor: anchor ?? this.anchor,
      opacity: opacity ?? this.opacity,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WatermarkConfig &&
        other.enabled == enabled &&
        other.text == text &&
        other.anchor == anchor &&
        other.opacity == opacity &&
        other.fontSize == fontSize;
  }

  @override
  int get hashCode => Object.hash(enabled, text, anchor, opacity, fontSize);

  @override
  String toString() =>
      'WatermarkConfig(enabled: $enabled, text: "$text", anchor: $anchor, '
      'opacity: $opacity, fontSize: $fontSize)';
}
