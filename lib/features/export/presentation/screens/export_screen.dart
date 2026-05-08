import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/placeholder_body.dart';

/// Placeholder for the export screen (real implementation lives in the
/// `05-08-export-watermark` task).
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('导出')),
      child: const PlaceholderBody(
        icon: Icons.ios_share_outlined,
        title: '导出',
        description: '此功能将在 05-08-export-watermark 任务中实现。',
      ),
    );
  }
}
