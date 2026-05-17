import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_image_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reorderables/reorderables.dart';

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({String tag = 'a'}) {
  return ImportedImage(
    sourcePath: tag,
    bytes: _validPng(),
    width: 100,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

/// Minimal fake repository that returns a fixed list on `pickFromGallery`
/// and no-ops on the other sources. Lets the widget test seed the real
/// [ImageImportController] state without overriding the controller
/// itself — so the clear() flow goes through the production chain.
class _FakeRepo implements ImageImportRepository {
  _FakeRepo(this._pickResult);

  final List<ImportedImage> _pickResult;

  @override
  Future<ImportResult> pickFromGallery({int limit = kMaxImportSessionImages}) {
    return Future.value(ImportSuccess(_pickResult));
  }

  @override
  Future<ImportResult> captureFromCamera() async {
    return const ImportFailure(UnsupportedSource('camera disabled in test'));
  }

  @override
  Future<ImportResult> pasteFromClipboard() async {
    return const ImportSuccess([]);
  }

  @override
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw) async {
    return const ImportSuccess([]);
  }
}

/// Builds a [ProviderContainer] whose stitch-scoped import controller is
/// pre-populated with [images]. Awaiting the container's initial build
/// + a `pickFromGallery` call replays the production path that the
/// widget exercises — so [StitchEditorController.clear] still flushes
/// the state under test.
Future<ProviderContainer> _seedContainer(List<ImportedImage> images) async {
  final repo = _FakeRepo(images);
  final container = ProviderContainer(
    overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
  );
  await container.read(
    imageImportControllerProvider(ImageImportSessionKind.stitch).future,
  );
  if (images.isNotEmpty) {
    await container
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .pickFromGallery();
  }
  return container;
}

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: StitchImageStrip())),
  );
}

void main() {
  group('StitchImageStrip — empty state', () {
    testWidgets(
      'hides clear button and collapse toggle when no images are present',
      (tester) async {
        final container = await _seedContainer(const []);
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container));
        await tester.pumpAndSettle();

        expect(find.text('清空'), findsNothing);
        expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
        expect(find.byIcon(Icons.expand_less), findsNothing);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        // 添加 stays visible.
        expect(find.text('添加'), findsOneWidget);
      },
    );
  });

  group('StitchImageStrip — clear button', () {
    testWidgets('shows clear button when image count > 0', (tester) async {
      final container = await _seedContainer([_stub(tag: 'a')]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('清空'), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
    });

    testWidgets('opens an AlertDialog with destructive 清空 button', (
      tester,
    ) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('清空已选图片'), findsOneWidget);
      expect(find.text('将移除当前 2 张图片，此操作不可撤销。'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '清空'), findsOneWidget);
    });

    testWidgets('cancel keeps the image list intact', (tester) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(2),
        reason: 'cancel must not call clear()',
      );
    });

    testWidgets('confirm clears the editor session', (tester) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      // Pre-condition.
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(2),
      );

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      // Tap the destructive FilledButton labelled 清空 inside the dialog.
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        isEmpty,
        reason: 'controller.clear() should empty the stitch session',
      );
      // Once cleared, the clear / collapse affordances should disappear.
      expect(find.text('清空'), findsNothing);
    });
  });

  group('StitchImageStrip — collapse toggle', () {
    testWidgets('shows expand_less icon by default and hides on toggle', (
      tester,
    ) async {
      final container = await _seedContainer([_stub(tag: 'a')]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      // Default state: expanded (icon = expand_less, ReorderableRow visible).
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byType(ReorderableRow), findsOneWidget);

      // Tap to collapse.
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
      expect(find.byType(ReorderableRow), findsNothing);
      // Header text still visible.
      expect(find.textContaining('已选图片'), findsOneWidget);
    });

    testWidgets('tapping the collapse icon again re-shows the cards', (
      tester,
    ) async {
      final container = await _seedContainer([_stub(tag: 'a')]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      // Collapse.
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableRow), findsNothing);

      // Re-expand.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableRow), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });
  });
}
