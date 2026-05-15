import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/home/presentation/screens/home_screen.dart';
import 'package:fl_picraft/features/home/presentation/widgets/feature_card.dart';
import 'package:fl_picraft/features/home/presentation/widgets/tips_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Builds the home screen under [ThemeMode.dark] using the seeded dark
/// scheme produced by [AppTheme.dark]. The smoke checks below assert
/// the widget tree builds without error and a couple of design-token
/// callsites resolve through the dark color scheme rather than blowing
/// up on a missing role.
Widget _harness({required ThemeMode themeMode}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
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
  group('HomeScreen dark-mode smoke', () {
    testWidgets('renders without exceptions under ThemeMode.dark', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      // Sanity: structural widgets are present.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(FeatureCard), findsNWidgets(2));
      expect(find.byType(TipsBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TipsBanner background blends tertiary over surface', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      // The banner uses Color.alphaBlend to ensure the tertiary tint
      // stays visible against a dark surface. A bare alpha-only color
      // would let the dark surface bleed through to invisibility.
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TipsBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      // alphaBlend always returns an opaque color (alpha == 255).
      expect(decoration.color!.a, closeTo(1.0, 0.01));
    });

    testWidgets('renders without exceptions under ThemeMode.light', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
