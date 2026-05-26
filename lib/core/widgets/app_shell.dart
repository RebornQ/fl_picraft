import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../constants/breakpoints.dart';
import 'bottom_nav_bar.dart';

/// Stateful shell hosting the four top-level tabs.
///
/// Owns the [Scaffold] + [AppBottomNavBar] so that NavigationBar itself
/// is **not** torn down on tab switches (within the same window size
/// class — see the size-class section below). Each branch keeps its own
/// [Navigator] stack inside [StatefulNavigationShell], so widget state,
/// scroll positions, and Riverpod notifiers survive tab switches.
///
/// **Size-class aware bottom nav** (since
/// `05-26-mobile-stitch-secondary-page`):
///
/// On `WindowSizeClass.compact` (< 600 dp) the bar renders only
/// 「功能大全」「设置」two destinations. The two editor branches
/// (stitch / grid) become **secondary pages** pushed from the home
/// screen via sibling root-level GoRoutes `/m/stitch`、`/m/grid` that
/// cover the shell. On medium / expanded / large the bar keeps all
/// four destinations and the editors stay as branch tabs — desktop
/// behavior is unchanged.
///
/// The shell translates between branch indices (what
/// `StatefulShellRoute` knows) and display indices (what
/// `NavigationBar.selectedIndex` expects) via
/// [AppBottomNavBar.branchToDisplayIndex] /
/// [AppBottomNavBar.displayToBranchIndex] so the two stay in sync even
/// when destinations are trimmed.
///
/// **Reconciling stale branch state on compact** (edge case): if the
/// user is sitting on a stitch/grid tab on a wide window and shrinks
/// the window into compact, `navigationShell.currentIndex` is 1 or 2
/// — an index the compact bar can't display. The shell schedules a
/// post-frame `navigationShell.goBranch(0)` to pull the user back to
/// home, matching the spirit of "compact users enter editors as
/// secondary pages, not as tabs".
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
///
/// Note: when a user pushes `/m/stitch` or `/m/grid` (root-level
/// sibling routes for compact secondary pages), the secondary screen
/// gets its own `PopScope` (added in commit 2 of the same task) and
/// the shell's contract above does not fire — the deepest Navigator
/// wins first.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final sizeClass = windowSizeClassOf(context);
    _reconcileBranchForSizeClass(sizeClass);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: navigationShell.currentIndex,
          onDestinationSelected: _onBranchSelected,
          sizeClass: sizeClass,
        ),
      ),
    );
  }

  /// Handles a tap on the bottom nav. [branchIndex] is already mapped
  /// from the display index by [AppBottomNavBar] using the active size
  /// class, so this only needs the branch-side no-op + dispatch logic.
  void _onBranchSelected(int branchIndex) {
    // Re-tapping the active tab is a no-op (per task Out-of-Scope —
    // "二次点击当前 tab 重置 / 滚到顶" is its own future task). Bail
    // before calling goBranch so we don't even round-trip through the
    // shell's controller.
    if (branchIndex == navigationShell.currentIndex) return;
    navigationShell.goBranch(branchIndex);
  }

  /// Edge-case reconciliation: if the window shrinks into compact while
  /// the user sits on a stitch / grid branch (indices 1 / 2 — branches
  /// the compact bar cannot display), schedule a `goBranch(0)` after the
  /// current frame so the user lands back on home. Without this, the
  /// `NavigationBar` paints "home" as selected (via the index-mapping
  /// fall-back) while the `IndexedStack` keeps showing the editor — a
  /// confusing visual mismatch.
  ///
  /// Scheduling via `addPostFrameCallback` avoids mutating
  /// `navigationShell` mid-build, which Flutter forbids.
  void _reconcileBranchForSizeClass(WindowSizeClass sizeClass) {
    if (sizeClass != WindowSizeClass.compact) return;
    final current = navigationShell.currentIndex;
    if (current == 0 || current == 3) return; // home / settings are fine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-check after the frame — the user (or another frame's reconcile)
      // may have already moved off the editor branch.
      if (navigationShell.currentIndex == 1 ||
          navigationShell.currentIndex == 2) {
        navigationShell.goBranch(0);
      }
    });
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
