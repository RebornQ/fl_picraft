import 'dart:typed_data';

import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/export_request.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:fl_picraft/features/export/domain/repositories/export_repository.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_dispatch.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/export/presentation/widgets/save_action_button.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Widget tests for [SaveActionButton] enabled-state contract.
///
/// The button derives `enabled` exclusively from [canSaveProvider]. We
/// stub [previewControllerProvider] to inject each [PreviewState]
/// variant and assert `FloatingActionButton.extended.onPressed` flips
/// correctly. The full save pipeline isn't exercised — that's covered
/// in `export_controller_test.dart` / `export_controller_save_cache_hit_test.dart`.

class _StubPreviewController extends PreviewController {
  _StubPreviewController(this._initial);

  final PreviewState _initial;

  @override
  PreviewState build() => _initial;
}

/// Stand-in repository so the in-flight save() smoke test doesn't try
/// to reach `gal` / `file_picker`. Only used by the
/// `isSaving=true → spinner / disabled` test where we flip the flag
/// directly on the export notifier without calling `save()`.
class _NoopRepo implements ExportRepository {
  @override
  Future<SaveResult> exportAndSave(ExportRequest request) async {
    return const SaveSuccess(location: '/tmp/test.png');
  }

  @override
  Future<SaveResult> persistOnly(
    List<Uint8List> processed,
    ExportFormat format,
  ) async {
    return SaveSuccess(location: '/tmp/test.png', count: processed.length);
  }
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

PreviewReady _ready() {
  return PreviewReady(
    bytes: [
      Uint8List.fromList(const [1, 2, 3]),
    ],
    totalSizeBytes: 3,
  );
}

Widget _harness({
  required PreviewState previewState,
  bool stitchHasImages = true,
}) {
  return ProviderScope(
    overrides: [
      previewControllerProvider.overrideWith(
        () => _StubPreviewController(previewState),
      ),
      exportRepositoryProvider.overrideWithValue(_NoopRepo()),
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWithValue(stitchHasImages ? [_fakeImage('a')] : const []),
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWithValue(const []),
    ],
    child: const MaterialApp(
      home: Scaffold(floatingActionButton: SaveActionButton()),
    ),
  );
}

FloatingActionButton _findFab(WidgetTester tester) {
  // `FloatingActionButton.extended` resolves to the public
  // `FloatingActionButton` class with `extendedLabel` set, so
  // `find.byType(FloatingActionButton)` matches it. Using the public
  // class also keeps the assertion stable if Flutter ever splits the
  // extended variant into a private subclass.
  return tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
}

void main() {
  group('SaveActionButton — onPressed gated on canSaveProvider', () {
    testWidgets('PreviewEmpty → onPressed == null', (tester) async {
      await tester.pumpWidget(_harness(previewState: const PreviewEmpty()));
      expect(_findFab(tester).onPressed, isNull);
    });

    testWidgets('PreviewLoading (no stale) → onPressed == null', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(previewState: const PreviewLoading()));
      expect(_findFab(tester).onPressed, isNull);
    });

    testWidgets(
      'PreviewLoading (with stale bytes — "重渲染中") → onPressed == null',
      (tester) async {
        final stale = [
          Uint8List.fromList(const [9, 9, 9]),
        ];
        await tester.pumpWidget(
          _harness(previewState: PreviewLoading(staleBytes: stale)),
        );
        expect(
          _findFab(tester).onPressed,
          isNull,
          reason: 'stale 帧仍处于 loading 态，保存必须禁用。',
        );
      },
    );

    testWidgets('PreviewError → onPressed == null', (tester) async {
      await tester.pumpWidget(
        _harness(previewState: const PreviewError(message: 'boom')),
      );
      expect(
        _findFab(tester).onPressed,
        isNull,
        reason: '错误态禁止保存，由 PreviewCard 内"重试"按钮恢复 Ready 后再保存。',
      );
    });

    testWidgets(
      'PreviewReady + !isSaving + canExport=true → onPressed != null (clickable)',
      (tester) async {
        await tester.pumpWidget(_harness(previewState: _ready()));
        expect(
          _findFab(tester).onPressed,
          isNotNull,
          reason: '产物准备就绪，按钮应当可点击。',
        );
      },
    );

    testWidgets('PreviewReady + canExport=false → onPressed == null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(previewState: _ready(), stitchHasImages: false),
      );
      expect(
        _findFab(tester).onPressed,
        isNull,
        reason: 'canExport=false 的纵深防御兜底，按钮必须 disabled。',
      );
    });
  });

  group('SaveActionButton — in-flight visual chrome', () {
    testWidgets(
      'isSaving=true → spinner replaces save icon and label flips to "保存中…"',
      (tester) async {
        await tester.pumpWidget(_harness(previewState: _ready()));
        // Pre-condition: idle visual.
        expect(find.byIcon(Icons.save_outlined), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('保存中…'), findsNothing);

        // Read providers from any descendant of the ProviderScope.
        final element = tester.element(find.byType(SaveActionButton));
        final container = ProviderScope.containerOf(element);
        final exportNotifier = container.read(
          exportControllerProvider.notifier,
        );
        exportNotifier.state = exportNotifier.state.copyWith(isSaving: true);
        await tester.pump();

        expect(find.byIcon(Icons.save_outlined), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('保存中…'), findsOneWidget);

        // And the button must be disabled while saving — canSaveProvider
        // factors isSaving into the gate.
        expect(
          _findFab(tester).onPressed,
          isNull,
          reason: '保存进行中，按钮必须 disabled 避免并发触发。',
        );
      },
    );
  });

  group('SaveActionButton — stable tooltip copy', () {
    testWidgets('tooltip stays at "保存至相册" regardless of enabled state', (
      tester,
    ) async {
      // Disabled (PreviewEmpty).
      await tester.pumpWidget(_harness(previewState: const PreviewEmpty()));
      expect(_findFab(tester).tooltip, '保存至相册');

      // Enabled (PreviewReady).
      await tester.pumpWidget(_harness(previewState: _ready()));
      expect(_findFab(tester).tooltip, '保存至相册');
    });
  });

  group('SaveActionButton — MD3 disabled visual tokens', () {
    testWidgets(
      'disabled (PreviewEmpty) → backgroundColor == surfaceContainerHighest, '
      'foregroundColor == onSurface@38%, elevation == 0',
      (tester) async {
        await tester.pumpWidget(_harness(previewState: const PreviewEmpty()));
        final element = tester.element(find.byType(SaveActionButton));
        final colorScheme = Theme.of(element).colorScheme;
        final fab = _findFab(tester);

        expect(fab.backgroundColor, colorScheme.surfaceContainerHighest);
        expect(
          fab.foregroundColor,
          colorScheme.onSurface.withValues(alpha: 0.38),
        );
        expect(fab.elevation, 0);
      },
    );

    testWidgets('disabled (PreviewError) → same MD3 disabled tokens applied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(previewState: const PreviewError(message: 'boom')),
      );
      final element = tester.element(find.byType(SaveActionButton));
      final colorScheme = Theme.of(element).colorScheme;
      final fab = _findFab(tester);

      expect(fab.backgroundColor, colorScheme.surfaceContainerHighest);
      expect(
        fab.foregroundColor,
        colorScheme.onSurface.withValues(alpha: 0.38),
      );
      expect(fab.elevation, 0);
    });

    testWidgets(
      'enabled (PreviewReady) → backgroundColor / foregroundColor / elevation '
      'are null (inherit theme defaults)',
      (tester) async {
        await tester.pumpWidget(_harness(previewState: _ready()));
        final fab = _findFab(tester);

        expect(
          fab.backgroundColor,
          isNull,
          reason: 'enabled 分支保留 null 以继承默认主题，避免硬编码 primaryContainer。',
        );
        expect(fab.foregroundColor, isNull);
        expect(fab.elevation, isNull);
      },
    );
  });
}
