import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/drag_drop_datasource.dart';
import '../../data/repositories/image_import_repository_impl.dart';
import '../../domain/entities/image_import_failure.dart';
import '../../domain/entities/image_import_result.dart';
import '../../domain/entities/image_import_session_kind.dart';
import '../../domain/entities/imported_image.dart';
import '../../domain/entities/raw_image_bytes.dart';
import '../../domain/repositories/image_import_repository.dart';

/// DI provider for [ImageImportRepository]. Override in tests with
/// `ProviderScope.overrides: [imageImportRepositoryProvider.overrideWithValue(...)]`.
final imageImportRepositoryProvider = Provider<ImageImportRepository>((ref) {
  return ImageImportRepositoryImpl();
});

/// DI provider for the drag-drop helper. Kept separate from the
/// repository because the drag-drop widget needs the helper directly to
/// read out [DataFormat]s for `DropRegion(formats:)` — surfacing it as a
/// provider keeps the widget free of concrete-class imports.
final dragDropDataSourceProvider = Provider<DragDropDataSource>((ref) {
  return const DragDropDataSource();
});

/// Reactive view over the most recent import result, scoped per
/// [ImageImportSessionKind].
///
/// State is `AsyncData([])` initially; calling any of the trigger
/// methods flips to `AsyncLoading` then back to `AsyncData(images)` (or
/// `AsyncError(failure)` on failure).
///
/// Each [ImageImportSessionKind] gets its own instance of this notifier
/// — the long-stitch editor's imports live in
/// `imageImportControllerProvider(ImageImportSessionKind.stitch)` and
/// the grid-split editor's live in
/// `imageImportControllerProvider(ImageImportSessionKind.grid)`. The
/// two instances do not share state; failures in one never surface as
/// errors in the other.
///
/// The notifier owns the current "import session" — i.e. the list of
/// images chosen via any combination of sources. Downstream features
/// (Long Stitch, Grid Split) watch [importedImagesProvider] for the
/// list shape they need.
class ImageImportController
    extends FamilyAsyncNotifier<List<ImportedImage>, ImageImportSessionKind> {
  @override
  Future<List<ImportedImage>> build(ImageImportSessionKind kind) async {
    // The session-kind argument is purely a cache key — the controller's
    // behaviour is identical across modes. Each mode just gets its own
    // independent storage.
    return const [];
  }

  ImageImportRepository get _repo => ref.read(imageImportRepositoryProvider);

  /// Most recent partial-import warning, if any. Cleared on every fresh
  /// trigger. UI surfaces this as a snackbar.
  ImageImportFailure? lastWarning;

  /// Open the gallery picker and append the user's selection to the
  /// current session, capped at [kMaxImportSessionImages].
  Future<void> pickFromGallery() async {
    if (_isSessionFull()) {
      _flagSessionFull();
      return;
    }
    await _runImport(() => _repo.pickFromGallery(limit: _remainingCapacity()));
  }

  /// Capture a photo with the camera and append it to the session.
  Future<void> captureFromCamera() async {
    await _runImport(_repo.captureFromCamera);
  }

  /// Read images from the clipboard and append them to the session.
  Future<void> pasteFromClipboard() async {
    await _runImport(_repo.pasteFromClipboard);
  }

  /// Append images extracted from a drag-drop event by the
  /// [DragDropDataSource].
  Future<void> addFromDrop(List<RawImageBytes> raw) async {
    if (raw.isEmpty) return;
    await _runImport(() => _repo.importRawBytes(raw));
  }

  /// Drop the image at [index]. No-op if out of range.
  void removeAt(int index) {
    final current = state.valueOrNull;
    if (current == null || index < 0 || index >= current.length) return;
    final next = [...current]..removeAt(index);
    state = AsyncData(List.unmodifiable(next));
  }

  /// Reorder the import list. The `newIndex` follows the
  /// `reorderables` package convention (post-removal coordinate
  /// space — i.e. the index where the moved item should land
  /// **after** the original slot is removed). This matches the
  /// package's own example code (see `reorderables` 0.6.0
  /// `example/lib/{row,column}_example*.dart`: `removeAt(oldIndex);
  /// insert(newIndex, item);` with no offset adjustment).
  ///
  /// **DO NOT** confuse with Flutter's built-in `ReorderableListView`
  /// which uses pre-removal coordinates and expects callers to do
  /// `newIndex > oldIndex ? newIndex - 1 : newIndex`. The two
  /// conventions are different by exactly one. Project-wide we
  /// commit to the reorderables convention because every drag-reorder
  /// UI in the editor uses `package:reorderables`.
  void reorder(int oldIndex, int newIndex) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (oldIndex < 0 || oldIndex >= current.length) return;
    final next = [...current];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    state = AsyncData(List.unmodifiable(next));
  }

  /// Clear the session.
  void clear() {
    lastWarning = null;
    state = const AsyncData([]);
  }

  Future<void> _runImport(Future<ImportResult> Function() trigger) async {
    lastWarning = null;
    final previous = state.valueOrNull ?? const <ImportedImage>[];
    state = const AsyncLoading<List<ImportedImage>>().copyWithPrevious(state);
    try {
      final result = await trigger();
      switch (result) {
        case ImportSuccess(:final images, :final partial, :final skippedReason):
          if (partial) lastWarning = skippedReason;
          state = AsyncData(_appendCapped(previous, images));
        case ImportFailure(:final failure):
          if (failure is ImportCancelled) {
            // User dismissed the picker — keep previous list.
            state = AsyncData(previous);
          } else {
            state = AsyncError(failure, StackTrace.current);
          }
      }
    } catch (e, st) {
      state = AsyncError(UnknownImportFailure(e.toString()), st);
    }
  }

  List<ImportedImage> _appendCapped(
    List<ImportedImage> existing,
    List<ImportedImage> incoming,
  ) {
    final remaining = kMaxImportSessionImages - existing.length;
    if (remaining <= 0) {
      lastWarning = TooManyImages(
        attempted: existing.length + incoming.length,
        maxAllowed: kMaxImportSessionImages,
      );
      return existing;
    }
    if (incoming.length > remaining) {
      lastWarning = TooManyImages(
        attempted: existing.length + incoming.length,
        maxAllowed: kMaxImportSessionImages,
      );
    }
    return List.unmodifiable([...existing, ...incoming.take(remaining)]);
  }

  int _remainingCapacity() {
    final current = state.valueOrNull?.length ?? 0;
    return (kMaxImportSessionImages - current).clamp(
      1,
      kMaxImportSessionImages,
    );
  }

  bool _isSessionFull() {
    final current = state.valueOrNull?.length ?? 0;
    return current >= kMaxImportSessionImages;
  }

  void _flagSessionFull() {
    final current = state.valueOrNull?.length ?? 0;
    lastWarning = TooManyImages(
      attempted: current + 1,
      maxAllowed: kMaxImportSessionImages,
    );
  }
}

/// Per-mode async session of imported images.
///
/// Each [ImageImportSessionKind] is an isolated instance — reading
/// `imageImportControllerProvider(ImageImportSessionKind.stitch)` and
/// `imageImportControllerProvider(ImageImportSessionKind.grid)` returns
/// two unrelated controllers. See the enum's dartdoc for the rationale.
final imageImportControllerProvider =
    AsyncNotifierProvider.family<
      ImageImportController,
      List<ImportedImage>,
      ImageImportSessionKind
    >(ImageImportController.new);

/// Convenience: the bare `List<ImportedImage>` for a given session kind
/// (or empty during load). Features that just need the list watch this
/// instead of the controller to avoid rebuilds on transient
/// AsyncLoading flips.
final importedImagesProvider =
    Provider.family<List<ImportedImage>, ImageImportSessionKind>((ref, kind) {
      return ref.watch(imageImportControllerProvider(kind)).valueOrNull ??
          const [];
    });
