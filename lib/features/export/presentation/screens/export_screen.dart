import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../widgets/watermark_card.dart';

/// Export screen scaffold. The full export pipeline (format / quality
/// pickers, save action) lands in the sibling `05-08-export-multiplatform`
/// task; this iteration only wires up the watermark section so it can
/// be reviewed in isolation.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      appBar: AppBar(title: const Text('导出')),
      child: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: WatermarkCard(),
        ),
      ),
    );
  }
}
