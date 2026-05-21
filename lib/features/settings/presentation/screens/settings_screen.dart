import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/placeholder_body.dart';

/// Top-level settings screen.
///
/// The settings surface is still mostly a stub — only the "关于" entry
/// is wired up so far. The existing [PlaceholderBody] is kept at the top
/// of the list so the screen still reads as "设置项即将推出" until real
/// preference rows land in a follow-up task. New entries should append
/// below `aboutTile` (per this task's PRD §Technical Approach).
///
/// The bottom nav and surrounding `Scaffold` chrome are owned by the
/// surrounding `AppShell`; this screen returns only its body + AppBar.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          children: [
            // Bounded height so the Center inside PlaceholderBody doesn't
            // receive an infinite-height constraint from the ListView's
            // viewport (ListView gives children unbounded main-axis space
            // by default).
            const SizedBox(
              height: 240,
              child: PlaceholderBody(
                icon: Icons.settings_outlined,
                title: '设置',
                description: '设置项即将推出。',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ],
        ),
      ),
    );
  }
}
