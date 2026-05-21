import 'package:flutter/foundation.dart';

import '../../../../core/errors/user_facing_messages.dart';
import '../../domain/entities/export_format.dart';
import '../../domain/entities/save_result.dart';
import '../../domain/usecases/suggested_name.dart';
import 'batch_persist_adapter.dart';
import 'gallery_saver_datasource.dart';

/// Mobile ([iOS] / [Android]) batch persistence — wraps the existing
/// `gal` plugin loop into the unified [BatchPersistAdapter] contract.
///
/// Behavior matches the pre-refactor `_exportGrid` loop:
///   * Sequentially pulls each cell from [next], strips the file
///     extension (per `gal`'s "I append the extension myself" rule),
///     and forwards to [GallerySaverDataSource.save].
///   * On the first cell's failure → returns the failure verbatim.
///   * On a mid-loop failure (saved ≥ 1) → returns
///     [SaveFailure] enriched with [partialSaveFailureMessage].
///   * On a mid-loop cancel (saved ≥ 1) → returns [SaveSuccess] with
///     the partial count (honors "已保存 N 张" snackbar copy).
///
/// Memory shape: pull → save → discard, peak ~ 1 image (same as
/// desktop). The gal plugin's first save typically prompts for
/// permission once; subsequent saves are uncongested.
class MobileGalleryPersistAdapter extends BatchPersistAdapter {
  const MobileGalleryPersistAdapter({GallerySaverDataSource? gallery})
    : _gallery = gallery ?? const GallerySaverDataSource();

  final GallerySaverDataSource _gallery;

  @override
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  }) async {
    if (total <= 0) {
      return const SaveFailure('没有可导出的内容');
    }

    String? lastLocation;
    var saved = 0;

    for (var i = 0; i < total; i++) {
      try {
        final bytes = await next(i);
        if (bytes == null) {
          // Producer signalled end-of-input before reaching [total];
          // honor it as a clean stop with whatever has been written.
          break;
        }
        final name = suggestedName(format, at: at, index: i + 1);
        // gal appends the extension itself — strip the user-facing
        // `.png` / `.jpg` we generated.
        final mobileName = _stripExtension(name);
        final result = await _gallery.save(bytes, fileName: mobileName);
        switch (result) {
          case SaveSuccess(:final location):
            saved++;
            lastLocation = location ?? lastLocation;
          case SaveCancelled():
            // gal currently never returns SaveCancelled, but keep the
            // exhaustive branch for forward-compat with future plugin
            // versions.
            if (saved > 0) {
              return SaveSuccess(location: lastLocation, count: saved);
            }
            return result;
          case SaveFailure(:final message):
            if (saved == 0) return result;
            return SaveFailure(
              partialSaveFailureMessage(
                saved: saved,
                total: total,
                cause: message,
              ),
            );
        }
      } catch (e) {
        if (saved == 0) {
          return SaveFailure(saveFailureMessage(e));
        }
        return SaveFailure(
          partialSaveFailureMessage(saved: saved, total: total, cause: e),
        );
      }
    }

    if (saved == 0) {
      return const SaveFailure('没有可导出的内容');
    }
    return SaveSuccess(location: lastLocation, count: saved);
  }

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }
}
