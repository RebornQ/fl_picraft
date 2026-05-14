import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scaffold.dart';
import '../../../export/domain/entities/export_format.dart';
import '../../../export/domain/entities/export_quality.dart';
import '../../../export/domain/entities/export_request.dart';
import '../../../export/domain/entities/export_source.dart';
import '../../../export/domain/entities/save_result.dart';
import '../../../export/presentation/providers/export_controller.dart';
import '../../../export/presentation/providers/watermark_config_provider.dart';
import '../../../image_import/presentation/widgets/image_drop_zone.dart';
import '../providers/grid_editor_provider.dart';
import '../widgets/grid_parameter_cards.dart';
import '../widgets/grid_preview_canvas.dart';
import '../widgets/grid_type_selector.dart';

/// Grid-split editor screen.
///
/// Layout (top → bottom, matching `_3_宫格切图/code.html`):
/// 1. AppBar with back + title + import action
/// 2. Square preview canvas with grid overlay
/// 3. Grid type selector (11 cards, horizontal scroll)
/// 4. Bento parameter cards (spacing, corner radius)
/// 5. FAB to export every cell as a PNG
///
/// The body is wrapped in [ImageDropZone] so desktop / web users can
/// drag-drop a new source image at any point.
class GridEditorScreen extends ConsumerWidget {
  const GridEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gridEditorControllerProvider);
    final notifier = ref.read(gridEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppScaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          '宫格切图编辑',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '导入图片',
            onPressed: () => notifier.addFromGallery(),
          ),
        ],
      ),
      floatingActionButton: state.hasSource
          ? FloatingActionButton.extended(
              onPressed: () => _onExportPressed(context, ref),
              tooltip: '导出每张子图',
              icon: const Icon(Icons.output),
              label: const Text('导出'),
            )
          : null,
      child: ImageDropZone(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const GridPreviewCanvas(),
            if (state.sourceTooSmall) ...[
              const SizedBox(height: 12),
              _SourceSizeWarning(
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ],
            const SizedBox(height: 16),
            // Nine-grid-social mode toggle is rendered as a reserved
            // row so the sibling task can extend it without disturbing
            // the layout. It is non-interactive in this task (the
            // social subtask owns the center-cell replacement UX).
            _NineGridSocialRow(
              enabled: state.nineGridSocialMode,
              onChanged: notifier.setNineGridSocialMode,
            ),
            const SizedBox(height: 16),
            GridTypeSelector(
              value: state.gridType,
              onChanged: notifier.setGridType,
            ),
            const SizedBox(height: 16),
            const GridParameterCards(),
          ],
        ),
      ),
    );
  }

  Future<void> _onExportPressed(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = ref.read(gridEditorControllerProvider);
    if (!state.hasSource) return;

    messenger.showSnackBar(const SnackBar(content: Text('正在生成宫格子图...')));
    try {
      final cells = await ref
          .read(gridEditorControllerProvider.notifier)
          .renderCells();
      final repository = ref.read(exportRepositoryProvider);
      final request = ExportRequest(
        source: GridExportSource(cells),
        format: ExportFormat.png,
        quality: kMaxExportQuality,
        watermark: ref.read(watermarkConfigProvider),
      );
      final result = await repository.exportAndSave(request);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(_snackBarFor(result, context, cells.length));
    } catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  SnackBar _snackBarFor(SaveResult result, BuildContext context, int total) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (result) {
      case SaveSuccess(:final location, :final count):
        final where = location ?? '本地';
        return SnackBar(
          content: Text('已保存 $count/$total 张到 $where'),
          behavior: SnackBarBehavior.floating,
        );
      case SaveCancelled():
        return const SnackBar(
          content: Text('已取消导出'),
          behavior: SnackBarBehavior.floating,
        );
      case SaveFailure(:final message):
        return SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.errorContainer,
        );
    }
  }
}

class _SourceSizeWarning extends StatelessWidget {
  const _SourceSizeWarning({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '图片过小，子图可能模糊',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reserved row for the nine-grid-social toggle. Stays interactive so
/// users discover the upcoming mode, but in this task it merely flips
/// the [GridEditorState.nineGridSocialMode] flag without changing the
/// editor behavior — the sibling `05-08-nine-grid-social` task owns
/// the center-cell replacement UI.
class _NineGridSocialRow extends StatelessWidget {
  const _NineGridSocialRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '九宫格朋友圈模式',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '开启 3x3 布局并支持中心图片替换',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
