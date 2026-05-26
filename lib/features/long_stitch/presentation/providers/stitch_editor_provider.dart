import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/entities/image_import_session_kind.dart';
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
/// `setSubtitleBandHeightPercent` methods (and corresponding UI hooks).
class StitchEditorController extends Notifier<StitchEditorState> {
  @override
  StitchEditorState build() {
    // Seed the editor with whatever the stitch-scoped import controller
    // currently holds, then keep the two in sync. Listening lets the
    // editor pick up images dropped/pasted while it's already on
    // screen. The grid editor watches its own family instance — the
    // two sessions never share state.
    const kind = ImageImportSessionKind.stitch;
    final initial = ref.read(importedImagesProvider(kind));
    ref.listen<List<ImportedImage>>(importedImagesProvider(kind), (prev, next) {
      // Replace the editor's image list verbatim. The import
      // controller already enforces the 20-image cap.
      //
      // Movie-subtitle band-height reset (PRD §3.3 — see
      // `.trellis/tasks/05-18-subtitle-reset-on-reselect`): the user-
      // tuned `subtitleBandHeightPercent` is tied to *the current
      // first image's scaled height*. When the editor's image list
      // transitions from empty to non-empty (user re-picks after a
      // clear / remove-all), the previous percent no longer matches
      // the new batch's visual geometry, so we reset it to the
      // default. The `state.images.isEmpty` guard prevents the
      // listener's first-fire (where `prev` is null) from clobbering
      // the percent on initial mount with a pre-existing list.
      final wasEmpty = prev == null || prev.isEmpty;
      final shouldResetSubtitle =
          wasEmpty && next.isNotEmpty && state.images.isEmpty;
      state = state.copyWith(
        images: next,
        subtitleBandHeightPercent: shouldResetSubtitle
            ? kDefaultSubtitleBandHeightPercent
            : state.subtitleBandHeightPercent,
      );
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

  /// Atomic setter for the "电影台词" basic-tab card. Forces the
  /// movie-subtitle path on and pins the mode to vertical in a single
  /// state emission so the preview canvas never paints an intermediate
  /// `horizontal + subtitleOnlyMode=true` frame (which the algorithm
  /// treats as degenerate). Mirrors the basic-tab "电影台词" card tap
  /// in PRD §D1.
  void selectMovieSubtitleMode() {
    if (state.subtitleOnlyMode && state.mode == StitchMode.vertical) return;
    state = state.copyWith(subtitleOnlyMode: true, mode: StitchMode.vertical);
  }

  /// Atomic setter for the "普通拼接" basic-tab card. Clears the
  /// subtitle flag while preserving the active orientation (vertical
  /// or horizontal). Pair to [selectMovieSubtitleMode].
  void selectNormalMode() {
    if (!state.subtitleOnlyMode) return;
    state = state.copyWith(subtitleOnlyMode: false);
  }

  /// Atomic setter for the basic-tab orientation card. Flips the mode
  /// to the opposite orientation. When switching vertical → horizontal,
  /// the subtitle flag is force-cleared because the movie-subtitle path
  /// only makes sense in vertical mode (PRD §D1) — without this
  /// side-effect the preview canvas would flash an intermediate
  /// `horizontal + subtitleOnlyMode=true` frame that the renderer
  /// treats as degenerate. Switching horizontal → vertical leaves
  /// [StitchEditorState.subtitleOnlyMode] alone (it was already false
  /// during horizontal mode anyway).
  void toggleOrientation() {
    switch (state.mode) {
      case StitchMode.vertical:
        state = state.copyWith(
          mode: StitchMode.horizontal,
          subtitleOnlyMode: false,
        );
      case StitchMode.horizontal:
        state = state.copyWith(mode: StitchMode.vertical);
    }
  }

  /// Update the bottom subtitle band height (as a fraction of the
  /// first image's scaled height). Clamped to
  /// [kMinSubtitleBandHeightPercent] – [kMaxSubtitleBandHeightPercent].
  void setSubtitleBandHeightPercent(double pct) {
    final clamped = pct
        .clamp(kMinSubtitleBandHeightPercent, kMaxSubtitleBandHeightPercent)
        .toDouble();
    if (state.subtitleBandHeightPercent == clamped) return;
    state = state.copyWith(subtitleBandHeightPercent: clamped);
  }

  /// Toggle the "auto-trim black bars" overlay. Inert outside subtitle
  /// mode; the renderer / preview ignore the flag unless the
  /// movie-subtitle path is active.
  void setAutoTrimBlackBars(bool enabled) {
    if (state.autoTrimBlackBars == enabled) return;
    state = state.copyWith(autoTrimBlackBars: enabled);
  }

  // ---- image list management --------------------------------------------

  /// Drop the image at [index]. No-op if out of range.
  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    // Drive the import controller so both stay in sync.
    ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .removeAt(index);
  }

  /// Reorder the editor list. Delegates to the import controller so
  /// other features observing `importedImagesProvider(.stitch)` see
  /// the same order.
  ///
  /// `newIndex` follows the `reorderables` package convention
  /// (post-removal coordinate space — see `ImageImportController.reorder`
  /// for the convention's authoritative definition and the reason we
  /// commit to it project-wide).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.images.length) return;
    ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .reorder(oldIndex, newIndex);
  }

  /// Append images via the gallery picker — reuses the existing
  /// import flow rather than re-implementing it.
  Future<void> addFromGallery() async {
    await ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .pickFromGallery();
  }

  Future<void> addFromCamera() async {
    await ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .captureFromCamera();
  }

  Future<void> pasteFromClipboard() async {
    await ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .pasteFromClipboard();
  }

  void clear() {
    ref
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .clear();
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

/// Compact-only: whether the inline parameter panel is expanded.
///
/// Toggled by the `[⚙ 参数]` chip in [StitchEditorBottomBar]. When
/// `true`, [StitchInlineControlsContainer] expands a
/// [StitchControlsPanel] between the canvas and the bottom bar
/// (PRD `05-26-compact`).
///
/// **Not persisted** — every fresh editor mount reads the default
/// (`false`). Consistent with the toolbar-Tab no-persist decision in
/// `05-26-long-stitch-toolbar-tab-redesign` PRD §D3. State survives
/// `StatefulShellRoute` tab switches within a single session, so
/// returning to the editor restores the user's last visible/hidden
/// choice for the lifetime of the app process.
///
/// Only the compact size class reads or writes this provider; medium
/// keeps the always-docked [StitchControlsSheet], expanded / large
/// dock the panel on the right column — both ignore this flag.
final stitchControlsInlineVisibleProvider = StateProvider<bool>((_) => false);
