import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart';
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

/// Minimal fake repository — mirrors the one in `stitch_image_strip_test.dart`
/// so the clear() flow goes through the production controller chain.
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
  // The vertical list lives in an Expanded slot of a Column in the
  // production layout; mirror that here so the widget gets the same
  // bounded vertical extent it expects.
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: Column(children: [Expanded(child: StitchVerticalImageList())]),
        ),
      ),
    ),
  );
}

void main() {
  group('StitchVerticalImageList — empty state', () {
    testWidgets('renders the empty hint with both CTA buttons', (tester) async {
      final container = await _seedContainer(const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('尚未导入图片'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '从相册'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '剪贴板'), findsOneWidget);
    });

    testWidgets('hides clear button when no images are present', (
      tester,
    ) async {
      final container = await _seedContainer(const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('清空'), findsNothing);
      // Header 「添加」 stays visible.
      expect(find.text('添加'), findsOneWidget);
    });
  });

  group('StitchVerticalImageList — header', () {
    testWidgets('shows count, 添加 and 清空 (no collapse toggle)', (tester) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('已选图片 (2/'), findsOneWidget);
      expect(find.text('添加'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
      // Collapse / expand button must NOT appear on the wide-screen
      // vertical list.
      expect(find.byIcon(Icons.expand_less), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });

  group('StitchVerticalImageList — reorderable rows', () {
    testWidgets('renders a ReorderableColumn with one row per image', (
      tester,
    ) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
        _stub(tag: 'c'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableColumn), findsOneWidget);
      // Each row carries the size text 「100×200」 — there are 3 images
      // so the text should appear three times.
      expect(find.text('100×200'), findsNWidgets(3));
      // Drag indicator (one per row).
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
      // Per-row remove buttons (one per row).
      expect(find.byTooltip('移除'), findsNWidgets(3));
    });

    testWidgets('tapping a row 移除 button calls removeImage(i)', (tester) async {
      final container = await _seedContainer([
        _stub(tag: 'a'),
        _stub(tag: 'b'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(2),
      );

      // Tap the first 移除 button.
      await tester.tap(find.byTooltip('移除').first);
      await tester.pumpAndSettle();

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(1),
        reason: 'controller.removeImage should drop the first image',
      );
    });
  });

  group('StitchVerticalImageList — clear flow', () {
    testWidgets('confirm clears the editor session via the shared helper', (
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

      // Shared confirm dialog (same shape as StitchImageStrip).
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('清空已选图片'), findsOneWidget);
      expect(find.text('将移除当前 2 张图片，此操作不可撤销。'), findsOneWidget);

      // Confirm.
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        isEmpty,
        reason: 'shared confirmStitchClear → clear() should empty the session',
      );
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

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(2),
        reason: 'cancel must not call clear()',
      );
    });
  });

  // ---------------------------------------------------------------------
  // PRD: `.trellis/tasks/05-20-stitch-import-limit-20`
  //
  // Vertical list (wide-screen layout) header "添加" button must mirror
  // the strip's session-cap behavior — disabled at 20, tooltip explains
  // why, re-enables when one is removed.
  // ---------------------------------------------------------------------
  group('StitchVerticalImageList — session cap', () {
    Future<ProviderContainer> seedWithCount(int n) async {
      final stubs = List.generate(n, (i) => _stub(tag: 'v$i'));
      return _seedContainer(stubs);
    }

    // `TextButton.icon` returns a `_TextButtonWithIcon` subclass that
    // doesn't match `find.byType(TextButton)` (strict runtimeType
    // comparison). Match the superclass via predicate, pinned through
    // the wrapping Tooltip.
    Finder findHeaderAddButton({required bool full}) {
      final tooltipMessage = full
          ? '已达上限 $kMaxImportSessionImages 张'
          : '添加图片';
      return find.descendant(
        of: find.byTooltip(tooltipMessage),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
    }

    testWidgets('count = 19 → 添加 button is enabled', (tester) async {
      final container = await seedWithCount(19);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        findHeaderAddButton(full: false),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('count = 20 → 添加 button is disabled', (tester) async {
      final container = await seedWithCount(kMaxImportSessionImages);
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        findHeaderAddButton(full: true),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byTooltip('已达上限 $kMaxImportSessionImages 张'),
        findsOneWidget,
      );
    });

    testWidgets(
      'after removing one image while at cap, 添加 button re-enables',
      (tester) async {
        final container = await seedWithCount(kMaxImportSessionImages);
        addTearDown(container.dispose);

        await tester.pumpWidget(_harness(container));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextButton>(findHeaderAddButton(full: true))
              .onPressed,
          isNull,
        );

        await tester.tap(find.byTooltip('移除').first);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextButton>(findHeaderAddButton(full: false))
              .onPressed,
          isNotNull,
        );
      },
    );
  });
}
