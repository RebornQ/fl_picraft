import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/image_import_result.dart';
import '../../../image_import/domain/entities/image_import_session_kind.dart';
import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../data/renderers/grid_image_renderer.dart';
import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/compute_center_transform.dart';
import '../../domain/usecases/compute_source_crop.dart';
import '../../domain/usecases/grid_render_request.dart';

/// DI seam for the renderer so widget tests can inject a fake without
/// going through the `image` package.
final gridImageRendererProvider = Provider<GridImageRenderer>((ref) {
  return const GridImageRenderer();
});

/// Source-of-truth notifier for the grid-split editor.
///
/// Carries the nine-grid-social subtask's center-cell replacement
/// state alongside the parent task's grid parameters — both modes
/// share a single notifier so toggling between them does not destroy
/// unrelated user input.
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
    // PRD §九宫格朋友圈 — "3x3 is locked (other grid types in the
    // selector are dimmed)". Ignore type changes while social mode is
    // on so a stray tap can't desync the editor.
    if (state.nineGridSocialMode && type != GridType.g3x3) return;
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

  // ---- nine-grid-social mode --------------------------------------------

  /// Toggle the nine-grid-social mode.
  ///
  /// Turning the mode **on** locks [GridType] to `3x3`. Turning it
  /// **off** discards the user-picked replacement image and resets the
  /// transform so the next toggle-on starts fresh (PRD edge case L69).
  void setNineGridSocialMode(bool enabled) {
    if (state.nineGridSocialMode == enabled) return;
    if (enabled) {
      state = state.copyWith(nineGridSocialMode: true, gridType: GridType.g3x3);
    } else {
      state = state.copyWith(
        nineGridSocialMode: false,
        clearCenterImage: true,
        centerScale: kDefaultCenterScale,
        centerOffset: kCenterOffsetZero,
      );
    }
  }

  /// Replace the center-cell image with [image]. Pass `null` to drop
  /// the current replacement. Resets the transform to its default.
  void setCenterImage(ImportedImage? image) {
    if (image == null) {
      state = state.copyWith(
        clearCenterImage: true,
        centerScale: kDefaultCenterScale,
        centerOffset: kCenterOffsetZero,
      );
      return;
    }
    state = state.copyWith(
      centerImage: image,
      centerScale: kDefaultCenterScale,
      centerOffset: kCenterOffsetZero,
    );
  }

  /// Update the user-controlled scale for the center image. The value
  /// is clamped against both the PRD's hard `[0.5, 2]` range and the
  /// cover-cell minimum that depends on the image / cell dimensions.
  void setCenterScale(double scale) {
    final image = state.centerImage;
    if (image == null) return;
    final cell = _currentCenterCellExtent();
    final clamped = clampCenterTransform(
      scale: scale,
      offset: state.centerOffset,
      imageWidth: image.width,
      imageHeight: image.height,
      cellWidth: cell,
      cellHeight: cell,
    );
    if (clamped.scale == state.centerScale &&
        clamped.offset == state.centerOffset) {
      return;
    }
    state = state.copyWith(
      centerScale: clamped.scale,
      centerOffset: clamped.offset,
    );
  }

  /// Update the user-controlled pan offset for the center image,
  /// clamped against the scaled-image / cell dimensions so the cell
  /// never exposes transparency.
  void setCenterOffset(CenterOffset offset) {
    final image = state.centerImage;
    if (image == null) return;
    final cell = _currentCenterCellExtent();
    final clamped = clampCenterOffset(
      offset: offset,
      imageWidth: image.width,
      imageHeight: image.height,
      cellWidth: cell,
      cellHeight: cell,
      userScale: state.centerScale,
    );
    if (clamped == state.centerOffset) return;
    state = state.copyWith(centerOffset: clamped);
  }

  /// Open the gallery picker and replace the center image with the
  /// first selection.
  ///
  /// Bypasses [imageImportControllerProvider] so the picked image
  /// stays out of the main import session — the social mode owns its
  /// own image slot and doesn't interfere with the grid's source.
  Future<void> pickCenterImage() async {
    final repo = ref.read(imageImportRepositoryProvider);
    final result = await repo.pickFromGallery(limit: 1);
    switch (result) {
      case ImportSuccess(:final images):
        if (images.isNotEmpty) {
          setCenterImage(images.first);
        }
      case ImportFailure():
        // Picker dismissed or failure — keep the existing center
        // image; the UI surfaces failure copy via the import
        // controller's snackbar elsewhere.
        break;
    }
  }

  /// Estimate the side length of the center cell in source-pixel
  /// units. 3x3 cells are square (the renderer always splits a square-
  /// cropped source) so we approximate via the source image's shorter
  /// dimension divided by 3. Falls back to a generic 256 px so the
  /// clamping math still operates on a positive cell size before the
  /// user has imported a source.
  int _currentCenterCellExtent() {
    final source = state.source;
    if (source == null) return 256;
    final short = source.width < source.height ? source.width : source.height;
    return (short ~/ 3).clamp(1, short);
  }

  // ---- canvas drag-select crop (ST-C) -----------------------------------

  /// Update the normalized center of the user-selected square crop.
  /// Re-clamped against the current scale / source aspect so the crop
  /// can never expose pixels outside the source.
  void setSourceOffset(SourceOffset offset) {
    final source = state.source;
    if (source == null) return;
    if (source.height <= 0) return;
    final clamped = clampSourceOffset(
      offset: offset,
      scale: state.sourceScale,
      sourceAspect: source.width / source.height,
    );
    if (clamped == state.sourceOffset) return;
    state = state.copyWith(sourceOffset: clamped);
  }

  /// Update the cover-relative scale of the user-selected square crop.
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
