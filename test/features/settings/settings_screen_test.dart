import 'package:fl_picraft/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Stub destination so the router has a `/settings/about` target to
/// navigate to. We don't need the real AboutScreen here — only that
/// the route resolves and the path activates on tap.
const _kAboutSentinel = Key('settings_test::about_sentinel');

Widget _settingsHarness() {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'about',
            name: 'about',
            builder: (_, _) =>
                const Scaffold(key: _kAboutSentinel, body: SizedBox.shrink()),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('SettingsScreen', () {
    testWidgets('renders AppBar title "设置"', (tester) async {
      await tester.pumpWidget(_settingsHarness());
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('设置')),
        findsOneWidget,
      );
    });

    testWidgets('shows "关于" entry with info + chevron icons', (tester) async {
      await tester.pumpWidget(_settingsHarness());
      await tester.pumpAndSettle();

      final aboutTile = find.ancestor(
        of: find.text('关于'),
        matching: find.byType(ListTile),
      );
      expect(aboutTile, findsOneWidget);

      // Leading icon comes from PRD §D3.2.
      expect(
        find.descendant(
          of: aboutTile,
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
      // Trailing chevron makes the navigation affordance obvious.
      expect(
        find.descendant(
          of: aboutTile,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping "关于" pushes /settings/about onto the stack', (
      tester,
    ) async {
      await tester.pumpWidget(_settingsHarness());
      await tester.pumpAndSettle();

      // Sentinel should NOT be on screen before tap.
      expect(find.byKey(_kAboutSentinel), findsNothing);

      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();

      // After tap, the about route is mounted on top of settings.
      expect(find.byKey(_kAboutSentinel), findsOneWidget);
    });
  });
}
