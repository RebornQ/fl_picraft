import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/placeholder_body.dart';

/// Placeholder for the grid-split editor (real implementation lives in the
/// `05-08-grid-split` task).
class GridEditorScreen extends ConsumerWidget {
  const GridEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('宫格切图')),
      child: const PlaceholderBody(
        icon: Icons.grid_view_outlined,
        title: '宫格切图',
        description: '此功能将在 05-08-grid-split 任务中实现。',
      ),
    );
  }
}
