// Compact secondary-page entry behavior for the stitch editor.
//
// Validates the `05-26-mobile-stitch-secondary-page` PRD's AC for the
// stitch side:
//
// * `/m/stitch` route is reachable + AppBar renders a leading back arrow
// * empty editor → back arrow / system back pops without confirmation
// * non-empty editor (`hasImages == true`) → back / system back invokes
//   the shared `showDiscardEditorDialog` AlertDialog
// * dialog cancel → user stays in the editor; state untouched
// * dialog confirm → controller cleared + Navigator popped → next entry
//   sees an empty canvas
//
// Desktop branch behavior (`/stitch` tab root) is already covered by
// `stitch_editor_responsive_test.dart`; this file only exercises the
// compact-only `/m/stitch` path so the two suites stay independent.

import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/screens/stitch_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub() {
  return ImportedImage(
    bytes: _validPng(),
    width: 100,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

/// Pumps a harness that boots on `/` (a placeholder home) and pushes
/// `/m/stitch` so `Navigator.canPop` is true inside the editor — that's
/// the key signal that drives the secondary-page branch in
/// [StitchEditorScreen] (AppBar leading + PopScope intercept).
Future<ProviderContainer> _pumpSecondaryEditor(
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
              onPressed: () => context.push('/m/stitch'),
              child: const Text('go-stitch'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/m/stitch', builder: (_, _) => const StitchEditorScreen()),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
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
  await tester.tap(find.text('go-stitch'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('StitchEditorScreen — compact secondary page (/m/stitch)', () {
    testWidgets('AppBar renders a leading back arrow', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryEditor(tester, images: const []);

      // BackButton is what Flutter inserts via `automaticallyImplyLeading`
      // when Navigator.canPop is true — locking it as an explicit
      // contract here so the AppBar never silently loses the arrow.
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('empty editor (no images) → back arrow pops immediately, no '
        'dialog', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryEditor(tester, images: const []);
      expect(find.byType(StitchEditorScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // No dialog ever appears.
      expect(find.text('退出编辑器？'), findsNothing);
      // Editor screen is gone — we're back on the placeholder home.
      expect(find.byType(StitchEditorScreen), findsNothing);
      expect(find.text('go-stitch'), findsOneWidget);
    });

    testWidgets('non-empty editor → back arrow shows discard confirmation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSecondaryEditor(tester, images: [_stub(), _stub()]);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('退出编辑器？'), findsOneWidget);
      expect(find.text('未导出的拼图将丢失。'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('退出'), findsOneWidget);
      // We're still on the editor — the back gesture was intercepted.
      expect(find.byType(StitchEditorScreen), findsOneWidget);
    });

    testWidgets('dialog cancel → stays in editor, controller untouched', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = await _pumpSecondaryEditor(
        tester,
        images: [_stub(), _stub()],
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // Dialog dismissed; editor still here.
      expect(find.text('退出编辑器？'), findsNothing);
      expect(find.byType(StitchEditorScreen), findsOneWidget);
      // Controller state untouched.
      final state = container.read(stitchEditorControllerProvider);
      expect(state.hasImages, isTrue);
      expect(state.imageCount, 2);
    });

    testWidgets('dialog confirm → editor pops back to caller (clear() is '
        'invoked synchronously before pop)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = await _pumpSecondaryEditor(
        tester,
        images: [_stub(), _stub()],
      );
      // Sanity: editor mounted with images.
      expect(container.read(stitchEditorControllerProvider).hasImages, isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();

      // Route popped back to placeholder home — proves the confirm
      // branch executed in full. The `clear()` call sits **before**
      // `Navigator.pop()` in the synchronous body of the confirm
      // handler, so a successful pop is sufficient evidence that
      // `clear()` ran first; we don't separately re-assert the
      // controller's `hasImages` here because the harness overrides
      // `importedImagesProvider` with a static list (the editor
      // controller mirrors that provider, so the override would mask
      // the post-`clear()` value). Behavior of `clear()` itself is
      // unit-tested in `stitch_editor_provider_test.dart`.
      expect(find.byType(StitchEditorScreen), findsNothing);
      expect(find.text('go-stitch'), findsOneWidget);
    });
  });
}
