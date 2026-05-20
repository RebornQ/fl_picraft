import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preview_renderer.dart';

/// DI seam for the watermark + encode stage of the export pipeline.
///
/// Production binding returns [processExportBytes], which hops to a
/// background isolate via `compute()`. Tests override the provider with
/// a synchronous fake so `FakeAsync` can drive the controller's
/// debounce / call-count assertions — `compute()` runs in a real
/// isolate and ignores `FakeAsync` ticks, making the production
/// implementation untestable for those concerns (see PRD §D6).
///
/// Both the preview controller and any other consumer that needs to
/// process bytes for display / save MUST go through this provider so
/// tests can intercept the same code path.
final processBytesFnProvider = Provider<ProcessBytesFn>((ref) {
  return processExportBytes;
});
