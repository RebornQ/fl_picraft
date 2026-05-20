import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/grid/presentation/widgets/grid_type_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SafeArea(child: child)),
  );

  testWidgets('renders one card per PRD variant (5 total)', (tester) async {
    await tester.pumpWidget(
      wrap(GridTypeSelector(value: GridType.g3x3, onChanged: (_) {})),
    );

    // ListView.separated lazy-builds children — scroll through every
    // variant to assert the card actually mounts for that type.
    final listView = find.byType(Scrollable).first;
    for (final type in GridType.values) {
      final keyFinder = find.byKey(ValueKey('grid-type-${type.name}'));
      await tester.scrollUntilVisible(keyFinder, 50, scrollable: listView);
      expect(
        keyFinder,
        findsOneWidget,
        reason: 'Missing card for ${type.name}',
      );
    }
  });

  testWidgets('every variant card surfaces its 中文 title and description', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(GridTypeSelector(value: GridType.g3x3, onChanged: (_) {})),
    );

    // The selector scrolls horizontally — pump `dragUntilVisible` for the
    // off-screen labels so findsOneWidget can locate them.
    final listView = find.byType(Scrollable).first;
    for (final type in GridType.values) {
      final titleFinder = find.text(type.displayTitle);
      await tester.scrollUntilVisible(titleFinder, 50, scrollable: listView);
      expect(titleFinder, findsOneWidget);
      final descFinder = find.text(type.displayDescription);
      expect(descFinder, findsOneWidget);
    }
  });

  testWidgets('tapping an inactive card fires onChanged with that GridType', (
    tester,
  ) async {
    GridType? lastValue;

    await tester.pumpWidget(
      wrap(
        GridTypeSelector(value: GridType.g3x3, onChanged: (t) => lastValue = t),
      ),
    );

    // 1x2 is left of 3x3 and visible on first paint.
    await tester.tap(find.byKey(const ValueKey('grid-type-g1x2')));
    await tester.pumpAndSettle();

    expect(lastValue, GridType.g1x2);
  });

  testWidgets('tapping the already-active card still emits the same value '
      '(parent decides whether to ignore)', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      wrap(GridTypeSelector(value: GridType.g3x3, onChanged: (_) => calls++)),
    );

    // Scroll to make sure g3x3 is visible before tapping.
    final listView = find.byType(Scrollable).first;
    final activeCard = find.byKey(const ValueKey('grid-type-g3x3'));
    await tester.scrollUntilVisible(activeCard, 50, scrollable: listView);
    await tester.pumpAndSettle();
    await tester.tap(activeCard);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('header copy 宫格类型 is rendered above the cards', (tester) async {
    await tester.pumpWidget(
      wrap(GridTypeSelector(value: GridType.g3x3, onChanged: (_) {})),
    );

    expect(find.text('宫格类型'), findsOneWidget);
  });

  testWidgets('lockedTo dims non-locked cards and ignores taps on them', (
    tester,
  ) async {
    GridType? lastValue;
    await tester.pumpWidget(
      wrap(
        GridTypeSelector(
          value: GridType.g3x3,
          lockedTo: GridType.g3x3,
          onChanged: (t) => lastValue = t,
        ),
      ),
    );

    // Tap on 1x2 — should be ignored.
    await tester.tap(find.byKey(const ValueKey('grid-type-g1x2')));
    await tester.pumpAndSettle();
    expect(lastValue, isNull);

    // 1x2 card is wrapped in an Opacity widget — its opacity is < 1.
    final opacities = tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byKey(const ValueKey('grid-type-g1x2')),
            matching: find.byType(Opacity),
          ),
        )
        .toList();
    expect(opacities, isNotEmpty);
    expect(opacities.first.opacity, lessThan(1));
  });

  testWidgets('lockedTo target card still emits onChanged on tap', (
    tester,
  ) async {
    GridType? lastValue;
    await tester.pumpWidget(
      wrap(
        GridTypeSelector(
          value: GridType.g3x3,
          lockedTo: GridType.g3x3,
          onChanged: (t) => lastValue = t,
        ),
      ),
    );

    // Scroll so g3x3 is visible, then tap. The active card has
    // `elevation: 2` which means Material's hit-test still works as
    // long as the widget is mounted and not clipped.
    final listView = find.byType(Scrollable).first;
    final card = find.byKey(const ValueKey('grid-type-g3x3'));
    await tester.scrollUntilVisible(card, 50, scrollable: listView);
    await tester.pumpAndSettle();
    await tester.tap(card, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(lastValue, GridType.g3x3);
  });

  // ────────────────────────────────────────────────────────────────
  // Default-selection visibility (05-20 grid-controls-chrome-cap
  // Addendum). The editor defaults to g3x3 which sits at the end of
  // kGridTypeSelectorOrder; without auto-scroll the selected card is
  // off-screen on first paint.
  // ────────────────────────────────────────────────────────────────

  ScrollController controllerOfFirstScrollable(WidgetTester tester) {
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    return scrollable.controller!;
  }

  testWidgets(
    'value = g3x3 (last) auto-scrolls so selected card becomes visible',
    (tester) async {
      // Narrow viewport so g3x3 is genuinely off-screen at offset 0.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrap(GridTypeSelector(value: GridType.g3x3, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      final controller = controllerOfFirstScrollable(tester);
      expect(
        controller.offset,
        greaterThan(0),
        reason: 'g3x3 sits at index 4; default mount should auto-scroll',
      );
    },
  );

  testWidgets('value = g1x2 (first) keeps offset at 0 (no scroll needed)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(GridTypeSelector(value: GridType.g1x2, onChanged: (_) {})),
    );
    await tester.pumpAndSettle();

    final controller = controllerOfFirstScrollable(tester);
    expect(controller.offset, 0.0);
  });

  testWidgets(
    'didUpdateWidget: switching value from g1x2 to g3x3 auto-scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var currentValue = GridType.g1x2;
      late StateSetter setOuterState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuterState = setState;
                  return GridTypeSelector(
                    value: currentValue,
                    onChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controllerBefore = controllerOfFirstScrollable(tester);
      expect(controllerBefore.offset, 0.0);

      setOuterState(() => currentValue = GridType.g3x3);
      await tester.pumpAndSettle();

      final controllerAfter = controllerOfFirstScrollable(tester);
      expect(
        controllerAfter.offset,
        greaterThan(0),
        reason: 'didUpdateWidget should re-trigger scroll-to-selected',
      );
    },
  );
}
