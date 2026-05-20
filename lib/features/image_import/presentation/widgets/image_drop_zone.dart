import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../domain/entities/image_import_session_kind.dart';
import '../../domain/repositories/image_import_repository.dart'
    show kMaxImportSessionImages;
import '../providers/image_import_provider.dart';

/// Wraps a [child] in a `DropRegion` that funnels dropped images into
/// the [imageImportControllerProvider] keyed by [sessionKind].
///
/// This widget exists because `super_drag_and_drop`'s `DropRegion` must
/// live in the widget tree — there's no way to express "drag-drop input"
/// purely from a data source. By owning the wiring here we still keep
/// the actual byte-extraction logic in
/// `data/datasources/drag_drop_datasource.dart`; the widget only knows
/// the data source's `evaluateDropOver` / `extractDroppedImages` API.
///
/// Callers MUST decide explicitly which import session a drop belongs
/// to via [sessionKind] — the field is required (no default) so a
/// caller forgetting to pick a mode is a compile-time error rather
/// than a silent cross-mode leak.
///
/// On platforms that don't support drag-drop (mobile),
/// `super_drag_and_drop`'s `DropRegion` simply never receives events,
/// so the widget is harmless to wrap unconditionally.
class ImageDropZone extends ConsumerWidget {
  const ImageDropZone({
    super.key,
    required this.child,
    required this.sessionKind,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.onDragOver,
    this.onDragLeave,
  });

  /// The content to wrap. Often a `Stack` containing the editor's
  /// canvas and an overlay highlight that listens to [onDragOver].
  final Widget child;

  /// Which import session this drop zone feeds. Each editor screen
  /// passes its own kind (`.stitch` / `.grid` / …) so drops never
  /// leak between modes.
  final ImageImportSessionKind sessionKind;

  /// Hit-test behavior for the underlying [DropRegion]. Default
  /// matches super_drag_and_drop's example.
  final HitTestBehavior hitTestBehavior;

  /// Optional hover-state callback. Fires `true` while a valid image
  /// drag is over the region, `false` when it leaves or completes.
  final ValueChanged<bool>? onDragOver;

  /// Convenience alias for `onDragOver(false)` so callers can express
  /// "the dragee left without dropping" semantically.
  final VoidCallback? onDragLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSource = ref.watch(dragDropDataSourceProvider);

    return DropRegion(
      formats: dataSource.acceptedFormats,
      hitTestBehavior: hitTestBehavior,
      onDropOver: (event) {
        final operation = dataSource.evaluateDropOver(event);
        onDragOver?.call(operation != DropOperation.none);
        return operation;
      },
      onDropLeave: (_) {
        onDragOver?.call(false);
        onDragLeave?.call();
      },
      onPerformDrop: (event) async {
        onDragOver?.call(false);
        // Gate session-full BEFORE attempting extraction so we don't
        // waste cycles decoding bytes the controller would just refuse.
        // The controller's `_appendCapped` is the authoritative cap, but
        // surfacing the rejection here lets us show an immediate
        // snackbar (the controller's `lastWarning` is not currently
        // wired to any listener) and skip the no-op import round-trip.
        final isFull = ref.read(imageImportSessionFullProvider(sessionKind));
        if (isFull) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text('已达上限 $kMaxImportSessionImages 张'),
            ),
          );
          return;
        }
        final raw = await dataSource.extractDroppedImages(event);
        if (raw.isEmpty) return;
        await ref
            .read(imageImportControllerProvider(sessionKind).notifier)
            .addFromDrop(raw);
      },
      child: child,
    );
  }
}
