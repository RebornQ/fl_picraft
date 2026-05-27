import 'dart:typed_data';

import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Provider-level tests for [canSaveProvider].
///
/// The provider derives a boolean from a sealed [PreviewState] +
/// [ExportState.isSaving] + [canExportProvider]. We don't need the real
/// renderer pipeline — overriding [previewControllerProvider] with a
/// stub that returns a fixed [PreviewState] lets us cover every
/// equivalence class without `compute()` / isolate / debounce noise.
///
/// Plain `test` + manual `ProviderContainer` per `quality-guidelines.md`
/// → "Pattern: Plain `test` over `testWidgets` for `AsyncNotifier`-only
/// assertions" — there's no widget tree under test here.

/// Stub controller that returns a fixed [PreviewState] from `build()`.
/// Overriding the provider with `.overrideWith(() => stub)` skips the
/// real controller's debounce / cache / isolate plumbing entirely.
class _StubPreviewController extends PreviewController {
  _StubPreviewController(this._initial);

  final PreviewState _initial;

  @override
  PreviewState build() => _initial;
}

ImportedImage _fakeImage(String path) {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 4)),
  );
  return ImportedImage(
    sourcePath: path,
    bytes: bytes,
    width: 4,
    height: 4,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 27),
  );
}

ProviderContainer _container({
  required PreviewState previewState,
  bool stitchHasImages = true,
}) {
  return ProviderContainer(
    overrides: [
      previewControllerProvider.overrideWith(
        () => _StubPreviewController(previewState),
      ),
      // `canExportProvider` (default: kind=stitch) reads
      // `importedImagesProvider(.stitch)`. Pump a non-empty list to
      // make canExport=true by default; tests that need canExport=false
      // override this with an empty list.
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWithValue(stitchHasImages ? [_fakeImage('a')] : const []),
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWithValue(const []),
    ],
  );
}

/// A minimal Ready state — bytes content doesn't affect the predicate,
/// only the sealed variant identity matters.
PreviewReady _ready() {
  return PreviewReady(
    bytes: [
      Uint8List.fromList(const [1, 2, 3]),
    ],
    totalSizeBytes: 3,
  );
}

void main() {
  group('canSaveProvider — PreviewState gate', () {
    test('PreviewEmpty → false', () {
      final container = _container(previewState: const PreviewEmpty());
      addTearDown(container.dispose);
      expect(container.read(canSaveProvider), isFalse);
    });

    test('PreviewLoading (no stale bytes) → false', () {
      final container = _container(previewState: const PreviewLoading());
      addTearDown(container.dispose);
      expect(container.read(canSaveProvider), isFalse);
    });

    test('PreviewLoading (with stale bytes — re-render in flight) → false', () {
      final stale = [
        Uint8List.fromList(const [9, 9, 9]),
      ];
      final container = _container(
        previewState: PreviewLoading(staleBytes: stale),
      );
      addTearDown(container.dispose);
      expect(
        container.read(canSaveProvider),
        isFalse,
        reason:
            '"重渲染中" 态（staleBytes != null）必须禁用保存，避免用户在过期'
            '帧上触发保存而产物不一致。',
      );
    });

    test('PreviewError → false', () {
      final container = _container(
        previewState: const PreviewError(message: 'boom'),
      );
      addTearDown(container.dispose);
      expect(
        container.read(canSaveProvider),
        isFalse,
        reason:
            '错误态必须禁用保存——用户须通过预览卡片的"重试"按钮恢复 '
            'PreviewReady 后再保存。',
      );
    });

    test('PreviewReady + !isSaving + canExport=true → true', () {
      final container = _container(previewState: _ready());
      addTearDown(container.dispose);
      expect(container.read(canSaveProvider), isTrue);
    });
  });

  group('canSaveProvider — isSaving gate', () {
    test('PreviewReady + isSaving=true → false', () {
      final container = _container(previewState: _ready());
      addTearDown(container.dispose);
      // Flip isSaving directly on the notifier state — the real save()
      // pipeline isn't under test here.
      final exportNotifier = container.read(exportControllerProvider.notifier);
      exportNotifier.state = exportNotifier.state.copyWith(isSaving: true);

      expect(
        container.read(canSaveProvider),
        isFalse,
        reason: '正在保存中，按钮必须 disabled 防止并发触发。',
      );
    });
  });

  group('canSaveProvider — canExport gate', () {
    test('PreviewReady + canExport=false → false (defense-in-depth)', () {
      // Despite PreviewReady, an empty editor would still trip the
      // canExport conjunction. Theoretically unreachable in production
      // because PreviewController falls back to PreviewEmpty when the
      // editor has no source — but the explicit guard is documented
      // (PRD §R1 / canSaveProvider doc-comment) as defense-in-depth
      // and the test pins the contract.
      final container = _container(
        previewState: _ready(),
        stitchHasImages: false,
      );
      addTearDown(container.dispose);
      expect(
        container.read(canSaveProvider),
        isFalse,
        reason:
            'canExport=false 时即便 preview 是 Ready 也必须禁用——纵深防御 '
            '保证导出管线没有 source 时不会被误触发。',
      );
    });
  });

  group('canSaveProvider — reactivity', () {
    test('flips false→true when preview transitions Loading → Ready', () {
      // Two containers exercise the two ends of the transition because
      // overriding `.overrideWith(() => stub)` resolves at container
      // build time; we can't mutate the stub after container creation.
      // What we can assert: the same input set yields the right output
      // at each end of the sealed transition.
      final loading = _container(previewState: const PreviewLoading());
      addTearDown(loading.dispose);
      final ready = _container(previewState: _ready());
      addTearDown(ready.dispose);

      expect(loading.read(canSaveProvider), isFalse);
      expect(ready.read(canSaveProvider), isTrue);
    });

    test('flips true→false when isSaving toggles on within Ready', () {
      final container = _container(previewState: _ready());
      addTearDown(container.dispose);
      expect(container.read(canSaveProvider), isTrue);

      final exportNotifier = container.read(exportControllerProvider.notifier);
      exportNotifier.state = exportNotifier.state.copyWith(isSaving: true);
      expect(container.read(canSaveProvider), isFalse);

      exportNotifier.state = exportNotifier.state.copyWith(isSaving: false);
      expect(container.read(canSaveProvider), isTrue);
    });
  });
}
