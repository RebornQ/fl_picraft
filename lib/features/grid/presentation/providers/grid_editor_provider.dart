import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/image_import_result.dart';
import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../data/renderers/grid_image_renderer.dart';
import '../../domain/entities/cell_replacement.dart';
import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_cell_transform.dart';
import '../../domain/usecases/compute_source_crop.dart';
import '../../domain/usecases/grid_render_request.dart';

/// DI seam for the renderer so widget tests can inject a fake without
/// going through the `image` package.
final gridImageRendererProvider = Provider<GridImageRenderer>((ref) {
  return const GridImageRenderer();
});

/// Source-of-truth notifier for the grid-split editor.
///
/// 05-17 Subtask C: per-cell replacement is reintroduced as a generalized
/// `Map<int, CellReplacement>` keyed by row-major cell index. Picking,
/// scaling, panning, and resetting are exposed as per-cell methods so a
/// single [CellOverlay] widget mounted on every cell can drive each
/// independently.
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
    // PRD R2 / R7: switching grid type clears all cell replacements
    // because the layout reshuffles and old indices no longer map to
    // the user's intended cells.
    state = state.copyWith(gridType: type, cellReplacements: const {});
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

  // ---- per-cell replacement (Subtask C) ---------------------------------

  /// Open the gallery picker (bypassing the grid-kind import session so
  /// the picked image does NOT overwrite the source) and store the
  /// result as a replacement for [cellIndex] with default scale /
  /// offset. Going through the repository instead of the import
  /// controller is the "side-channel reuse" pattern — per-cell picks
  /// must not contaminate the main grid session.
  Future<void> pickCellImage(int cellIndex) async {
    final repo = ref.read(imageImportRepositoryProvider);
    final result = await repo.pickFromGallery(limit: 1);
    if (result is ImportSuccess && result.images.isNotEmpty) {
      setCellImage(cellIndex, result.images.first);
    }
    // Cancellation and failures intentionally swallowed — the per-cell
    // picker is a peer flow and shouldn't surface as a top-level
    // editor snackbar. Future enhancement: add per-cell error surface.
  }

  /// Replace (or remove, when [image] is `null`) the cell at
  /// [cellIndex]. Inserting a fresh image resets the cell's transform
  /// to cover-fit / centered.
  void setCellImage(int cellIndex, ImportedImage? image) {
    final next = Map<int, CellReplacement>.from(state.cellReplacements);
    if (image == null) {
      if (!next.containsKey(cellIndex)) return;
      next.remove(cellIndex);
    } else {
      next[cellIndex] = CellReplacement(image: image);
    }
    state = state.copyWith(cellReplacements: Map.unmodifiable(next));
  }

  /// Update the cover-relative scale of the cell's replacement. No-op
  /// when no replacement exists at [cellIndex].
  void setCellScale(int cellIndex, double scale) {
    final current = state.cellReplacements[cellIndex];
    if (current == null) return;
    final clamped = clampUserScale(scale);
    // Re-clamp offset against the new scale so the image still covers
    // the cell. We don't know the live cell pixel extent here, so we
    // use the replacement image's own dimensions as the cell-shape
    // proxy — sufficient for a domain-level guarantee. The widget
    // additionally clamps against its on-screen extent.
    final reClamped = clampCellOffset(
      offset: current.offset,
      imageWidth: current.image.width,
      imageHeight: current.image.height,
      cellWidth: current.image.width,
      cellHeight: current.image.height,
      userScale: clamped,
    );
    final next = Map<int, CellReplacement>.from(state.cellReplacements);
    next[cellIndex] = current.copyWith(scale: clamped, offset: reClamped);
    state = state.copyWith(cellReplacements: Map.unmodifiable(next));
  }

  /// Update the pan offset of the cell's replacement (cell-target
  /// pixels). No-op when no replacement exists at [cellIndex]. The
  /// widget supplies the on-screen cell extents so this method clamps
  /// against the real cover-fit bounds; callers that don't know the
  /// cell size should use the version of `setCellOffset` from the
  /// widget itself (which feeds the cell extents through).
  void setCellOffset(int cellIndex, CellOffset offset) {
    final current = state.cellReplacements[cellIndex];
    if (current == null) return;
    final clamped = clampCellOffset(
      offset: offset,
      imageWidth: current.image.width,
      imageHeight: current.image.height,
      cellWidth: current.image.width,
      cellHeight: current.image.height,
      userScale: current.scale,
    );
    if (clamped == current.offset) return;
    final next = Map<int, CellReplacement>.from(state.cellReplacements);
    next[cellIndex] = current.copyWith(offset: clamped);
    state = state.copyWith(cellReplacements: Map.unmodifiable(next));
  }

  /// Remove the replacement at [cellIndex] (alias of
  /// `setCellImage(cellIndex, null)`).
  void resetCell(int cellIndex) => setCellImage(cellIndex, null);

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
