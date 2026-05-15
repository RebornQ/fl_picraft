import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../grid/domain/entities/grid_type.dart';
import '../../../grid/presentation/providers/grid_editor_provider.dart';
import '../../../long_stitch/presentation/providers/stitch_editor_provider.dart';
import '../../data/datasources/gallery_saver_datasource.dart';

/// Which editor a pending export should pull from.
///
/// Set by the editor screen immediately before navigating to `/export`
/// (see `grid_editor_screen.dart` and `stitch_editor_screen.dart`); the
/// export controller dispatches its render + persist pipeline on the
/// value at save time so a single `/export` route services both flows.
enum ExportSourceKind { stitch, grid }

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

/// Copy for the export-screen save CTA in its **idle** state.
///
/// Reads the active source kind and (for grid) the cell count off
/// [GridEditorState.gridType] so the user knows up-front how many
/// files the save will produce. The "保存中…" in-flight copy is owned
/// by the button itself since it depends on transient state.
final exportSaveButtonLabelProvider = Provider<String>((ref) {
  final kind = ref.watch(currentExportSourceKindProvider);
  final mobile = GallerySaverDataSource.isSupported;
  switch (kind) {
    case ExportSourceKind.stitch:
      return mobile ? '保存至相册' : '保存到本地';
    case ExportSourceKind.grid:
      final type = ref.watch(gridEditorControllerProvider).gridType;
      final count = type.cellCount;
      return mobile ? '保存 $count 张至相册' : '保存 $count 张到本地';
  }
});
