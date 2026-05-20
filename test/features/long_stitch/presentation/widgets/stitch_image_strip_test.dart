/// 守护 `StitchImageStrip._ImageCard` 右上角"移除"按钮的尺寸 / 行为。
///
/// PRD: `.trellis/tasks/05-19-fix-stitch-image-card-remove-button-mobile-oversized`
///
/// V2' 规格（决策已修订 — ADR-lite v2 revision）：
/// - `iconSize = 14` + `constraints: minWidth/minHeight 24` → 视觉
///   chrome ≈ 24×24 dp（圆形浅色底 + close icon）
/// - `tapTargetSize: MaterialTapTargetSize.shrinkWrap` → hit area
///   收敛到 24×24（**主动**违反 `androidTapTargetGuideline` /
///   `iOSTapTargetGuideline`），是显式的视觉/a11y trade-off：用户
///   真机测试发现 padded 的 48×48 splash 反馈圈仍让按钮看起来过大。
///
/// 适用边界：仅卡片角标场景。常规按钮仍应满足 48dp。
///
/// 测试结构：
/// 1. **集成路径**（onRemove）：通过真实 `StitchImageStrip` + 注入
///    `_FakeRepo` 的 `imageImportRepositoryProvider` 渲染，模拟点击 ×
///    按钮，断言 `importedImagesProvider(.stitch)` 从 1 张变 0 张 ——
///    验证 _ImageCard.onRemove 被正确连接到
///    `StitchEditorController.removeImage`。
/// 2. **shrinkWrap 决策守护**：定位生产 _ImageCard 中的 × IconButton，
///    断言其渲染尺寸**紧贴** 24×24 chrome（≤ 28×28），**故意**低于
///    androidTapTargetGuideline 的 48dp。这是反向守护——未来如果有人
///    把 `tapTargetSize` 改回 `padded`，该按钮的渲染尺寸会膨胀到
///    48×48，本测试会 fail，提醒：本场景是经过用户真机视觉评估、显式
///    放弃 a11y guideline 的 trade-off，不是疏忽。
///
/// **本文件不**跑 `meetsGuideline(androidTapTargetGuideline)` /
/// `meetsGuideline(iOSTapTargetGuideline)`——因为本 widget 处明确违反
/// 这两个 guideline，跑了必 fail。全局 a11y test（home / export
/// 等）继续守护其他屏幕的 ≥48dp 最小 tap target，不受本任务影响。
library;

import 'dart:typed_data';

import 'package:fl_picraft/app/theme/app_theme.dart';
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

/// Mirrors the same fake-repo pattern used by other stitch tests so the
/// real `ImageImportController` chain seeds the editor.
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

Widget _stripHarness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StitchImageStrip()),
    ),
  );
}

void main() {
  group('StitchImageStrip._ImageCard remove button — onRemove wiring', () {
    testWidgets(
      'tapping × removes the image from the stitch session via the controller',
      (tester) async {
        final container = await _seedContainer([_stub(tag: 'a')]);
        addTearDown(container.dispose);

        await tester.pumpWidget(_stripHarness(container));
        await tester.pumpAndSettle();

        // Pre-condition: one image in the strip → one `_ImageCard` →
        // one `find.byTooltip('移除')` match (top bar buttons use no
        // tooltip / a different tooltip).
        expect(find.byTooltip('移除'), findsOneWidget);
        expect(
          container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
          hasLength(1),
        );

        await tester.tap(find.byTooltip('移除'));
        await tester.pumpAndSettle();

        expect(
          container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
          isEmpty,
          reason: 'tapping × should call StitchEditorController.removeImage',
        );
        expect(find.byTooltip('移除'), findsNothing);
      },
    );
  });

  group('StitchImageStrip._ImageCard remove button — shrinkWrap guard', () {
    // **故意守护"违反 a11y guideline"的状态** —— 详见 PRD ADR-lite v2:
    //
    // 用户真机测试反馈：`MaterialTapTargetSize.padded` 即使视觉 chrome
    // 限制在 24×24，tap/hover 时的 48×48 splash 反馈圈仍让按钮看起来
    // 过大。因此本卡片角标场景退到 `shrinkWrap`，hit area = visual =
    // 24×24，主动放弃 ≥48dp 最小 tap target 守护。
    //
    // 这个测试是「反向 sanity 守护」——如果未来有人把 production 改回
    // `padded`，该 IconButton 的渲染尺寸会膨胀到 48×48，断言会 fail，
    // 提醒读者：本 widget 处的 shrinkWrap 是经过用户真机视觉评估、
    // 显式 trade-off 的结果，不是疏忽。
    //
    // **适用边界**：仅本卡片角标 × 按钮场景。其他屏幕仍由各自的
    // a11y guideline test（home_screen_a11y_test 等）守护 ≥48dp。
    testWidgets(
      'production _ImageCard × button render size is shrinkWrap-tight '
      '(≤ 28×28, NOT 48×48)',
      (tester) async {
        final container = await _seedContainer([_stub(tag: 'a')]);
        addTearDown(container.dispose);

        await tester.pumpWidget(_stripHarness(container));
        await tester.pumpAndSettle();

        // Top bar 「展开 / 收起」 IconButton + `_ImageCard` × IconButton →
        // two IconButton instances. `find.ancestor` of the unique
        // tooltip '移除' picks out exactly the × one.
        final removeButton = find.ancestor(
          of: find.byTooltip('移除'),
          matching: find.byType(IconButton),
        );
        expect(removeButton, findsOneWidget);

        final size = tester.getSize(removeButton);
        // shrinkWrap + `constraints: minWidth/minHeight 24` →
        // rendered size hugs the visual chrome at 24×24. The ≤ 28
        // bound leaves a small margin for any IconButton-internal
        // padding without allowing the size to grow toward 48×48
        // (the padded form).
        expect(
          size.width,
          lessThanOrEqualTo(28),
          reason:
              'production _ImageCard × button width must stay tight '
              '(shrinkWrap, hit area = visual chrome). Got ${size.width}: '
              'if this is ≈48, someone likely flipped `tapTargetSize` back '
              'to `padded` without revisiting the PRD ADR-lite v2 trade-off.',
        );
        expect(
          size.height,
          lessThanOrEqualTo(28),
          reason:
              'production _ImageCard × button height must stay tight '
              '(shrinkWrap, hit area = visual chrome). Got ${size.height}: '
              'if this is ≈48, someone likely flipped `tapTargetSize` back '
              'to `padded` without revisiting the PRD ADR-lite v2 trade-off.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // PRD: `.trellis/tasks/05-20-stitch-import-limit-20`
  //
  // Guard the 20-image cap surface in the header "添加" button:
  // - count < 20 → enabled
  // - count == 20 → disabled (Material 3 will auto-render disabled state)
  // - removing one when at 20 → enabled again (reactive via the
  //   `imageImportSessionFullProvider` selector)
  // ---------------------------------------------------------------------
  group('StitchImageStrip header 添加 button — session cap', () {
    Future<ProviderContainer> seedWithCount(int n) async {
      final stubs = List.generate(n, (i) => _stub(tag: 'a$i'));
      return _seedContainer(stubs);
    }

    // `TextButton.icon` returns a `_TextButtonWithIcon` subclass — so
    // `find.byType(TextButton)` (which compares `runtimeType` strictly)
    // misses it. Match the superclass via predicate instead, then pin
    // the specific button via its tooltip ancestor.
    Finder findHeaderAddButton({required bool full}) {
      final tooltipMessage = full ? '已达上限 $kMaxImportSessionImages 张' : '添加图片';
      return find.descendant(
        of: find.byTooltip(tooltipMessage),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
    }

    testWidgets('count = 19 → 添加 button is enabled', (tester) async {
      final container = await seedWithCount(19);
      addTearDown(container.dispose);

      await tester.pumpWidget(_stripHarness(container));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        findHeaderAddButton(full: false),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('count = 20 → 添加 button is disabled', (tester) async {
      final container = await seedWithCount(kMaxImportSessionImages);
      addTearDown(container.dispose);

      await tester.pumpWidget(_stripHarness(container));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(findHeaderAddButton(full: true));
      expect(
        button.onPressed,
        isNull,
        reason: 'at the 20-image cap the header 添加 button must be disabled',
      );

      // Tooltip says why.
      expect(find.byTooltip('已达上限 $kMaxImportSessionImages 张'), findsOneWidget);
    });

    testWidgets('after removing one image while at cap, 添加 button re-enables', (
      tester,
    ) async {
      final container = await seedWithCount(kMaxImportSessionImages);
      addTearDown(container.dispose);

      await tester.pumpWidget(_stripHarness(container));
      await tester.pumpAndSettle();

      // Pre-condition: disabled
      expect(
        tester.widget<TextButton>(findHeaderAddButton(full: true)).onPressed,
        isNull,
      );

      // Remove one (tap any × button — there are 20 of them, just pick
      // the first).
      await tester.tap(find.byTooltip('移除').first);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextButton>(findHeaderAddButton(full: false)).onPressed,
        isNotNull,
        reason:
            'removing one image at the cap should immediately re-enable '
            'the 添加 button via the reactive sessionFull selector',
      );
      expect(find.byTooltip('已达上限 $kMaxImportSessionImages 张'), findsNothing);
    });
  });
}
