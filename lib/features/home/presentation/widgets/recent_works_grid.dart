import 'package:flutter/material.dart';

/// 3-column grid of recent works thumbnails used on the Home screen.
///
/// Currently renders [count] placeholder tiles; once the works library is
/// implemented this will be wired to a Riverpod provider exposing real
/// thumbnails.
class RecentWorksGrid extends StatelessWidget {
  const RecentWorksGrid({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Icon(
            Icons.image_outlined,
            size: 32,
            color: colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
