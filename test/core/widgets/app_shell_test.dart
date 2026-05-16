// State-preservation + Android back-key contract for AppShell.
//
// Validates the three R-items from the
// 05-16-bottom-nav-switch-optimization PRD:
//
//   R1: tab switches don't rebuild screen instances (IndexedStack
//       retains the branch element trees once visited).
//   R2: NavigationBar widget identity is preserved across tab
//       switches (the bar lives on the shell, not the screens).
//   R8: Android back-key three-layer logic — branch can-pop is
//       branch-local (we cover the two shell-visible layers here:
//       non-home tab → goBranch(0); home tab → system pop).

import 'package:fl_picraft/app/app.dart';
import 'package:fl_picraft/features/home/presentation/screens/home_screen.dart';
import 'package:fl_picraft/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: AppRoot()));
  await tester.pumpAndSettle();
}

/// Finds a NavigationDestination by label, scoped to the bottom
/// NavigationBar (avoiding collisions with AppBar titles or in-body
/// text — e.g. SettingsScreen also renders "设置" twice in its body).
Finder _navDestination(String label) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
}

void main() {
  group('AppShell — R1 state preservation', () {
    testWidgets(
      'visiting a tab and switching away keeps it in the widget tree',
      (tester) async {
        await _pumpApp(tester);

        // Boot lands on home; settings hasn't been built yet.
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(
          find.byType(SettingsScreen, skipOffstage: false),
          findsNothing,
          reason: 'IndexedStack lazy-builds branches on first visit',
        );

        // Switch to settings.
        await tester.tap(_navDestination('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);

        // Switch back to home. Settings should now be retained in
        // the tree as offstage (the whole point of IndexedStack).
        await tester.tap(_navDestination('功能大全'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(
          find.byType(SettingsScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'Visited branches stay mounted; that\'s state preservation',
        );
        expect(
          find.byType(SettingsScreen),
          findsNothing,
          reason: 'Offstage means not visible — but still mounted',
        );
      },
    );

    testWidgets('returning to a tab reuses the same Element instance', (
      tester,
    ) async {
      await _pumpApp(tester);

      // Visit settings once so it's mounted.
      await tester.tap(_navDestination('设置'));
      await tester.pumpAndSettle();
      final firstSettingsElement = tester.element(find.byType(SettingsScreen));

      // Detour through home.
      await tester.tap(_navDestination('功能大全'));
      await tester.pumpAndSettle();

      // Return to settings.
      await tester.tap(_navDestination('设置'));
      await tester.pumpAndSettle();
      final secondSettingsElement = tester.element(find.byType(SettingsScreen));

      expect(
        identical(firstSettingsElement, secondSettingsElement),
        isTrue,
        reason:
            'IndexedStack must reuse the existing element subtree, '
            'not rebuild from scratch — that\'s the state-preservation '
            'contract this task introduces.',
      );
    });
  });

  group('AppShell — R2 NavigationBar identity', () {
    testWidgets('NavigationBar element survives tab switches', (tester) async {
      await _pumpApp(tester);

      final navBarBefore = tester.element(find.byType(NavigationBar));

      await tester.tap(_navDestination('设置'));
      await tester.pumpAndSettle();
      final navBarAfterSwitch = tester.element(find.byType(NavigationBar));

      expect(
        identical(navBarBefore, navBarAfterSwitch),
        isTrue,
        reason:
            'The shell owns the NavigationBar; switching tabs '
            'must not tear it down and rebuild it.',
      );

      await tester.tap(_navDestination('功能大全'));
      await tester.pumpAndSettle();
      final navBarAfterSecondSwitch = tester.element(
        find.byType(NavigationBar),
      );
      expect(identical(navBarBefore, navBarAfterSecondSwitch), isTrue);
    });
  });

  group('AppShell — R8 Android back-key contract', () {
    testWidgets('pressing back on a non-home tab returns to the home tab '
        '(not system exit)', (tester) async {
      await _pumpApp(tester);

      // Land on settings (currentIndex == 3).
      await tester.tap(_navDestination('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Simulate Android system back. PopScope's onPopInvokedWithResult
      // fires; we expect the shell to swap to branch 0 instead of
      // exiting.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        handled,
        isTrue,
        reason:
            'PopScope(canPop: false) always reports the pop as '
            'handled, even when we redirect it.',
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byType(SettingsScreen),
        findsNothing,
        reason: 'Settings is offstage now, not unmounted',
      );
    });

    testWidgets('pressing back on the home tab invokes SystemNavigator.pop '
        '(Android system-exit path)', (tester) async {
      await _pumpApp(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      // Set up the platform-channel mock AFTER boot finished, so the
      // app's early initialization (system UI, locale, etc.) used
      // the real handler. We only want to observe SystemNavigator.pop.
      final systemNavigatorCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemNavigatorCalls.add(call.method);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        systemNavigatorCalls,
        contains('SystemNavigator.pop'),
        reason:
            'On the home branch, the shell should ask the OS to '
            'exit (no-op on iOS/desktop/web).',
      );
    });
  });
}
