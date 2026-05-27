import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../grid/domain/entities/grid_type.dart';
import '../../../grid/presentation/providers/grid_editor_provider.dart';
import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../long_stitch/presentation/providers/stitch_editor_provider.dart';
import '../../data/datasources/gallery_saver_datasource.dart';
import 'export_controller.dart';
import 'preview_controller.dart';
import 'preview_state.dart';

/// Which editor a pending export should pull from.
///
/// Set by the editor screen immediately before navigating to `/export`
/// (see `grid_editor_screen.dart` and `stitch_editor_screen.dart`); the
/// export controller dispatches its render + persist pipeline on the
/// value at save time so a single `/export` route services both flows.
enum ExportSourceKind { stitch, grid }

/// Map an [ExportSourceKind] to the [ImageImportSessionKind] whose
/// import session feeds that editor.
///
/// The two enums happen to enumerate the same set of editors today but
/// are kept as independent types per `state-management.md` →
/// "Pattern: Per-mode session isolation via .family" (export sources
/// and import sessions are different concerns). This helper is the
/// single bridge point — any caller that needs to look up the import
/// session for an export source goes through here so the mapping stays
/// in one place.
ImageImportSessionKind sessionKindFor(ExportSourceKind kind) {
  return switch (kind) {
    ExportSourceKind.stitch => ImageImportSessionKind.stitch,
    ExportSourceKind.grid => ImageImportSessionKind.grid,
  };
}

/// Routing-state provider — flipped by editor screens just before they
/// navigate to `/export`. Defaults to [ExportSourceKind.stitch] so a
/// programmatic / deeplink visit to the export screen falls back to
/// the long-stitch source rather than crashing.
final currentExportSourceKindProvider = StateProvider<ExportSourceKind>((ref) {
  return ExportSourceKind.stitch;
});

/// `true` when the active export source has content to render. Drives
/// the save button's enabled state so the user can't tap "保存" on an
/// empty editor.
final canExportProvider = Provider<bool>((ref) {
  final kind = ref.watch(currentExportSourceKindProvider);
  switch (kind) {
    case ExportSourceKind.stitch:
      return ref.watch(stitchEditorControllerProvider).hasImages;
    case ExportSourceKind.grid:
      return ref.watch(gridEditorControllerProvider).hasSource;
  }
});

/// `true` when the user is allowed to commit the current save action.
///
/// 产品语义：在导出预览管线真正“完成”（[PreviewState] == [PreviewReady]）
/// 之前禁止保存——避免“看到的预览”与“保存到相册的产物”出现视觉错位，
/// 让用户清楚地知道保存对象就是预览中所见。
///
/// 条件叠加（按从严到松排序，命中第一个 false 即返回 false）：
/// 1. [previewControllerProvider] 必须落在 [PreviewReady]。
///    * [PreviewEmpty] / [PreviewLoading]（含 `staleBytes != null` 的
///      “重渲染中”态） / [PreviewError] 都不可保存。
///    * [PreviewError] 下用户必须先通过预览卡内的“重试”按钮
///      （见 `preview_card.dart` 的 `_ErrorView`）触发
///      `previewControllerProvider.notifier.refresh()`，恢复
///      [PreviewReady] 后才能保存。这条路径在 UI 上自闭环。
/// 2. [ExportState.isSaving] 必须为 `false`——避免并发触发 `save()` 二
///    次进入。
/// 3. [canExportProvider] 必须为 `true`。
///    * 理论上 [PreviewReady] 已蕴含 “editor 有内容” 这一前提（否则
///      preview controller 早已落到 [PreviewEmpty]），但显式保留这条
///      纵深防御让 (a) 读代码时三个条件并列清晰，(b) 单元测试可以独立
///      pin 这一项，(c) 未来若 [PreviewReady] 的语义发生扩展（例如允许
///      “没有 source 但缓存了过去帧” 的合法 ready），canExport 仍能兜底。
///
/// 与 sealed [PreviewState] 的耦合：直接 `is PreviewReady` 检查，**不
/// 经过** `AsyncValue.when` 包装。见
/// `.trellis/spec/frontend/state-management.md` →
/// "Pattern: `NotifierProvider<SealedState>` when the sealed already owns
/// loading/error"——sealed 已经穷举了 loading / error / empty，外面再裹
/// 一层 `AsyncValue` 会产生 4×4 的笛卡尔展开；派生 boolean 同样应该直
/// 接消费 sealed variant。
///
/// 可复用性：未来同主题 CTA（分享、批量导出预设、其它“需要等待预览准
/// 备好”的入口）可直接 `ref.watch(canSaveProvider)`，不必各自重新组合
/// 三条件。
final canSaveProvider = Provider<bool>((ref) {
  final preview = ref.watch(previewControllerProvider);
  if (preview is! PreviewReady) return false;
  if (ref.watch(exportControllerProvider.select((s) => s.isSaving))) {
    return false;
  }
  return ref.watch(canExportProvider);
});

/// Copy for the export-screen save CTA in its **idle** state.
///
/// Reads the active source kind and (for grid) the cell count off
/// [GridEditorState.gridType] so the user knows up-front how many
/// files the save will produce. The "保存中…" in-flight copy is owned
/// by the button itself since it depends on transient state.
///
/// **Web grid branch**: Per PRD §05-21-batch-export-all the Web grid
/// export bundles all cells into a single ZIP download (rather than
/// triggering N separate browser downloads). The button label calls
/// this out explicitly so the user knows what to expect before they
/// tap save — replaces the generic "保存 N 张到本地" copy with
/// "保存 N 张为 ZIP".
final exportSaveButtonLabelProvider = Provider<String>((ref) {
  final kind = ref.watch(currentExportSourceKindProvider);
  final mobile = GallerySaverDataSource.isSupported;
  switch (kind) {
    case ExportSourceKind.stitch:
      return mobile ? '保存至相册' : '保存到本地';
    case ExportSourceKind.grid:
      final type = ref.watch(gridEditorControllerProvider).gridType;
      final count = type.cellCount;
      if (kIsWeb) return '保存 $count 张为 ZIP';
      return mobile ? '保存 $count 张至相册' : '保存 $count 张到本地';
  }
});
