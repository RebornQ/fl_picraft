import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../widgets/format_quality_card.dart';
import '../widgets/save_action_button.dart';
import '../widgets/save_disclaimer.dart';
import '../widgets/watermark_card.dart';

/// Export screen — composes format / quality picker, watermark
/// settings, save CTA, and the local-processing disclaimer.
///
/// Source plumbing currently pulls from the long-stitch editor's
/// state via the export controller. The grid-split hook-in lands
/// with `05-08-grid-split`; until then, navigating here from the
/// grid editor surfaces a "No images to export" error toast.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('导出')),
      child: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(child: FormatQualityCard()),
            SizedBox(height: 16),
            _SectionCard(child: WatermarkCard()),
            SizedBox(height: 16),
            SaveActionButton(),
            SizedBox(height: 16),
            SaveDisclaimer(),
          ],
        ),
      ),
    );
  }
}

/// Visual wrapper that gives each settings section the rounded
/// "surface-container" look from the mockup's right-hand panel.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
