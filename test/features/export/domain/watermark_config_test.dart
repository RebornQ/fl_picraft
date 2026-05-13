import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_font_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatermarkConfig.initial', () {
    test('uses mockup defaults', () {
      final c = WatermarkConfig.initial();
      expect(c.enabled, isFalse);
      expect(c.text, kDefaultWatermarkText);
      expect(c.anchor, kDefaultWatermarkAnchor);
      expect(c.opacity, kDefaultWatermarkOpacity);
      expect(c.fontSize, WatermarkFontSize.medium);
    });
  });

  group('hasVisibleWatermark', () {
    test('false when disabled even with text', () {
      final c = WatermarkConfig.initial().copyWith(enabled: false, text: 'a');
      expect(c.hasVisibleWatermark, isFalse);
    });

    test('false when enabled but text is empty / whitespace', () {
      final c = WatermarkConfig.initial().copyWith(enabled: true, text: '   ');
      expect(c.hasVisibleWatermark, isFalse);
    });

    test('true when enabled and text has content', () {
      final c = WatermarkConfig.initial().copyWith(enabled: true, text: 'Hi');
      expect(c.hasVisibleWatermark, isTrue);
    });
  });

  group('copyWith / equality', () {
    test('copyWith updates only the given fields', () {
      final base = WatermarkConfig.initial();
      final next = base.copyWith(enabled: true, opacity: 0.9);
      expect(next.enabled, isTrue);
      expect(next.opacity, 0.9);
      expect(next.text, base.text);
      expect(next.anchor, base.anchor);
      expect(next.fontSize, base.fontSize);
    });

    test('equality + hash are content-based', () {
      final a = WatermarkConfig.initial();
      final b = WatermarkConfig.initial();
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(enabled: true);
      expect(c, isNot(a));
    });
  });
}
