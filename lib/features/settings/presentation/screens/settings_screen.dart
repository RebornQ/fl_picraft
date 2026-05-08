import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/placeholder_body.dart';

/// Stub settings screen. The real settings UI is out of scope for the base
/// architecture task and will be filled in by a future task.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('设置')),
      child: const PlaceholderBody(
        icon: Icons.settings_outlined,
        title: '设置',
        description: '设置项即将推出。',
      ),
    );
  }
}
