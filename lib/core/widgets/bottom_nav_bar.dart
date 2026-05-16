import 'package:flutter/material.dart';

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
/// Uses Material 3 [NavigationBar]. The selected index and tap callback
/// are injected by the surrounding `AppShell` so that the bar is purely
/// presentational and the bar widget itself does **not** rebuild on tab
/// changes (only its `selectedIndex` updates).
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Destinations in branch order. The index matches the
  /// `StatefulShellBranch` order declared in `lib/app/router.dart` —
  /// keep the two in sync when adding / reordering tabs.
  static const List<AppNavDestination> destinations = [
    AppNavDestination(
      label: '功能大全',
      icon: Icons.apps_outlined,
      selectedIcon: Icons.apps,
      location: '/',
    ),
    AppNavDestination(
      label: '长图拼接',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library,
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

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (final d in destinations)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: d.label,
          ),
      ],
    );
  }
}
