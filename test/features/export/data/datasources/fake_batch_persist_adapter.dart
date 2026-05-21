import 'dart:typed_data';

import 'package:fl_picraft/features/export/data/datasources/batch_persist_adapter.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';

/// Deterministic [BatchPersistAdapter] for unit tests.
///
/// Pulls bytes from [next] up to [pullCount] times (defaults to
/// [total]), recording each call, then returns the configured
/// [result] (defaults to [SaveSuccess] with the count of cells
/// actually pulled).
///
/// Use this in repository-level tests where the assertion target is
/// "does the repository correctly delegate to the adapter?". Tests
/// that assert per-cell partial-save accounting (cancel / mid-loop
/// failure) should target the platform adapters directly via their
/// own test files.
class FakeBatchPersistAdapter extends BatchPersistAdapter {
  FakeBatchPersistAdapter({this.overrideResult, this.pullCount});

  /// Indices passed to `next(...)` during the most recent
  /// `persistMany` call, in invocation order.
  final List<int> nextCallIndices = <int>[];

  /// Bytes pulled from `next(...)` during the most recent
  /// `persistMany` call. `null` entries indicate end-of-input
  /// signals.
  final List<Uint8List?> pulledBytes = <Uint8List?>[];

  /// Last call's [persistMany] arguments — for assertion in tests
  /// that the repository passed the values it was supposed to.
  int? lastTotal;
  ExportFormat? lastFormat;
  DateTime? lastAt;
  int callCount = 0;

  /// Optional override for the returned [SaveResult]. When null,
  /// returns `SaveSuccess(count: <bytes pulled>)`.
  SaveResult? overrideResult;

  /// How many cells to pull from [next]. Null = pull until [total]
  /// (default behavior — covers the happy path).
  int? pullCount;

  @override
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  }) async {
    callCount++;
    lastTotal = total;
    lastFormat = format;
    lastAt = at;
    nextCallIndices.clear();
    pulledBytes.clear();

    final stopAfter = pullCount ?? total;
    for (var i = 0; i < stopAfter && i < total; i++) {
      nextCallIndices.add(i);
      final bytes = await next(i);
      pulledBytes.add(bytes);
      if (bytes == null) break;
    }
    final landed = pulledBytes.where((b) => b != null).length;
    return overrideResult ??
        SaveSuccess(location: '/tmp/fake_batch', count: landed);
  }
}
