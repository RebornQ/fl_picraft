import 'package:go_router/go_router.dart';

import '../features/export/presentation/screens/export_screen.dart';
import '../features/grid/presentation/screens/grid_editor_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/stitch/presentation/screens/stitch_editor_screen.dart';

/// Application-wide [GoRouter] configuration.
///
/// Routes are kept flat: each top-level destination has its own bottom-nav
/// entry, and shared chrome is provided per-screen via [AppScaffold] rather
/// than a [ShellRoute]. This keeps placeholder screens trivially droppable
/// when the real implementations land.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/stitch',
      name: 'stitch',
      builder: (context, state) => const StitchEditorScreen(),
    ),
    GoRoute(
      path: '/grid',
      name: 'grid',
      builder: (context, state) => const GridEditorScreen(),
    ),
    GoRoute(
      path: '/export',
      name: 'export',
      builder: (context, state) => const ExportScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
