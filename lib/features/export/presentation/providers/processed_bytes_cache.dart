import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/export_format.dart';
import '../../domain/entities/watermark_config.dart';
import 'export_dispatch.dart';

/// Maximum number of distinct cache entries kept in memory.
///
/// PNG/JPG × 5 common quality presets = 10 combinations in theory, but
/// most users only toggle 1~2 times before saving. 4 is the budget that
/// keeps memory bounded (each entry can hold N decoded cells worth of
/// bytes) without trashing the typical hit pattern.
const int kProcessedBytesCacheCapacity = 4;

/// LRU cache for already-processed (watermarked + encoded) bytes.
///
/// Used by:
/// * [PreviewController] — writes after each successful render so
///   subsequent identical inputs skip the isolate hop. Reads on
///   re-evaluation when the cache key is unchanged.
/// * [ExportController.save] — reads before invoking
///   `exportAndSave(...)`; on hit, calls
///   [ExportRepository.persistOnly] directly so the save tap responds
///   instantly instead of waiting 1~2s for a redundant
///   compose+encode pass.
///
/// Cache life is tied to the owning Riverpod container — preview state
/// does NOT survive `ProviderContainer.dispose()` (e.g. test teardown
/// or full app restart). Cross-session persistence is explicitly out of
/// scope per PRD §Out of Scope.
class ProcessedBytesCache {
  ProcessedBytesCache({int capacity = kProcessedBytesCacheCapacity})
    : _capacity = capacity,
      _entries = LinkedHashMap<int, List<Uint8List>>();

  final int _capacity;
  final LinkedHashMap<int, List<Uint8List>> _entries;

  /// Returns the cached bytes for [key], promoting the entry to the
  /// most-recently-used slot. `null` on miss.
  List<Uint8List>? read(int key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// Write [bytes] under [key], evicting the least-recently-used entry
  /// when capacity is exceeded.
  void write(int key, List<Uint8List> bytes) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= _capacity) {
      final oldestKey = _entries.keys.first;
      _entries.remove(oldestKey);
    }
    _entries[key] = bytes;
  }

  /// Drop every cached entry. Called when the user explicitly resets
  /// the editor or when a controller decides cache invariants no
  /// longer hold.
  void invalidate() {
    _entries.clear();
  }

  /// Snapshot count for tests/diagnostics. Not part of the public
  /// contract callers should depend on.
  @visibleForTesting
  int get length => _entries.length;

  /// Snapshot key order (oldest → newest) for tests.
  @visibleForTesting
  Iterable<int> get keysInOrder => List.unmodifiable(_entries.keys);
}

/// Notifier that owns the singleton [ProcessedBytesCache] for the
/// current Riverpod container.
///
/// Exposes [invalidate] so callers (e.g. an editor "clear" action) can
/// drop the cache without a `ref.read(...).invalidate()` indirection.
class ProcessedBytesCacheNotifier extends Notifier<ProcessedBytesCache> {
  @override
  ProcessedBytesCache build() {
    return ProcessedBytesCache();
  }

  /// Read-through accessor (returns `null` on miss).
  List<Uint8List>? read(int key) => state.read(key);

  /// Write-through accessor with LRU bookkeeping.
  void write(int key, List<Uint8List> bytes) => state.write(key, bytes);

  void invalidate() => state.invalidate();
}

/// Public provider — read this from preview + save controllers.
final processedBytesCacheProvider =
    NotifierProvider<ProcessedBytesCacheNotifier, ProcessedBytesCache>(
      ProcessedBytesCacheNotifier.new,
    );

/// Compute a stable cache key for an export-pipeline input tuple.
///
/// All callers (preview controller, save controller) MUST go through
/// this helper so they share the same key derivation — mismatched keys
/// would silently double-render the same input.
///
/// The key is order-independent in the obvious sense (same inputs
/// always produce the same key) and field-sensitive — flipping any
/// watermark / format / quality bit produces a different key.
int computeProcessedBytesCacheKey({
  required ExportSourceKind kind,
  required int editorStateHash,
  required WatermarkConfig watermark,
  required ExportFormat format,
  required int quality,
}) {
  return Object.hash(
    kind,
    editorStateHash,
    watermark.hashCode,
    format.index,
    quality,
  );
}
