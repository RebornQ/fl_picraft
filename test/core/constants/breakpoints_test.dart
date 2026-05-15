import 'package:fl_picraft/core/constants/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('windowSizeClassFromWidth', () {
    test('returns compact for widths strictly below 600 dp', () {
      expect(windowSizeClassFromWidth(0), WindowSizeClass.compact);
      expect(windowSizeClassFromWidth(320), WindowSizeClass.compact);
      expect(windowSizeClassFromWidth(599.999), WindowSizeClass.compact);
    });

    test('returns medium for widths in [600, 840)', () {
      expect(windowSizeClassFromWidth(600), WindowSizeClass.medium);
      expect(windowSizeClassFromWidth(720), WindowSizeClass.medium);
      expect(windowSizeClassFromWidth(839.999), WindowSizeClass.medium);
    });

    test('returns expanded for widths in [840, 1200)', () {
      expect(windowSizeClassFromWidth(840), WindowSizeClass.expanded);
      expect(windowSizeClassFromWidth(1024), WindowSizeClass.expanded);
      expect(windowSizeClassFromWidth(1199.999), WindowSizeClass.expanded);
    });

    test('returns large for widths >= 1200', () {
      expect(windowSizeClassFromWidth(1200), WindowSizeClass.large);
      expect(windowSizeClassFromWidth(1440), WindowSizeClass.large);
      expect(windowSizeClassFromWidth(2560), WindowSizeClass.large);
    });
  });

  group('windowSizeClassOf', () {
    Widget harness({
      required Size size,
      required ValueSetter<WindowSizeClass> onBuilt,
    }) {
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            onBuilt(windowSizeClassOf(context));
            return const SizedBox.shrink();
          },
        ),
      );
    }

    testWidgets('resolves compact from MediaQuery', (tester) async {
      WindowSizeClass? observed;
      await tester.pumpWidget(
        harness(size: const Size(400, 800), onBuilt: (cls) => observed = cls),
      );
      expect(observed, WindowSizeClass.compact);
    });

    testWidgets('resolves medium from MediaQuery', (tester) async {
      WindowSizeClass? observed;
      await tester.pumpWidget(
        harness(size: const Size(720, 1024), onBuilt: (cls) => observed = cls),
      );
      expect(observed, WindowSizeClass.medium);
    });

    testWidgets('resolves expanded from MediaQuery', (tester) async {
      WindowSizeClass? observed;
      await tester.pumpWidget(
        harness(size: const Size(1024, 768), onBuilt: (cls) => observed = cls),
      );
      expect(observed, WindowSizeClass.expanded);
    });

    testWidgets('resolves large from MediaQuery', (tester) async {
      WindowSizeClass? observed;
      await tester.pumpWidget(
        harness(size: const Size(1600, 900), onBuilt: (cls) => observed = cls),
      );
      expect(observed, WindowSizeClass.large);
    });
  });

  group('Breakpoints sanity', () {
    test('breakpoints follow Material 3 ordering', () {
      expect(Breakpoints.compact < Breakpoints.medium, isTrue);
      expect(Breakpoints.medium < Breakpoints.expanded, isTrue);
      expect(Breakpoints.maxContentWidth >= Breakpoints.expanded, isTrue);
    });
  });
}
