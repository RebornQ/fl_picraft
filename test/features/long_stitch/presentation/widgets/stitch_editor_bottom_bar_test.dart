/// Widget tests for [StitchEditorBottomBar].
///
/// PRD: `.trellis/tasks/05-23-mobile-canvas-redesign-for-long-image-stitching`
/// Updated by `05-26-compact` — the `[⚙ 参数]` chip no longer opens a
/// modal sheet; it now toggles [stitchControlsInlineVisibleProvider]
/// which drives the inline parameter panel in the compact body.
///
/// The compact-viewport editor bottom bar surfaces three chips:
///
/// * `[+ 添加]` — always enabled, opens the add ActionSheet
/// * `[🖼 N/20]` — count chip, disabled when no images
/// * `[⚙ 参数]` — always enabled, toggles the inline parameter panel
///
/// The export CTA lives in the AppBar action slot on every size
/// class — it is **not** part of the bar; those assertions belong
/// in `stitch_editor_responsive_test.dart`.
library;

import 'dart:typed_data';

import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_editor_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// Harness: a small router that anchors the bottom bar on the home
/// route.
Widget _harness({
  required List<ImportedImage> images,
  GlobalKey<NavigatorState>? navKey,
  ProviderContainer? container,
}) {
  final router = GoRouter(
    navigatorKey: navKey,
    initialLocation: '/stitch',
    routes: [
      GoRoute(
        path: '/stitch',
        builder: (_, _) => const Scaffold(
          body: SizedBox.shrink(),
          bottomNavigationBar: StitchEditorBottomBar(),
        ),
      ),
    ],
  );
  final scopeChild = MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.light(),
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: scopeChild);
  }
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images),
    ],
    child: scopeChild,
  );
}

void main() {
  group('StitchEditorBottomBar — chip rendering', () {
    testWidgets('renders all three chips (添加 / count / 参数)', (tester) async {
      await tester.pumpWidget(_harness(images: const []));
      await tester.pumpAndSettle();

      expect(find.text('添加'), findsOneWidget);
      expect(find.text('0/$kMaxImportSessionImages'), findsOneWidget);
      expect(find.text('参数'), findsOneWidget);
      // Export chip was removed — the AppBar action owns export.
      expect(find.text('导出'), findsNothing);
    });

    testWidgets('count chip reflects the current image count', (tester) async {
      await tester.pumpWidget(
        _harness(
          images: [
            _stub(tag: 'a'),
            _stub(tag: 'b'),
            _stub(tag: 'c'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3/$kMaxImportSessionImages'), findsOneWidget);
    });
  });

  group('StitchEditorBottomBar — enabled / disabled states', () {
    Finder findFilledButtonWithLabel(String label) {
      return find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
    }

    testWidgets('imageCount == 0 → [🖼] is disabled; others enabled', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(images: const []));
      await tester.pumpAndSettle();

      // The count chip is a FilledButton.tonalIcon (a FilledButton
      // under the hood). Pin via the visible label.
      final imagesBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('0/$kMaxImportSessionImages'),
      );
      final addBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('添加'),
      );
      final paramsBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('参数'),
      );

      expect(imagesBtn.onPressed, isNull, reason: 'empty session → disabled');
      expect(addBtn.onPressed, isNotNull);
      expect(paramsBtn.onPressed, isNotNull);
    });

    testWidgets('imageCount > 0 → all three chips are enabled', (tester) async {
      await tester.pumpWidget(_harness(images: [_stub(tag: 'a')]));
      await tester.pumpAndSettle();

      final imagesBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('1/$kMaxImportSessionImages'),
      );
      final addBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('添加'),
      );
      final paramsBtn = tester.widget<FilledButton>(
        findFilledButtonWithLabel('参数'),
      );

      expect(imagesBtn.onPressed, isNotNull);
      expect(addBtn.onPressed, isNotNull);
      expect(paramsBtn.onPressed, isNotNull);
    });
  });

  group('StitchEditorBottomBar — chip interactions', () {
    testWidgets('tapping [+ 添加] opens a bottom sheet with three ListTiles', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(images: const []));
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      // Three ListTiles render in the action sheet.
      expect(find.text('从相册'), findsOneWidget);
      expect(find.text('剪贴板粘贴'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
    });

    testWidgets('tapping [⚙ 参数] toggles stitchControlsInlineVisibleProvider', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          importedImagesProvider(
            ImageImportSessionKind.stitch,
          ).overrideWith((ref) => [_stub(tag: 'a')]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _harness(
          images: [_stub(tag: 'a')],
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      // Default: provider is false.
      expect(
        container.read(stitchControlsInlineVisibleProvider),
        isFalse,
        reason: 'provider default value should be false',
      );

      // Tap → true.
      await tester.tap(find.text('参数'));
      await tester.pumpAndSettle();
      expect(
        container.read(stitchControlsInlineVisibleProvider),
        isTrue,
        reason: 'first tap should expand the panel',
      );

      // Tap again → false.
      await tester.tap(find.text('参数'));
      await tester.pumpAndSettle();
      expect(
        container.read(stitchControlsInlineVisibleProvider),
        isFalse,
        reason: 'second tap should collapse the panel',
      );
    });

    testWidgets(
      '[⚙ 参数] chip swaps between FilledButton.tonalIcon and FilledButton.icon on toggle',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            importedImagesProvider(
              ImageImportSessionKind.stitch,
            ).overrideWith((ref) => const []),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _harness(images: const [], container: container),
        );
        await tester.pumpAndSettle();

        // Collapsed state: tooltip reads "展开参数".
        expect(find.byTooltip('展开参数'), findsOneWidget);
        expect(find.byTooltip('收起参数'), findsNothing);

        // Flip provider to true; the chip rebuilds with the
        // selected-state tooltip.
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            true;
        await tester.pumpAndSettle();

        expect(find.byTooltip('收起参数'), findsOneWidget);
        expect(find.byTooltip('展开参数'), findsNothing);
      },
    );

    testWidgets(
      'tapping [🖼] opens a bottom sheet with the StitchVerticalImageList',
      (tester) async {
        await tester.pumpWidget(_harness(images: [_stub(tag: 'a')]));
        await tester.pumpAndSettle();

        // Find the count chip via its label.
        await tester.tap(find.text('1/$kMaxImportSessionImages'));
        await tester.pumpAndSettle();

        // Header "已选图片 (1/20)" identifies the vertical list.
        expect(find.textContaining('已选图片 (1/'), findsOneWidget);
      },
    );
  });
}
