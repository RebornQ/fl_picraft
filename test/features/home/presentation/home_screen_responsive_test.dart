import 'package:fl_picraft/features/home/presentation/screens/home_screen.dart';
import 'package:fl_picraft/features/home/presentation/widgets/feature_card.dart';
import 'package:fl_picraft/features/home/presentation/widgets/recent_works_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Builds a minimal GoRouter wrapper so [HomeScreen]'s `context.go`
/// callbacks resolve during tests (the home screen does not actually
/// navigate in these checks — we just need the router scope).
Widget _homeHarness({required Size size}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  group('HomeScreen responsive layout', () {
    testWidgets('compact (< 600 dp) stacks feature cards vertically', (
      tester,
    ) async {
      await tester.pumpWidget(_homeHarness(size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Both feature cards present.
      expect(find.byType(FeatureCard), findsNWidgets(2));

      // Vertical stack ⇒ the two cards have the same left edge.
      final lhs = tester.getTopLeft(find.byType(FeatureCard).first);
      final rhs = tester.getTopLeft(find.byType(FeatureCard).last);
      expect(lhs.dx, rhs.dx);
      expect(rhs.dy, greaterThan(lhs.dy));
    });

    testWidgets('medium (>= 600 dp) lays feature cards side-by-side', (
      tester,
    ) async {
      await tester.pumpWidget(_homeHarness(size: const Size(720, 1024)));
      await tester.pumpAndSettle();

      expect(find.byType(FeatureCard), findsNWidgets(2));

      // Side-by-side ⇒ same top edge, different left edges.
      final lhs = tester.getTopLeft(find.byType(FeatureCard).first);
      final rhs = tester.getTopLeft(find.byType(FeatureCard).last);
      expect(lhs.dy, rhs.dy);
      expect(rhs.dx, greaterThan(lhs.dx));
    });

    testWidgets('expanded (>= 840 dp) keeps side-by-side feature cards', (
      tester,
    ) async {
      await tester.pumpWidget(_homeHarness(size: const Size(1024, 800)));
      await tester.pumpAndSettle();

      final lhs = tester.getTopLeft(find.byType(FeatureCard).first);
      final rhs = tester.getTopLeft(find.byType(FeatureCard).last);
      expect(lhs.dy, rhs.dy);
      expect(rhs.dx, greaterThan(lhs.dx));
    });

    testWidgets('recent works grid uses 3 columns on compact', (tester) async {
      await tester.pumpWidget(_homeHarness(size: const Size(400, 800)));
      await tester.pumpAndSettle();

      // Use skipOffstage:false because the ListView lazily lays children
      // off-screen when the compact viewport is too short to host the
      // whole page in one pass.
      final grid = tester.widget<RecentWorksGrid>(
        find.byType(RecentWorksGrid, skipOffstage: false),
      );
      expect(grid.crossAxisCount, 3);
    });

    testWidgets('recent works grid uses 3 columns on medium', (tester) async {
      await tester.pumpWidget(_homeHarness(size: const Size(720, 1024)));
      await tester.pumpAndSettle();

      final grid = tester.widget<RecentWorksGrid>(
        find.byType(RecentWorksGrid, skipOffstage: false),
      );
      expect(grid.crossAxisCount, 3);
    });

    testWidgets('recent works grid uses 4 columns on expanded', (tester) async {
      await tester.pumpWidget(_homeHarness(size: const Size(1024, 800)));
      await tester.pumpAndSettle();

      final grid = tester.widget<RecentWorksGrid>(
        find.byType(RecentWorksGrid, skipOffstage: false),
      );
      expect(grid.crossAxisCount, 4);
    });

    testWidgets('recent works grid uses 4 columns on large', (tester) async {
      await tester.pumpWidget(_homeHarness(size: const Size(1600, 900)));
      await tester.pumpAndSettle();

      final grid = tester.widget<RecentWorksGrid>(
        find.byType(RecentWorksGrid, skipOffstage: false),
      );
      expect(grid.crossAxisCount, 4);
    });

    testWidgets('content is capped by maxContentWidth on very wide windows', (
      tester,
    ) async {
      await tester.pumpWidget(_homeHarness(size: const Size(2400, 1080)));
      await tester.pumpAndSettle();

      // The ListView (inside the ConstrainedBox cap) must be no wider than
      // the breakpoints constant — pick its first RenderConstrainedBox
      // descendant and verify its width.
      final renderListView = tester.renderObject<RenderBox>(
        find.byType(ListView),
      );
      expect(renderListView.size.width, lessThanOrEqualTo(1200));
    });
  });
}
