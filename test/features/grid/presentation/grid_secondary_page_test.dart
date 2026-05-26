// Compact secondary-page entry behavior for the grid editor.
//
// Mirror of `stitch_secondary_page_test.dart` for the grid side. The
// grid editor's "has data" predicate is `state.hasSource` (single
// source image) rather than `state.hasImages` (list), but the
// PopScope + discard-dialog + Navigator.pop flow is identical.

import 'package:fl_picraft/features/grid/presentation/providers/grid_editor_provider.dart';
import 'package:fl_picraft/features/grid/presentation/screens/grid_editor_screen.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

ImportedImage _gridSourceStub() {
  // 600×600 so the source-too-small warning doesn't render (would
  // otherwise overflow the compact viewport and steal hit-test from
  // BackButton).
  final image = img.Image(width: 600, height: 600);
  return ImportedImage(
    bytes: img.encodePng(image),
    width: 600,
    height: 600,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

Future<ProviderContainer> _pumpSecondaryGridEditor(
  WidgetTester tester, {
  required List<ImportedImage> images,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/m/grid'),
              child: const Text('go-grid'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/m/grid', builder: (_, _) => const GridEditorScreen()),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWith((ref) => images),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go-grid'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('GridEditorScreen — compact secondary page (/m/grid)', () {
    testWidgets('AppBar renders a leading back arrow', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryGridEditor(tester, images: const []);

      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('empty editor → back arrow pops immediately, no dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryGridEditor(tester, images: const []);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('退出编辑器？'), findsNothing);
      expect(find.byType(GridEditorScreen), findsNothing);
      expect(find.text('go-grid'), findsOneWidget);
    });

    testWidgets('editor with source → back arrow shows discard confirmation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryGridEditor(tester, images: [_gridSourceStub()]);

      // Sanity: source latched in.
      expect(find.byType(GridEditorScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('退出编辑器？'), findsOneWidget);
      expect(find.text('未导出的拼图将丢失。'), findsOneWidget);
      // Still on the editor.
      expect(find.byType(GridEditorScreen), findsOneWidget);
    });

    testWidgets('dialog cancel → stays in editor, source untouched', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = await _pumpSecondaryGridEditor(
        tester,
        images: [_gridSourceStub()],
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('退出编辑器？'), findsNothing);
      expect(find.byType(GridEditorScreen), findsOneWidget);
      // Source still latched.
      expect(container.read(gridEditorControllerProvider).hasSource, isTrue);
    });

    testWidgets('dialog confirm → editor pops back to caller', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryGridEditor(tester, images: [_gridSourceStub()]);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();

      // Confirm branch ran in full — `clear()` runs synchronously
      // before `Navigator.pop()` in the handler, so a successful pop
      // proves the clear path executed (mirrors the stitch test's
      // rationale).
      expect(find.byType(GridEditorScreen), findsNothing);
      expect(find.text('go-grid'), findsOneWidget);
    });
  });
}
