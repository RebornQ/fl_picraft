import 'package:flutter/material.dart';

import '../constants/breakpoints.dart';

/// A single destination in the [AppBottomNavBar].
class AppNavDestination {
  const AppNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.location,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The branch's initial location. Kept for documentation / deep-link
  /// tooling — the [AppBottomNavBar] itself no longer uses it for
  /// active-index resolution. Branch selection is owned by
  /// `StatefulNavigationShell` upstream.
  final String location;
}

/// Bottom navigation bar shared by the four top-level branches.
///
/// Uses Material 3 [NavigationBar]. The selected branch index and tap
/// callback are injected by the surrounding `AppShell` so that the bar is
/// purely presentational and the bar widget itself does **not** rebuild
/// when the active branch changes within the same size class (only its
/// `selectedIndex` updates).
///
/// **Size-class aware destinations** (since
/// `05-26-mobile-stitch-secondary-page`):
///
/// On `WindowSizeClass.compact` (< 600 dp) the bar renders only **two**
/// destinations — 「功能大全」「设置」(branch indices 0 and 3). The two
/// editor branches (「长图拼接」/「宫格切图」, branch indices 1 and 2) are
/// hidden because compact users enter the editors as **secondary pages**
/// pushed from the home screen's feature cards (sibling root-level
/// GoRoutes `/m/stitch`、`/m/grid` that cover the shell). Medium /
/// expanded / large continue to render all four destinations and the
/// editors stay as top-level tabs — the desktop-side topology is
/// unchanged.
///
/// **Index mapping**: when destinations are trimmed on compact, the
/// `NavigationBar`'s displayed selected-index no longer equals the
/// underlying `StatefulShellRoute` branch index. [AppBottomNavBar]
/// exposes [displayToBranchIndex] / [branchToDisplayIndex] helpers that
/// `AppShell` uses to translate in both directions so:
///
/// - `selectedIndex: branchToDisplayIndex(navigationShell.currentIndex,
///   sizeClass)` paints the right destination as active;
/// - `onDestinationSelected(displayIndex)` → `displayToBranchIndex(...)`
///   gives the branch to navigate to.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.sizeClass,
  });

  /// The currently active **branch** index (0..3, matching
  /// `appRouter`'s branch order). [AppBottomNavBar] internally maps this
  /// to the displayed selected-index for the current size class via
  /// [branchToDisplayIndex].
  final int currentIndex;

  /// Invoked with the **branch** index to navigate to (already mapped
  /// from the tapped destination's display index — the surrounding
  /// `AppShell` handles the display→branch translation before calling
  /// `navigationShell.goBranch(...)`).
  final ValueChanged<int> onDestinationSelected;

  /// Drives the size-class-aware destination filtering. The bar itself
  /// reads this rather than calling [windowSizeClassOf] to keep the
  /// widget pure / testable (callers can pass a synthetic size class).
  final WindowSizeClass sizeClass;

  /// All four destinations in branch order. The index matches the
  /// `StatefulShellBranch` order declared in `lib/app/router.dart` —
  /// keep the two in sync when adding / reordering tabs.
  ///
  /// **Do not** index this directly for the visible destination list —
  /// use [destinationsFor] which filters by size class. This constant is
  /// preserved for backwards-compatible test access and for callers that
  /// genuinely need the canonical branch metadata.
  static const List<AppNavDestination> destinations = [
    AppNavDestination(
      label: '功能大全',
      icon: Icons.apps_outlined,
      selectedIcon: Icons.apps,
      location: '/',
    ),
    AppNavDestination(
      label: '长图拼接',
      icon: Icons.view_agenda_outlined,
      selectedIcon: Icons.view_agenda,
      location: '/stitch',
    ),
    AppNavDestination(
      label: '宫格切图',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
      location: '/grid',
    ),
    AppNavDestination(
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      location: '/settings',
    ),
  ];

  /// The displayed destinations for the given [sizeClass].
  ///
  /// - `compact` → `[功能大全, 设置]` (the two editor entries move to
  ///   secondary pages pushed from the home FeatureCards).
  /// - any other size class → all four destinations.
  static List<AppNavDestination> destinationsFor(WindowSizeClass sizeClass) {
    if (sizeClass == WindowSizeClass.compact) {
      // Indices 0 (home) + 3 (settings).
      return const [_homeDestination, _settingsDestination];
    }
    return destinations;
  }

  /// Translates a branch index (0..3) into the visible destination index
  /// for the given [sizeClass]. Used by [AppShell] to paint the right
  /// `NavigationBar.selectedIndex` when destinations are trimmed.
  ///
  /// On compact, an unreachable branch index (1 = stitch, 2 = grid)
  /// falls back to 0 (home) so the bar still paints a coherent state if
  /// the window is dragged from desktop down to compact while one of
  /// those branches is active. The surrounding shell is expected to
  /// schedule a `goBranch(0)` correction on the next frame — see
  /// `AppShell._reconcileBranchForSizeClass`.
  static int branchToDisplayIndex(int branchIndex, WindowSizeClass sizeClass) {
    if (sizeClass != WindowSizeClass.compact) return branchIndex;
    return switch (branchIndex) {
      0 => 0, // home → displayed at index 0
      3 => 1, // settings → displayed at index 1
      _ => 0, // stitch / grid (unreachable on compact) → fall back to home
    };
  }

  /// Translates the displayed destination index back to the underlying
  /// branch index for the given [sizeClass]. Used by [AppShell] when the
  /// user taps a destination.
  static int displayToBranchIndex(int displayIndex, WindowSizeClass sizeClass) {
    if (sizeClass != WindowSizeClass.compact) return displayIndex;
    // compact: [home=0, settings=1] → [branch 0, branch 3]
    return displayIndex == 0 ? 0 : 3;
  }

  @override
  Widget build(BuildContext context) {
    final displayed = destinationsFor(sizeClass);
    return NavigationBar(
      selectedIndex: branchToDisplayIndex(currentIndex, sizeClass),
      onDestinationSelected: (displayIndex) {
        final branchIndex = displayToBranchIndex(displayIndex, sizeClass);
        onDestinationSelected(branchIndex);
      },
      destinations: [
        for (final d in displayed)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: d.label,
          ),
      ],
    );
  }
}

// Aliases used by [AppBottomNavBar.destinationsFor] so the compact list
// is a `const` and the bar's destinations don't reallocate on every
// rebuild.
const AppNavDestination _homeDestination = AppNavDestination(
  label: '功能大全',
  icon: Icons.apps_outlined,
  selectedIcon: Icons.apps,
  location: '/',
);

const AppNavDestination _settingsDestination = AppNavDestination(
  label: '设置',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  location: '/settings',
);
