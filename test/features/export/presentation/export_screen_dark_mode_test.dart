import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/export/presentation/screens/export_screen.dart';
import 'package:fl_picraft/features/export/presentation/widgets/save_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Wraps the export screen under the seeded dark theme so we can
/// smoke-test the disclaimer's [Color.alphaBlend] composition for the
/// inner icon chip background (a flat
/// `tertiaryContainer.withValues(alpha: 0.2)` would wash out against
/// the dark surface).
Widget _harness({required ThemeMode themeMode}) {
  final router = GoRouter(
    initialLocation: '/export',
    routes: [
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
    ),
  );
}

void main() {
  group('ExportScreen dark-mode smoke', () {
    testWidgets('renders without exceptions under ThemeMode.dark', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.byType(ExportScreen), findsOneWidget);
      expect(find.byType(SaveDisclaimer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'SaveDisclaimer icon chip resolves to an opaque blended color in dark mode',
      (tester) async {
        await tester.pumpWidget(_harness(themeMode: ThemeMode.dark));
        await tester.pumpAndSettle();

        // The disclaimer's inner Container (icon chip) is the second
        // Container under SaveDisclaimer — the outer one is the
        // bordered card. Confirm the icon chip background is opaque,
        // which is the hallmark of [Color.alphaBlend].
        final containers = find.descendant(
          of: find.byType(SaveDisclaimer),
          matching: find.byType(Container),
        );
        expect(containers, findsAtLeast(2));
        final iconChip = tester.widget<Container>(containers.at(1));
        final decoration = iconChip.decoration as BoxDecoration;
        expect(decoration.color, isNotNull);
        expect(decoration.color!.a, closeTo(1.0, 0.01));
      },
    );

    testWidgets('renders without exceptions under ThemeMode.light', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ExportScreen), findsOneWidget);
    });
  });
}
