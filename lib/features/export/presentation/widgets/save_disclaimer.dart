import 'package:flutter/material.dart';

/// Privacy disclaimer rendered below the save CTA.
///
/// Matches the mockup's "拼接后的图片将保存至本地相册。我们不会上传任何数据到
/// 服务器。" tile (`_4_导出页面/code.html` lines 210–215). Reassures the
/// user that the app is local-only (PRD §1 隐私要求). The inner icon
/// chip uses [Color.alphaBlend] over the surface so the tint stays
/// visible in dark mode (a flat `tertiaryContainer.withValues(alpha:
/// 0.2)` washes out against the dark scheme's already-dark tertiary).
class SaveDisclaimer extends StatelessWidget {
  const SaveDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconChipBg = Color.alphaBlend(
      colorScheme.tertiaryContainer.withValues(alpha: 0.2),
      colorScheme.surface,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconChipBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '所有处理均在本地完成，我们不会上传任何图片到服务器。高分辨率导出大约需要 2–3 秒。',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
