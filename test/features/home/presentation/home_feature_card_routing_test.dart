// Home FeatureCard routing — size-class-aware push vs go.
//
// Validates the ADR-2 routing branch in
// `.trellis/tasks/05-26-mobile-stitch-secondary-page/prd.md`:
//
// * compact (< 600 dp) → FeatureCards `context.push('/m/stitch')` /
//   `/m/grid` so the editors mount as secondary pages over the shell.
// * non-compact → FeatureCards keep `context.go('/stitch')` / `/grid`
//   so the desktop tab experience is unchanged.

import 'package:fl_picraft/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps a harness that mounts HomeScreen at `/` and gives both the
/// secondary-page (`/m/stitch`, `/m/grid`) and branch (`/stitch`,
/// `/grid`) destinations as inline placeholders, so the test can assert
/// which one the FeatureCard tapped routed to.
Future<void> _pumpHome(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/stitch',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('branch-stitch'))),
      ),
      GoRoute(
        path: '/grid',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('branch-grid'))),
      ),
      GoRoute(
        path: '/m/stitch',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('secondary-stitch'))),
      ),
      GoRoute(
        path: '/m/grid',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('secondary-grid'))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Home FeatureCard routing — compact (push secondary)', () {
    testWidgets('long-stitch card pushes /m/stitch on compact', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpHome(tester);

      // Tap the FeatureCard's "点击进入" FilledButton. The button's
      // `onPressed` invokes `onActionPressed`, which on compact runs
      // `context.push('/m/stitch')`.
      await tester.tap(find.text('点击进入').first);
      await tester.pumpAndSettle();

      // Push lands on the compact secondary route, not the branch route.
      expect(find.text('secondary-stitch'), findsOneWidget);
      expect(find.text('branch-stitch'), findsNothing);
    });

    testWidgets('grid card pushes /m/grid on compact', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpHome(tester);

      // The second "点击进入" button corresponds to the grid card
      // (FeatureCards are stacked vertically on compact).
      await tester.tap(find.text('点击进入').at(1));
      await tester.pumpAndSettle();

      expect(find.text('secondary-grid'), findsOneWidget);
      expect(find.text('branch-grid'), findsNothing);
    });
  });

  group('Home FeatureCard routing — medium (go branch)', () {
    testWidgets('long-stitch card goes /stitch on medium', (tester) async {
      // 800×600 — medium per Material 3 (600 ≤ w < 840).
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpHome(tester);

      // On medium the two cards are arranged in a Row, so the first
      // "点击进入" is still the stitch card (FeatureCards keep their
      // order; the Row places long-stitch on the left).
      await tester.tap(find.text('点击进入').first);
      await tester.pumpAndSettle();

      expect(find.text('branch-stitch'), findsOneWidget);
      expect(find.text('secondary-stitch'), findsNothing);
    });

    testWidgets('grid card goes /grid on medium', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpHome(tester);

      await tester.tap(find.text('点击进入').at(1));
      await tester.pumpAndSettle();

      expect(find.text('branch-grid'), findsOneWidget);
      expect(find.text('secondary-grid'), findsNothing);
    });
  });
}
