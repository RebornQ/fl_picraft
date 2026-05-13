import 'package:fl_picraft/features/export/domain/entities/watermark_anchor.dart';
import 'package:fl_picraft/features/export/domain/entities/watermark_config.dart';
import 'package:fl_picraft/features/export/presentation/providers/watermark_config_provider.dart';
import 'package:fl_picraft/features/export/presentation/widgets/watermark_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pumpHarness({ProviderContainer? container}) {
    final c = container ?? ProviderContainer();
    return UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: WatermarkCard(),
          ),
        ),
      ),
    );
  }

  testWidgets('master toggle flips enabled state in the provider', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    expect(container.read(watermarkConfigProvider).enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(watermarkConfigProvider).enabled, isTrue);
  });

  testWidgets('controls are inert when toggle is off', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    // Anchor stays at default while controls are disabled — we can't
    // tap through IgnorePointer, but we can still call the notifier
    // directly to verify the state machine itself is unconstrained.
    expect(
      container.read(watermarkConfigProvider).anchor,
      kDefaultWatermarkAnchor,
    );
    final ignoring = find.byWidgetPredicate(
      (w) => w is IgnorePointer && w.ignoring,
    );
    expect(ignoring, findsOneWidget);
  });

  testWidgets('tapping a position cell updates the anchor', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));
    // Enable first so the IgnorePointer doesn't swallow taps.
    container.read(watermarkConfigProvider.notifier).setEnabled(true);
    await tester.pumpAndSettle();

    final topLeft = find.bySemanticsLabel(
      'Watermark position ${WatermarkAnchor.topLeft.name}',
    );
    expect(topLeft, findsOneWidget);
    await tester.tap(topLeft, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      container.read(watermarkConfigProvider).anchor,
      WatermarkAnchor.topLeft,
    );
  });

  testWidgets('opacity slider value renders as percent', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    // Default 50%.
    expect(find.text('50%'), findsOneWidget);

    container.read(watermarkConfigProvider.notifier).setOpacity(0.75);
    await tester.pumpAndSettle();

    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('setOpacity clamps to [0.1, 1.0]', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(watermarkConfigProvider.notifier);
    notifier.setOpacity(0);
    expect(container.read(watermarkConfigProvider).opacity, closeTo(0.1, 1e-9));
    notifier.setOpacity(5);
    expect(container.read(watermarkConfigProvider).opacity, 1.0);
  });

  testWidgets('setText caps at the spec-defined max length', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final long = 'x' * 200;
    container.read(watermarkConfigProvider.notifier).setText(long);
    expect(container.read(watermarkConfigProvider).text.length, 40);
  });
}
