import 'package:fl_picraft/core/constants/breakpoints.dart';
import 'package:fl_picraft/core/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks the four bottom-nav destination [IconData]s in place so a
/// careless rename of `Icons.foo` doesn't silently shift the tab icons.
///
/// `destinations[1]` migrated from `photo_library` →
/// `view_agenda` as part of the long-stitch UX polish task
/// (PRD R3 / AC4): the photo-library glyph reads as "album of
/// pictures" but the feature is "stack several pictures into one
/// vertical strip" — `view_agenda` (a vertical stack of card-shaped
/// rows) carries that meaning more directly. The other three
/// destinations are untouched.
void main() {
  group('AppBottomNavBar destinations', () {
    test('destinations[0] uses the apps icon family (功能大全)', () {
      final destination = AppBottomNavBar.destinations[0];
      expect(destination.label, '功能大全');
      expect(destination.icon, Icons.apps_outlined);
      expect(destination.selectedIcon, Icons.apps);
      expect(destination.location, '/');
    });

    test('destinations[1] uses the view_agenda icon family (长图拼接)', () {
      final destination = AppBottomNavBar.destinations[1];
      expect(destination.label, '长图拼接');
      expect(destination.icon, Icons.view_agenda_outlined);
      expect(destination.selectedIcon, Icons.view_agenda);
      expect(destination.location, '/stitch');
    });

    test('destinations[2] uses the grid_view icon family (宫格切图)', () {
      final destination = AppBottomNavBar.destinations[2];
      expect(destination.label, '宫格切图');
      expect(destination.icon, Icons.grid_view_outlined);
      expect(destination.selectedIcon, Icons.grid_view);
      expect(destination.location, '/grid');
    });

    test('destinations[3] uses the settings icon family (设置)', () {
      final destination = AppBottomNavBar.destinations[3];
      expect(destination.label, '设置');
      expect(destination.icon, Icons.settings_outlined);
      expect(destination.selectedIcon, Icons.settings);
      expect(destination.location, '/settings');
    });

    test('declares exactly 4 destinations', () {
      expect(AppBottomNavBar.destinations, hasLength(4));
    });
  });

  // Per 05-26-mobile-stitch-secondary-page: the compact bar drops the
  // stitch / grid destinations because compact users enter the editors
  // as secondary pages pushed from the home FeatureCards. Lock the
  // size-class-aware filtering so the convention can't silently revert.
  group('AppBottomNavBar.destinationsFor (size-class aware)', () {
    test('compact returns only home + settings (in that order)', () {
      final list = AppBottomNavBar.destinationsFor(WindowSizeClass.compact);
      expect(list, hasLength(2));
      expect(list[0].label, '功能大全');
      expect(list[0].location, '/');
      expect(list[1].label, '设置');
      expect(list[1].location, '/settings');
    });

    test('medium returns all four destinations in branch order', () {
      final list = AppBottomNavBar.destinationsFor(WindowSizeClass.medium);
      expect(list, hasLength(4));
      expect(list.map((d) => d.label).toList(), ['功能大全', '长图拼接', '宫格切图', '设置']);
    });

    test('expanded returns all four destinations', () {
      final list = AppBottomNavBar.destinationsFor(WindowSizeClass.expanded);
      expect(list, hasLength(4));
    });

    test('large returns all four destinations', () {
      final list = AppBottomNavBar.destinationsFor(WindowSizeClass.large);
      expect(list, hasLength(4));
    });
  });

  // Locks the branch ↔ display index translation used by AppShell to
  // paint NavigationBar.selectedIndex correctly when destinations are
  // trimmed.
  group('AppBottomNavBar index mapping', () {
    test('non-compact size classes are identity-mapped', () {
      for (final sc in [
        WindowSizeClass.medium,
        WindowSizeClass.expanded,
        WindowSizeClass.large,
      ]) {
        for (var i = 0; i < 4; i++) {
          expect(
            AppBottomNavBar.branchToDisplayIndex(i, sc),
            i,
            reason: '$sc / branch $i should be identity',
          );
          expect(
            AppBottomNavBar.displayToBranchIndex(i, sc),
            i,
            reason: '$sc / display $i should be identity',
          );
        }
      }
    });

    test('compact: branch 0 (home) → display 0', () {
      expect(
        AppBottomNavBar.branchToDisplayIndex(0, WindowSizeClass.compact),
        0,
      );
    });

    test('compact: branch 3 (settings) → display 1', () {
      expect(
        AppBottomNavBar.branchToDisplayIndex(3, WindowSizeClass.compact),
        1,
      );
    });

    test('compact: branches 1 / 2 (stitch / grid) fall back to display 0 '
        '(home) — AppShell schedules a reconcile on the next frame', () {
      expect(
        AppBottomNavBar.branchToDisplayIndex(1, WindowSizeClass.compact),
        0,
      );
      expect(
        AppBottomNavBar.branchToDisplayIndex(2, WindowSizeClass.compact),
        0,
      );
    });

    test('compact: display 0 → branch 0 (home); display 1 → branch 3 '
        '(settings)', () {
      expect(
        AppBottomNavBar.displayToBranchIndex(0, WindowSizeClass.compact),
        0,
      );
      expect(
        AppBottomNavBar.displayToBranchIndex(1, WindowSizeClass.compact),
        3,
      );
    });
  });

  group('AppBottomNavBar widget', () {
    testWidgets('medium width renders all four labels in branch order', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
              sizeClass: WindowSizeClass.medium,
            ),
          ),
        ),
      );

      expect(find.text('功能大全'), findsOneWidget);
      expect(find.text('长图拼接'), findsOneWidget);
      expect(find.text('宫格切图'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('renders the new view_agenda icon for the stitch tab '
        '(medium)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
              sizeClass: WindowSizeClass.medium,
            ),
          ),
        ),
      );

      // Unselected tab uses the outlined glyph.
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
      // The old photo_library icon should NOT be present anywhere in
      // the bar (catches accidental regression to the prior IconData).
      expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
      expect(find.byIcon(Icons.photo_library), findsNothing);
    });

    testWidgets('selected stitch tab swaps to the filled view_agenda icon '
        '(medium)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 1,
              onDestinationSelected: (_) {},
              sizeClass: WindowSizeClass.medium,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.view_agenda), findsOneWidget);
    });

    testWidgets('compact width hides stitch / grid destinations and only '
        'shows home + settings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
              sizeClass: WindowSizeClass.compact,
            ),
          ),
        ),
      );

      expect(find.text('功能大全'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('长图拼接'), findsNothing);
      expect(find.text('宫格切图'), findsNothing);
    });

    testWidgets('compact width: tapping the settings destination invokes '
        'the callback with branch index 3 (not display index 1)', (
      tester,
    ) async {
      int? lastBranchIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (i) => lastBranchIndex = i,
              sizeClass: WindowSizeClass.compact,
            ),
          ),
        ),
      );

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(
        lastBranchIndex,
        3,
        reason:
            'AppBottomNavBar must translate display index 1 → branch 3 '
            'before invoking the callback so AppShell can call goBranch '
            'with the right index.',
      );
    });
  });
}
