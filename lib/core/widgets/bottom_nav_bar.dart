import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  final String location;
}

/// Bottom navigation bar shared by the four top-level routes.
///
/// Uses Material 3 [NavigationBar]. The current selection is derived from
/// [GoRouterState.uri] so that hot-reload and deep-links keep it in sync.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key});

  static const List<AppNavDestination> destinations = [
    AppNavDestination(
      label: '作品库',
      icon: Icons.image_outlined,
      selectedIcon: Icons.image,
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

  int _indexFor(String location) {
    for (var i = 0; i < destinations.length; i++) {
      final dest = destinations[i].location;
      if (dest == '/') {
        if (location == '/') return i;
      } else if (location == dest || location.startsWith('$dest/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex = _indexFor(location);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        final target = destinations[index].location;
        if (target != location) {
          context.go(target);
        }
      },
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
