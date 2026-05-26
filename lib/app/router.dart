import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_shell.dart';
import '../features/about/presentation/screens/about_screen.dart';
import '../features/export/presentation/screens/export_screen.dart';
import '../features/grid/presentation/screens/grid_editor_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/long_stitch/presentation/screens/stitch_editor_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';

/// Root navigator key. `/export` is registered against it explicitly so
/// it covers the bottom nav (modal flow), instead of being scoped to a
/// single branch's nested navigator.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Per-branch navigator keys. They let each tab keep its own [Navigator]
/// stack so pushing a sub-route inside one tab doesn't pop another tab's
/// stack — and so the `AppShell`'s `PopScope` correctly delegates
/// in-branch pops back to each branch.
final GlobalKey<NavigatorState> _homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'home',
);
final GlobalKey<NavigatorState> _stitchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'stitch',
);
final GlobalKey<NavigatorState> _gridNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'grid',
);
final GlobalKey<NavigatorState> _settingsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'settings');

/// Application-wide [GoRouter] configuration.
///
/// Topology: one [StatefulShellRoute.indexedStack] hosting the four
/// top-level tabs (功能大全 / 长图拼接 / 宫格切图 / 设置), plus sibling
/// root-level [GoRoute]s for `/export`, `/m/stitch`, `/m/grid` which are
/// intentionally outside the shell so they cover the bottom nav.
///
/// Tab branches are rendered through an [IndexedStack] internally, so
/// inactive branches retain their element tree and state survives
/// switches (per
/// `.trellis/spec/frontend/component-guidelines.md` →
/// "StatefulShellRoute + per-branch screen").
///
/// **Why `/m/stitch` + `/m/grid` exist** (since
/// `05-26-mobile-stitch-secondary-page`): on `WindowSizeClass.compact`
/// the bottom nav drops the two editor tabs and the home screen's
/// FeatureCards instead **push** into these root-level sibling routes,
/// which cover the shell and present each editor as a true secondary
/// page (AppBar back arrow, PopScope-intercepted exit). The same
/// [StitchEditorScreen] / [GridEditorScreen] widgets are reused — the
/// underlying Riverpod state survives across the branch-vs-sibling
/// entry points because controllers (`stitchEditorControllerProvider`,
/// etc.) are non-autoDispose and live in `ProviderScope`, which sits
/// above the router.
///
/// On medium / expanded / large the FeatureCards keep `context.go(...)`
/// into the branch routes, so desktop behavior is unchanged.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootNavigatorKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _stitchNavigatorKey,
          routes: [
            GoRoute(
              path: '/stitch',
              name: 'stitch',
              builder: (context, state) => const StitchEditorScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _gridNavigatorKey,
          routes: [
            GoRoute(
              path: '/grid',
              name: 'grid',
              builder: (context, state) => const GridEditorScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'about',
                  name: 'about',
                  builder: (context, state) => const AboutScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/export',
      name: 'export',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ExportScreen(),
    ),
    // Compact-only secondary-page entry points for the two editors.
    // Mounted as root-level siblings so they cover the AppShell's bottom
    // nav and Flutter's `automaticallyImplyLeading` gives them a back
    // arrow out-of-the-box. The `/m/` prefix is the project's "mobile
    // secondary page" convention — see the file-level doc-comment above
    // and `.trellis/spec/frontend/component-guidelines.md`.
    GoRoute(
      path: '/m/stitch',
      name: 'mobileStitch',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StitchEditorScreen(),
    ),
    GoRoute(
      path: '/m/grid',
      name: 'mobileGrid',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const GridEditorScreen(),
    ),
  ],
);
