import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/watermark_anchor.dart';
import '../../domain/entities/watermark_config.dart';
import '../../domain/entities/watermark_font_size.dart';

/// Single source of truth for the export-screen watermark settings.
///
/// Leaf provider: no dependencies on repositories or async data — the
/// notifier only manipulates an immutable [WatermarkConfig]. Consumers
/// in the export pipeline read the snapshot via `ref.read(
/// watermarkConfigProvider)` immediately before encoding.
class WatermarkConfigNotifier extends Notifier<WatermarkConfig> {
  @override
  WatermarkConfig build() => WatermarkConfig.initial();

  // ---- master toggle / text ---------------------------------------------

  void setEnabled(bool value) {
    if (state.enabled == value) return;
    state = state.copyWith(enabled: value);
  }

  /// Update the watermark text. Caps length at
  /// [kMaxWatermarkTextLength] so the rasterizer never sees an
  /// over-long string even if the input field's `maxLength` is
  /// bypassed (e.g. via programmatic paste).
  void setText(String value) {
    final next = value.length > kMaxWatermarkTextLength
        ? value.substring(0, kMaxWatermarkTextLength)
        : value;
    if (state.text == next) return;
    state = state.copyWith(text: next);
  }

  // ---- anchor / opacity / font size -------------------------------------

  void setAnchor(WatermarkAnchor anchor) {
    if (state.anchor == anchor) return;
    state = state.copyWith(anchor: anchor);
  }

  /// Clamp to [kMinWatermarkOpacity]–[kMaxWatermarkOpacity] so the
  /// slider can drive this directly without re-implementing bounds.
  void setOpacity(double value) {
    final clamped = value
        .clamp(kMinWatermarkOpacity, kMaxWatermarkOpacity)
        .toDouble();
    if (state.opacity == clamped) return;
    state = state.copyWith(opacity: clamped);
  }

  void setFontSize(WatermarkFontSize size) {
    if (state.fontSize == size) return;
    state = state.copyWith(fontSize: size);
  }
}

/// Public provider — wire this into the export screen and the
/// rasterizer.
final watermarkConfigProvider =
    NotifierProvider<WatermarkConfigNotifier, WatermarkConfig>(
      WatermarkConfigNotifier.new,
    );
