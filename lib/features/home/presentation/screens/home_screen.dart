import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../widgets/feature_card.dart';
import '../widgets/recent_works_grid.dart';
import '../widgets/tips_banner.dart';

/// Top-level home screen mounted at `/`.
///
/// Layout matches `_1_首页/code.html`: greeting header, two creative entry
/// cards (long stitch + grid split), tips banner, and a recent works grid.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppScaffold(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Greeting header.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '你好，创作者',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '欢迎回来',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: '通知',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          // Section title.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Text(
              '今天想创作点什么？',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // Feature cards.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                FeatureCard(
                  title: '长图拼接',
                  description: '将多张图片无缝拼接为竖向、横向或电影台词长图。',
                  actionLabel: '导入新图片',
                  icon: Icons.photo_library_outlined,
                  onActionPressed: () => context.go('/stitch'),
                ),
                const SizedBox(height: 16),
                FeatureCard(
                  title: '宫格切图',
                  description: '将图片切分为创意九宫格或自定义布局，非常适合社交媒体分享。',
                  actionLabel: '导入新图片',
                  icon: Icons.grid_view_outlined,
                  primaryAction: false,
                  onActionPressed: () => context.go('/grid'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Tips banner.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TipsBanner(message: '您可以尝试"电影台词模式"，它能在保留底部文字区域的同时自动叠加拼接。'),
          ),
          const SizedBox(height: 24),
          // Recent works header.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最近作品',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Row(
                    children: [
                      Text(
                        '查看全部',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: RecentWorksGrid(),
          ),
        ],
      ),
    );
  }
}
