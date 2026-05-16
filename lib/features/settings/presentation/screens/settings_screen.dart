import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/placeholder_body.dart';

/// Stub settings screen. The real settings UI is out of scope for the base
/// architecture task and will be filled in by a future task.
///
/// The bottom nav and surrounding `Scaffold` chrome are owned by the
/// surrounding `AppShell`; this screen returns only its body + AppBar.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: const SafeArea(
        child: PlaceholderBody(
          icon: Icons.settings_outlined,
          title: '设置',
          description: '设置项即将推出。',
        ),
      ),
    );
  }
}
