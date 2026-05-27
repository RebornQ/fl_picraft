import 'dart:typed_data';

import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_controller.dart';
import 'package:fl_picraft/features/export/presentation/providers/preview_state.dart';
import 'package:fl_picraft/features/export/presentation/screens/export_screen.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

/// Stubbed [PreviewController] that emits a fixed [PreviewState] on
/// build so the harness can land the export screen in
/// [PreviewReady] — the only state where the save FAB is enabled and
/// rendered with full-contrast tokens. Disabled FAB tokens (MD3
/// `onSurface@38%` foreground on `surfaceContainerHighest`)
/// intentionally fail WCAG 4.5:1 contrast per the MD3 disabled-state
/// spec; WCAG explicitly exempts disabled controls (SC 1.4.3) but
/// Flutter's [textContrastGuideline] doesn't differentiate, so the
/// a11y check must exercise the enabled visual to be meaningful.
class _StubPreviewController extends PreviewController {
  _StubPreviewController(this._initial);

  final PreviewState _initial;

  @override
  PreviewState build() => _initial;
}

ImportedImage _fakeImage() {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 4)),
  );
  return ImportedImage(
    sourcePath: 'a.png',
    bytes: bytes,
    width: 4,
    height: 4,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 27),
  );
}

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/export',
    routes: [
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    overrides: [
      // Land on PreviewReady so the save FAB renders enabled — its
      // disabled MD3 tokens (onSurface@38%) are intentionally
      // low-contrast and would trip textContrastGuideline. The
      // a11y suite is meaningful only for the user-actionable state.
      previewControllerProvider.overrideWith(
        () => _StubPreviewController(
          PreviewReady(
            bytes: [
              Uint8List.fromList(const [1, 2, 3]),
            ],
            totalSizeBytes: 3,
          ),
        ),
      ),
      // canExportProvider derives from imported images in the stitch
      // session (the default source kind). Seed one image so
      // canSaveProvider returns true alongside PreviewReady.
      importedImagesProvider(
        ImageImportSessionKind.stitch,
      ).overrideWithValue([_fakeImage()]),
      importedImagesProvider(
        ImageImportSessionKind.grid,
      ).overrideWithValue(const []),
    ],
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

void main() {
  group('ExportScreen accessibility', () {
    testWidgets('meets Android tap target guideline (48×48 dp)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('meets iOS tap target guideline (44×44 pt)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('meets text-contrast guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('meets labeled-tappable-node guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
