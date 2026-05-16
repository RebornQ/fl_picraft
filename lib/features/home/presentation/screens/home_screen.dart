import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/breakpoints.dart';
import '../widgets/feature_card.dart';
import '../widgets/recent_works_grid.dart';
import '../widgets/tips_banner.dart';

/// Top-level home screen mounted at `/`.
///
/// Layout matches `_1_首页/code.html`: greeting header, two creative entry
/// cards (long stitch + grid split), tips banner, and a recent works grid.
///
/// Responsive behavior (driven by [windowSizeClassOf]):
///
/// | size class | feature cards | recent works grid |
/// |------------|---------------|-------------------|
/// | compact    | 1 column stacked | 3 columns         |
/// | medium     | 2 columns side-by-side | 3 columns         |
/// | expanded   | 2 columns side-by-side | 4 columns         |
/// | large      | 2 columns side-by-side | 4 columns         |
///
/// On all size classes the body is capped at [Breakpoints.maxContentWidth]
/// via a [ConstrainedBox] + [Center] so the page does not stretch to fill
/// ultra-wide monitors.
///
/// The bottom nav and `Scaffold` chrome are owned by the surrounding
/// `AppShell`; this screen returns only its body.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.maxContentWidth,
            ),
            child: const _HomeBody(),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sizeClass = windowSizeClassOf(context);
    final isCompact = sizeClass == WindowSizeClass.compact;
    final recentWorksColumns = switch (sizeClass) {
      WindowSizeClass.compact || WindowSizeClass.medium => 3,
      WindowSizeClass.expanded || WindowSizeClass.large => 4,
    };

    return ListView(
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
                tooltip: '通知（即将推出）',
                // Notification center is not part of the MVP — leave the
                // affordance visible (matches the mockup) but render it
                // disabled so users get the right "coming soon" cue.
                onPressed: null,
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
        // Feature cards — single column on compact, two-column row on
        // medium+ so the long-stitch and grid-split entry points fit
        // side-by-side without overflowing card content.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _FeatureCardsLayout(isCompact: isCompact),
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
                // The full works library is not part of the MVP — keep
                // the visual affordance but render it disabled so the
                // empty handler doesn't look like a bug.
                onPressed: null,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RecentWorksGrid(crossAxisCount: recentWorksColumns),
        ),
      ],
    );
  }
}

/// Lays out the two top-level feature cards as a stacked column on
/// compact widths and a side-by-side row on medium+ widths.
class _FeatureCardsLayout extends StatelessWidget {
  const _FeatureCardsLayout({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final longStitchCard = FeatureCard(
      title: '长图拼接',
      description: '将多张图片无缝拼接为竖向、横向或电影台词长图。',
      actionLabel: '导入新图片',
      icon: Icons.photo_library_outlined,
      onActionPressed: () => context.go('/stitch'),
    );
    final gridCard = FeatureCard(
      title: '宫格切图',
      description: '将图片切分为创意九宫格或自定义布局，非常适合社交媒体分享。',
      actionLabel: '导入新图片',
      icon: Icons.grid_view_outlined,
      primaryAction: false,
      onActionPressed: () => context.go('/grid'),
    );

    if (isCompact) {
      return Column(
        children: [longStitchCard, const SizedBox(height: 16), gridCard],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: longStitchCard),
          const SizedBox(width: 16),
          Expanded(child: gridCard),
        ],
      ),
    );
  }
}
