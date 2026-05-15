import 'package:flutter/material.dart';

/// Responsive grid of recent works thumbnails used on the Home screen.
///
/// Currently renders [count] placeholder tiles; once the works library is
/// implemented this will be wired to a Riverpod provider exposing real
/// thumbnails. The Home screen drives [crossAxisCount] from
/// `windowSizeClassOf(context)` so tablet / desktop windows fit more
/// thumbnails per row.
class RecentWorksGrid extends StatelessWidget {
  const RecentWorksGrid({super.key, this.count, this.crossAxisCount = 3});

  /// Number of placeholder tiles to render. Defaults to a multiple of
  /// [crossAxisCount] so rows stay aligned at any size class.
  final int? count;

  /// How many tiles per row. Driven by the parent screen's responsive
  /// breakpoint logic.
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tileCount = count ?? crossAxisCount;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tileCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
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
