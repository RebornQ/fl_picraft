/// Default JPG quality. Matches the mockup slider's `value="85"`
/// attribute (`_4_导出页面/code.html` line 162).
const int kDefaultExportQuality = 85;

/// Slider bounds per the mockup's `min="1" max="100"` attributes.
const int kMinExportQuality = 1;
const int kMaxExportQuality = 100;

/// Clamp [value] to the valid quality range so the encoder never sees
/// out-of-spec input regardless of where it came from.
int clampExportQuality(int value) {
  if (value < kMinExportQuality) return kMinExportQuality;
  if (value > kMaxExportQuality) return kMaxExportQuality;
  return value;
}
