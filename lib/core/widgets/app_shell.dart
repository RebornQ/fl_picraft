import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'bottom_nav_bar.dart';

/// Stateful shell hosting the four top-level tabs.
///
/// Owns the [Scaffold] + [AppBottomNavBar] so that NavigationBar itself
/// is **not** torn down on tab switches. Each branch keeps its own
/// [Navigator] stack inside [StatefulNavigationShell], so widget state,
/// scroll positions, and Riverpod notifiers survive tab switches.
///
/// **Android back-key contract** (R8 in
/// `.trellis/tasks/05-16-bottom-nav-switch-optimization/prd.md`):
///
/// 1. Branch navigator can pop → the inner Navigator pops one route
///    off its own stack and consumes the back-key. This shell's
///    `PopScope` never fires because the system back is dispatched
///    to the deepest active Navigator first; only when that
///    Navigator is at the branch root does the pop bubble outward.
/// 2. Else if `currentIndex != 0` → swap back to the home branch.
/// 3. Else → call [SystemNavigator.pop] (Android-only system exit;
///    no-op on iOS / desktop / web, where the OS handles termination).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    // Re-tapping the active tab is a no-op (per task Out-of-Scope —
    // "二次点击当前 tab 重置 / 滚到顶" is its own future task). Bail
    // before calling goBranch so we don't even round-trip through the
    // shell's controller.
    if (index == navigationShell.currentIndex) return;
    navigationShell.goBranch(index);
  }

  Future<void> _handlePop(bool didPop, Object? _) async {
    if (didPop) return;
    if (navigationShell.currentIndex != 0) {
      navigationShell.goBranch(0);
      return;
    }
    // Home branch + nothing left to pop → real exit. SystemNavigator.pop
    // is a no-op on non-Android platforms, so this is safe to call
    // unconditionally.
    await SystemNavigator.pop();
  }
}
