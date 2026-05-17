import 'dart:typed_data';

import 'package:fl_picraft/features/grid/presentation/screens/grid_editor_screen.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

/// Stub repository for the AppBar import action.
///
/// Captures every call so tests can assert whether `pickFromGallery`
/// was invoked. The first call returns a synthetic [ImportedImage]; the
/// session-pre-seed flow (via `importedImagesProvider` override) means
/// tests usually don't need this fallback, but it keeps the controller's
/// `pickFromGallery` round-trip honest if a test ever drives it.
class _RecordingRepo implements ImageImportRepository {
  int pickCallCount = 0;

  @override
  Future<ImportResult> pickFromGallery({int? limit}) async {
    pickCallCount++;
    return ImportSuccess(<ImportedImage>[_synth('picked')]);
  }

  @override
  Future<ImportResult> captureFromCamera() async =>
      ImportFailure(const ImportCancelled());

  @override
  Future<ImportResult> pasteFromClipboard() async =>
      ImportFailure(const ImportCancelled());

  @override
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw) async =>
      ImportFailure(const ImportCancelled());
}

Uint8List _validPng() {
  final image = img.Image(width: 8, height: 8);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _synth(String tag) {
  return ImportedImage(
    bytes: _validPng(),
    width: 1024,
    height: 1024,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 5, 17),
  );
}

Widget _harness({
  required _RecordingRepo repo,
  required List<ImportedImage> seedImages,
}) {
  final router = GoRouter(
    initialLocation: '/grid',
    routes: [
      GoRoute(path: '/grid', builder: (_, _) => const GridEditorScreen()),
      GoRoute(path: '/export', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    overrides: [
      imageImportRepositoryProvider.overrideWithValue(repo),
      // Seed the grid-kind session directly so `state.hasSource`
      // reflects the test setup without needing to drive the picker
      // first. The controller wires up its `ref.listen` to this
      // family instance in `build`, so the editor's source is in
      // sync from frame 1.
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((ref) => seedImages),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _tapImportAction(WidgetTester tester) async {
  await tester.tap(find.byTooltip('导入图片'));
  await tester.pumpAndSettle();
}

void main() {
  group('GridEditorScreen overwrite-import flow', () {
    testWidgets(
      'with existing source: tapping import shows confirm dialog and 替换 triggers picker',
      (tester) async {
        final repo = _RecordingRepo();
        await tester.pumpWidget(
          _harness(repo: repo, seedImages: [_synth('seed')]),
        );
        await tester.pumpAndSettle();

        await _tapImportAction(tester);

        // Dialog surfaced.
        expect(find.text('替换现有图片？'), findsOneWidget);
        expect(find.text('替换后，当前的裁剪位置与缩放会重置。'), findsOneWidget);
        expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, '替换'),
          findsOneWidget,
          reason: 'FilledButton.tonal resolves to a FilledButton ancestor',
        );

        // Tap "替换".
        await tester.tap(find.widgetWithText(FilledButton, '替换'));
        await tester.pumpAndSettle();

        // Picker fired exactly once.
        expect(repo.pickCallCount, 1);
        // Dialog is gone.
        expect(find.text('替换现有图片？'), findsNothing);
      },
    );

    testWidgets(
      'with existing source: 取消 preserves state and does not open picker',
      (tester) async {
        final repo = _RecordingRepo();
        final seed = _synth('seed');
        await tester.pumpWidget(_harness(repo: repo, seedImages: [seed]));
        await tester.pumpAndSettle();

        await _tapImportAction(tester);

        expect(find.text('替换现有图片？'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();

        // No picker call.
        expect(repo.pickCallCount, 0);
        // Dialog is gone.
        expect(find.text('替换现有图片？'), findsNothing);
      },
    );

    testWidgets('no source: tapping import skips dialog and opens picker', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await tester.pumpWidget(_harness(repo: repo, seedImages: const []));
      await tester.pumpAndSettle();

      await _tapImportAction(tester);

      // Dialog NEVER surfaced.
      expect(find.text('替换现有图片？'), findsNothing);
      // Picker fired.
      expect(repo.pickCallCount, 1);
    });

    testWidgets(
      'cancel path: outside-tap dismissal treated as cancel (no picker)',
      (tester) async {
        final repo = _RecordingRepo();
        await tester.pumpWidget(
          _harness(repo: repo, seedImages: [_synth('seed')]),
        );
        await tester.pumpAndSettle();

        await _tapImportAction(tester);
        expect(find.text('替换现有图片？'), findsOneWidget);

        // Tap the barrier (outside the dialog).
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text('替换现有图片？'), findsNothing);
        expect(repo.pickCallCount, 0);
      },
    );
  });
}
