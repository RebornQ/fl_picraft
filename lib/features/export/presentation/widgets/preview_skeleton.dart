import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Loading placeholder for the preview card.
///
/// 极简通用 loading 占位 —— `surfaceContainerLow` 背景 + 居中
/// [CircularProgressIndicator] + 下方文案。**不复用编辑器的任何 canvas
/// widget**（`StitchPreviewCanvas` / `GridPreviewCanvas`）。
///
/// 文案按 [staleBytes] 是否非空决定：
///
/// * **首次加载** (`staleBytes == null`) — "生成中..."
/// * **刷新** (`staleBytes != null`) — "重新生成中..."
///
/// PRD 决策路径（参见父任务 `prd.md` §Decision §D4 (revised twice
/// 2026-05-21)）：
///
/// * **Iteration 0 (设计阶段)**：stale 字节优先 + 首次 fallback widget canvas
/// * **Iteration 1 (上线后实测)**：发现 stale 帧太逼真会误导用户，改用 widget
///   canvas + `Opacity(0.6)` + chip —— 但 canvas 本身是"完整的预览图样貌"，
///   用户看到它仍会与"完成态"混淆，并且 canvas 会随用户在编辑器侧的源图
///   变化跳动，与"在加载中"语义脱节
/// * **Iteration 2 (本实现，最终方案)**：彻底放弃 cross-feature widget，
///   改用 Material 标准 spinner + 文案。视觉上**明显不像"完成的预览"**，
///   用户一眼知道是"在加载"；也不再随编辑器源图变化跳动；
///   `currentExportSourceKindProvider` 不再被本 widget watch，
///   减少了一次 cross-feature provider 依赖
///
/// [staleBytes] 字段仍然保留：它驱动文案差异（"生成中..." vs
/// "重新生成中..."），且 `PreviewLoading.staleBytes` 在 Subtask A 的 controller
/// 中保留不删，给未来 UX 实验（例如 picture-in-picture micro stale
/// thumbnail）保留扩展空间。
///
/// 真实预览到达后由父 [PreviewCard] 的 [AnimatedSwitcher] 淡入替换；
/// 本 widget 只负责 loading 视觉本身。
///
/// 错误状态下的 stale 半透明背景**不在本 widget 的职责范围内**，
/// 由父 `_ErrorView` 自行处理 —— Loading（无明确错误信号）和 Error
/// （有明确错误信号）在 "stale 是否会引发误解" 这一点上语义不同。
class PreviewSkeleton extends StatelessWidget {
  const PreviewSkeleton({super.key, this.staleBytes});

  /// Previously-rendered bytes, when the loading state was reached from
  /// `PreviewReady`. `null` on first entry. Only used to choose the
  /// "生成中..." vs "重新生成中..." copy — the visual body is identical in
  /// both cases (see class-level doc-comment for the rationale).
  final List<Uint8List>? staleBytes;

  @override
  Widget build(BuildContext context) {
    final hasStale = staleBytes != null && staleBytes!.isNotEmpty;
    final label = hasStale ? '重新生成中...' : '生成中...';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
