import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/imported_image.dart';
import '../../../image_import/presentation/providers/image_import_provider.dart';
import '../../data/renderers/stitch_image_renderer.dart';
import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/entities/stitch_mode.dart';
import '../../domain/usecases/stitch_render_request.dart';

/// DI seam for the renderer so widget tests can inject a fake without
/// going through the `image` package.
final stitchImageRendererProvider = Provider<StitchImageRenderer>((ref) {
  return const StitchImageRenderer();
});

/// Source-of-truth notifier for the long-stitch editor.
///
/// Mode-specific fields owned by the sibling `05-08-movie-subtitle`
/// task live in [StitchEditorState] but are inert here — that task
/// will extend this notifier with its own `setSubtitleOnlyMode` /
/// `setSubtitleBandHeight` methods (and corresponding UI hooks).
class StitchEditorController extends Notifier<StitchEditorState> {
  @override
  StitchEditorState build() {
    // Seed the editor with whatever the import controller currently
    // holds, then keep the two in sync. Listening lets the editor
    // pick up images dropped/pasted while it's already on screen.
    final initial = ref.read(importedImagesProvider);
    ref.listen<List<ImportedImage>>(importedImagesProvider, (prev, next) {
      // Replace the editor's image list verbatim. The import
      // controller already enforces the 20-image cap.
      state = state.copyWith(images: next);
    });
    return StitchEditorState.initial().copyWith(images: initial);
  }

  // ---- mode / parameters -------------------------------------------------

  void setMode(StitchMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void setSpacing(double px) {
    final clamped = px.clamp(0, kMaxStitchSpacing).toDouble();
    if (state.spacing == clamped) return;
    state = state.copyWith(spacing: clamped);
  }

  void setBorderWidth(double px) {
    final clamped = px.clamp(0, kMaxStitchBorderWidth).toDouble();
    if (state.border.width == clamped) return;
    state = state.copyWith(border: state.border.copyWith(width: clamped));
  }

  void setBorderColor(Color color) {
    if (state.border.color == color) return;
    state = state.copyWith(border: state.border.copyWith(color: color));
  }

  void setCornerRadius(double px) {
    final clamped = px.clamp(0, kMaxStitchCornerRadius).toDouble();
    if (state.cornerRadius == clamped) return;
    state = state.copyWith(cornerRadius: clamped);
  }

  // ---- movie-subtitle (PRD §3.3) ----------------------------------------

  /// Toggle the movie-subtitle flag-overlay. The flag is a no-op while
  /// [StitchEditorState.mode] is horizontal or while the editor holds
  /// fewer than 2 images (rendering degrades to plain vertical), but
  /// the field is still persisted so the toggle stays sticky across
  /// mode switches and image-list edits.
  void setSubtitleOnlyMode(bool enabled) {
    if (state.subtitleOnlyMode == enabled) return;
    state = state.copyWith(subtitleOnlyMode: enabled);
  }

  /// Update the bottom subtitle band height (in scaled-canvas pixels).
  /// Clamped to [kMinSubtitleBandHeight] – [kMaxSubtitleBandHeight].
  void setSubtitleBandHeight(double px) {
    final clamped = px
        .clamp(kMinSubtitleBandHeight, kMaxSubtitleBandHeight)
        .toDouble();
    if (state.subtitleBandHeight == clamped) return;
    state = state.copyWith(subtitleBandHeight: clamped);
  }

  // ---- image list management --------------------------------------------

  /// Drop the image at [index]. No-op if out of range.
  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    // Drive the import controller so both stay in sync.
    ref.read(imageImportControllerProvider.notifier).removeAt(index);
  }

  /// Reorder the editor list. Delegates to the import controller so
  /// other features observing `importedImagesProvider` see the same
  /// order. The `newIndex` follows the standard Flutter reorderable
  /// convention (post-removal coordinate space); the import controller
  /// handles the `> oldIndex ? - 1 : 0` adjustment internally.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.images.length) return;
    ref
        .read(imageImportControllerProvider.notifier)
        .reorder(oldIndex, newIndex);
  }

  /// Append images via the gallery picker — reuses the existing
  /// import flow rather than re-implementing it.
  Future<void> addFromGallery() async {
    await ref.read(imageImportControllerProvider.notifier).pickFromGallery();
  }

  Future<void> addFromCamera() async {
    await ref.read(imageImportControllerProvider.notifier).captureFromCamera();
  }

  Future<void> pasteFromClipboard() async {
    await ref.read(imageImportControllerProvider.notifier).pasteFromClipboard();
  }

  void clear() {
    ref.read(imageImportControllerProvider.notifier).clear();
  }

  // ---- rendering --------------------------------------------------------

  /// Render the assembled long image off the UI isolate. Throws if
  /// the editor has no images.
  Future<Uint8List> render({
    StitchExportFormat format = StitchExportFormat.png,
    int jpegQuality = 92,
  }) {
    if (!state.hasImages) {
      throw StateError('Cannot render: no images in the editor.');
    }
    final renderer = ref.read(stitchImageRendererProvider);
    return renderer.render(
      StitchRenderRequest.fromState(
        state,
        format: format,
        jpegQuality: jpegQuality,
      ),
    );
  }
}

final stitchEditorControllerProvider =
    NotifierProvider<StitchEditorController, StitchEditorState>(
      StitchEditorController.new,
    );
