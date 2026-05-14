import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../data/renderers/grid_image_renderer.dart';
import '../../domain/entities/grid_editor_state.dart';
import '../../domain/entities/grid_type.dart';
import '../../domain/usecases/grid_render_request.dart';

/// DI seam for the renderer so widget tests can inject a fake without
/// going through the `image` package.
final gridImageRendererProvider = Provider<GridImageRenderer>((ref) {
  return const GridImageRenderer();
});

/// Source-of-truth notifier for the grid-split editor.
///
/// Mode-specific state owned by the sibling `05-08-nine-grid-social`
/// task lives on the reserved [GridEditorState.nineGridSocialMode]
/// flag — that task will extend this notifier with its own
/// `setNineGridSocialMode` / center-cell-image methods (and
/// corresponding UI hooks) without rewriting the field set.
class GridEditorController extends Notifier<GridEditorState> {
  @override
  GridEditorState build() {
    // The grid editor consumes a single source image — by convention
    // the first imported image. We listen to the import controller so
    // the editor picks up a new source when the user re-imports.
    final initial = ref.read(importedImagesProvider);
    ref.listen<List<ImportedImage>>(importedImagesProvider, (prev, next) {
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

  // ---- reserved for sibling task ----------------------------------------

  /// Toggle the nine-grid-social flag. Inert here (no center-cell
  /// replacement plumbing) — the sibling `05-08-nine-grid-social`
  /// task layers its UI on top.
  void setNineGridSocialMode(bool enabled) {
    if (state.nineGridSocialMode == enabled) return;
    state = state.copyWith(nineGridSocialMode: enabled);
  }

  // ---- import shortcuts -------------------------------------------------

  /// Append images via the gallery picker. The first imported image
  /// will become the source (existing imports + new ones combine
  /// through the import controller's session cap).
  Future<void> addFromGallery() async {
    await ref.read(imageImportControllerProvider.notifier).pickFromGallery();
  }

  Future<void> addFromCamera() async {
    await ref.read(imageImportControllerProvider.notifier).captureFromCamera();
  }

  Future<void> pasteFromClipboard() async {
    await ref.read(imageImportControllerProvider.notifier).pasteFromClipboard();
  }

  /// Clear the editor (drops the source image too).
  void clear() {
    ref.read(imageImportControllerProvider.notifier).clear();
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
