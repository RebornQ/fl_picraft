import 'package:flutter/material.dart';

/// Tinted info banner used on the Home screen to surface a "tip of the day".
///
/// Visual pattern lifted from `_1_首页/code.html` (lightbulb + tertiary
/// container tone with low opacity). Uses [Color.alphaBlend] to compose
/// the tertiary tint **on top of** the surface color so the banner
/// reads correctly in both light and dark schemes — a bare
/// `tertiaryContainer.withValues(alpha: 0.10)` would dissolve into the
/// dark surface and become invisible because the dark `tertiaryContainer`
/// itself is already a dark tone.
class TipsBanner extends StatelessWidget {
  const TipsBanner({super.key, required this.message, this.title = '小贴士'});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final tintedSurface = Color.alphaBlend(
      colorScheme.tertiaryContainer.withValues(alpha: 0.10),
      colorScheme.surface,
    );
    final tintedBorder = Color.alphaBlend(
      colorScheme.tertiaryContainer.withValues(alpha: 0.30),
      colorScheme.surface,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tintedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tintedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, size: 20, color: colorScheme.tertiary),
              const SizedBox(width: 8),
              Text(
                title,
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
