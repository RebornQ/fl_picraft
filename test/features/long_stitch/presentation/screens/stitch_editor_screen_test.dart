import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
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

/// Harness that pumps the [StitchEditorScreen] as a top-level
/// `GoRouter` location.
///
/// Mirrors the pattern used by `stitch_editor_responsive_test.dart` —
/// the editor screen reads `context.push('/export')` so a sibling
/// `/export` route is registered to keep navigation calls valid.
Widget _stitchHarness({List<ImportedImage>? images}) {
  final router = GoRouter(
    initialLocation: '/stitch',
    routes: [
      GoRoute(path: '/stitch', builder: (_, _) => const StitchEditorScreen()),
      GoRoute(path: '/export', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    overrides: [
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWith((ref) => images ?? [_stub()]),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('StitchEditorScreen AppBar leading contract', () {
    // The stitch editor is a `StatefulShellRoute` tab branch root, so
    // per `.trellis/spec/frontend/component-guidelines.md`
    // → "StatefulShellRoute + per-branch screen + Android back-key
    // contract", the AppBar must NOT render a leading back button —
    // the user switches tabs via the bottom nav. A prior
    // `Navigator.canPop(context) ? IconButton : null` guard had a race
    // window where the button could be momentarily visible and tapping
    // it triggered a GoRouter `currentConfiguration.isNotEmpty`
    // assertion crash. Removing the leading entirely closes the race.
    testWidgets('AppBar.leading is null (no back button rendered)', (
      tester,
    ) async {
      await tester.pumpWidget(_stitchHarness());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(
        appBar.leading,
        isNull,
        reason:
            'StatefulShellRoute tab branch root must NOT render a leading '
            'back button — use the bottom nav to switch tabs',
      );

      // Double-check via icon / tooltip finders so a future refactor
      // that uses a different leading shape still trips this guard.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.arrow_back),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('返回'),
        ),
        findsNothing,
      );
    });

    testWidgets('AppBar.leading is null even with empty session', (
      tester,
    ) async {
      // Empty session toggles export IconButton's onPressed to null;
      // make sure the leading absence is independent of that.
      await tester.pumpWidget(_stitchHarness(images: const []));
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.leading, isNull);
    });
  });
}
