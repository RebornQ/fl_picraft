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

  group('AppBottomNavBar widget', () {
    testWidgets('renders all four labels in branch order', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('功能大全'), findsOneWidget);
      expect(find.text('长图拼接'), findsOneWidget);
      expect(find.text('宫格切图'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('renders the new view_agenda icon for the stitch tab', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
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

    testWidgets('selected stitch tab swaps to the filled view_agenda icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: 1,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.view_agenda), findsOneWidget);
    });
  });
}
