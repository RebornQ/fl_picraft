import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/placeholder_body.dart';

/// Placeholder for the long-stitch editor (real implementation lives in the
/// `05-08-long-stitch` task).
class StitchEditorScreen extends ConsumerWidget {
  const StitchEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('长图拼接')),
      child: const PlaceholderBody(
        icon: Icons.photo_library_outlined,
        title: '长图拼接',
        description: '此功能将在 05-08-long-stitch 任务中实现。',
      ),
    );
  }
}
