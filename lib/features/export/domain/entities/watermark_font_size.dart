/// Preset font sizes the watermark UI exposes. Values map to pixel
/// heights consistent with the PRD (§5.5).
///
/// Numeric sizes outside this preset (8..48) can be expressed via the
/// `custom` factory in `WatermarkConfig` if the UI ever exposes a
/// numeric input.
enum WatermarkFontSize {
  small(12),
  medium(18),
  large(28);

  const WatermarkFontSize(this.pixels);

  /// Nominal pixel height of the rendered text. The rasterizer uses
  /// this to select the closest available bitmap font.
  final int pixels;
}

/// Hard limits surfaced to the UI layer for numeric font-size inputs.
/// Centralizing keeps validation in one place.
const int kMinWatermarkFontPixels = 8;
const int kMaxWatermarkFontPixels = 48;

/// Minimum logical font size before truncation kicks in. Below this
/// the rasterizer ellipsizes rather than shrinking further.
const int kWatermarkMinShrinkPixels = 8;
