import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../data/renderers/grid_image_renderer.dart';
import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_source_crop.dart';
import '../../domain/usecases/grid_render_request.dart';

/// DI seam for the renderer so widget tests can inject a fake without
/// going through the `image` package.
final gridImageRendererProvider = Provider<GridImageRenderer>((ref) {
  return const GridImageRenderer();
});

/// Source-of-truth notifier for the grid-split editor.
///
/// 05-17 Subtask B: the legacy nine-grid-social fields are gone — the
/// editor now treats every supported [GridType] uniformly with a
/// `targetAspect = cols / rows` crop. Subtask C will reintroduce per-cell
/// replacement on top of this geometry.
class GridEditorController extends Notifier<GridEditorState> {
  @override
  GridEditorState build() {
    // The grid editor consumes a single source image — by convention
    // the first imported image from the grid-scoped import session.
    // We listen so the editor picks up a new source when the user
    // re-imports. The stitch editor watches its own session — the two
    // never share state.
    const kind = ImageImportSessionKind.grid;
    final initial = ref.read(importedImagesProvider(kind));
    ref.listen<List<ImportedImage>>(importedImagesProvider(kind), (prev, next) {
      _syncSourceFromImports(next);
    });
    final source = initial.isNotEmpty ? initial.first : null;
    return GridEditorState.initial().copyWith(source: source);
  }

  void _syncSourceFromImports(List<ImportedImage> next) {
    if (next.isEmpty) {
      if (state.source != null) {
        state = state.copyWith(clearSource: true);
      }
      return;
    }
    final newSource = next.first;
    if (state.source == newSource) return;
    state = state.copyWith(source: newSource);
  }

  // ---- parameters --------------------------------------------------------

  void setGridType(GridType type) {
    if (state.gridType == type) return;
    state = state.copyWith(gridType: type);
  }

  void setSpacing(double px) {
    final clamped = px.clamp(0, kMaxGridSpacing).toDouble();
    if (state.spacing == clamped) return;
    state = state.copyWith(spacing: clamped);
  }

  void setCornerRadius(double px) {
    final clamped = px.clamp(0, kMaxGridCornerRadius).toDouble();
    if (state.cornerRadius == clamped) return;
    state = state.copyWith(cornerRadius: clamped);
  }

  // ---- canvas drag-select crop (ST-C) -----------------------------------

  double _currentTargetAspect() {
    final cols = state.gridType.cols;
    final rows = state.gridType.rows;
    if (rows <= 0) return 1.0;
    return cols / rows;
  }

  /// Update the normalized center of the user-selected crop rectangle.
  /// Re-clamped against the current scale / source aspect / grid aspect
  /// so the crop can never expose pixels outside the source.
  void setSourceOffset(SourceOffset offset) {
    final source = state.source;
    if (source == null) return;
    if (source.height <= 0) return;
    final clamped = clampSourceOffset(
      offset: offset,
      scale: state.sourceScale,
      sourceAspect: source.width / source.height,
      targetAspect: _currentTargetAspect(),
    );
    if (clamped == state.sourceOffset) return;
    state = state.copyWith(sourceOffset: clamped);
  }

  /// Update the cover-relative scale of the user-selected crop rectangle.
  /// Clamped to `[kMinSourceScale, kMaxSourceScale]`. The offset is
  /// re-clamped against the new scale so the crop stays inside the
  /// source.
  void setSourceScale(double scale) {
    final source = state.source;
    if (source == null) return;
    final clampedScale = clampSourceScale(scale);
    final clampedOffset = source.height <= 0
        ? state.sourceOffset
        : clampSourceOffset(
            offset: state.sourceOffset,
            scale: clampedScale,
            sourceAspect: source.width / source.height,
            targetAspect: _currentTargetAspect(),
          );
    if (clampedScale == state.sourceScale &&
        clampedOffset == state.sourceOffset) {
      return;
    }
    state = state.copyWith(
      sourceScale: clampedScale,
      sourceOffset: clampedOffset,
    );
  }

  /// Reset the drag-select crop to defaults (cover-fit, centered).
  /// Wired into the controls panel's "重置裁剪" button (PRD ST-C, AC6)
  /// and into [addFromGallery] when `replace: true`.
  void resetCrop() {
    if (state.sourceOffset == kDefaultSourceOffset &&
        state.sourceScale == kDefaultSourceScale) {
      return;
    }
    state = state.copyWith(
      sourceOffset: kDefaultSourceOffset,
      sourceScale: kDefaultSourceScale,
    );
  }

  // ---- import shortcuts -------------------------------------------------

  /// Append images via the gallery picker.
  ///
  /// When [replace] is `false` (default), the picked image is appended
  /// to the current grid-kind import session — the first image stays
  /// the source if one is already present. This matches the legacy
  /// behavior used by camera / clipboard / drag-drop import paths.
  ///
  /// When [replace] is `true`, the current grid-kind import session is
  /// cleared **before** the picker opens so the picked image lands as
  /// a fresh `next.first` and overwrites the previous source. The
  /// drag-select crop is reset alongside the session clear (PRD ST-C,
  /// R-DRAG-03) so the new image starts in cover-fit at the centre.
  /// Callers (see [GridEditorScreen]'s AppBar action) gate this branch
  /// behind a confirm dialog so a stray tap can't destroy work.
  Future<void> addFromGallery({bool replace = false}) async {
    final importNotifier = ref.read(
      imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
    );
    if (replace) {
      importNotifier.clear();
      resetCrop();
    }
    await importNotifier.pickFromGallery();
  }

  Future<void> addFromCamera() async {
    await ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
        )
        .captureFromCamera();
  }

  Future<void> pasteFromClipboard() async {
    await ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
        )
        .pasteFromClipboard();
  }

  /// Clear the editor (drops the source image too).
  void clear() {
    ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.grid).notifier,
        )
        .clear();
  }

  // ---- rendering --------------------------------------------------------

  /// Render every cell to its own PNG. Throws when the editor has no
  /// source image.
  Future<List<Uint8List>> renderCells() {
    if (!state.hasSource) {
      throw StateError('Cannot render: no source image in the editor.');
    }
    final renderer = ref.read(gridImageRendererProvider);
    return renderer.render(GridRenderRequest.fromState(state));
  }
}

final gridEditorControllerProvider =
    NotifierProvider<GridEditorController, GridEditorState>(
      GridEditorController.new,
    );
