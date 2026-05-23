import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/presentation/providers/export_controller.dart';
import 'package:fl_picraft/features/export/presentation/widgets/format_quality_card.dart';
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
            child: FormatQualityCard(),
          ),
        ),
      ),
    );
  }

  testWidgets('renders both format buttons with PNG selected by default', (
    tester,
  ) async {
    await tester.pumpWidget(pumpHarness());

    expect(find.text('JPG'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    // PNG is the new lossless default → slider is hidden, no `%` label.
    expect(find.byType(Slider), findsNothing);
    expect(find.text('最小体积'), findsNothing);
    expect(find.text('最高质量'), findsNothing);
  });

  testWidgets('switching to JPG reveals the quality slider at 100%', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));
    expect(find.byType(Slider), findsNothing);

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    await tester.pumpAndSettle();

    // Quality slider visible — default quality is now max (100) so a
    // one-tap flip to JPG yields the highest-fidelity JPG.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('最小体积'), findsOneWidget);
    expect(find.text('最高质量'), findsOneWidget);
  });

  testWidgets('switching back to PNG hides the slider again', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.png);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tapping the JPG button updates the controller', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));
    expect(container.read(exportControllerProvider).format, ExportFormat.png);

    await tester.tap(find.text('JPG'));
    await tester.pumpAndSettle();

    expect(container.read(exportControllerProvider).format, ExportFormat.jpg);
  });

  testWidgets('quality slider reflects controller state in JPG mode', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    // Slider is only rendered for JPG. Flip format first.
    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    container.read(exportControllerProvider.notifier).setQuality(42);
    await tester.pumpAndSettle();

    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('setQuality clamps to [1, 100]', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(exportControllerProvider.notifier);
    notifier.setQuality(-5);
    expect(container.read(exportControllerProvider).quality, 1);
    notifier.setQuality(9999);
    expect(container.read(exportControllerProvider).quality, 100);
  });

  testWidgets('dragging the slider does NOT submit to the controller', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    // Reveal the slider by switching to JPG. After this, quality is at
    // the default (100).
    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    await tester.pumpAndSettle();
    expect(container.read(exportControllerProvider).quality, 100);

    // Simulate mid-drag onChanged ticks by invoking the Slider's
    // callback directly — this is more deterministic than gesture
    // simulation and proves the wiring contract regardless of the
    // platform's pointer dispatch.
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(50.0);
    slider.onChanged!(30.0);
    slider.onChanged!(20.0);
    await tester.pumpAndSettle();

    // Controller quality is unchanged — no upward submission while
    // dragging.
    expect(container.read(exportControllerProvider).quality, 100);

    // The percentage text and slider position DID follow the finger.
    expect(find.text('20%'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 20.0);
  });

  testWidgets('releasing the slider submits the final value exactly once', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    await tester.pumpAndSettle();
    expect(container.read(exportControllerProvider).quality, 100);

    // Drag to 65, drag to 60, then release at 60.
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(65.0);
    slider.onChanged!(60.0);
    await tester.pumpAndSettle();
    expect(
      container.read(exportControllerProvider).quality,
      100,
      reason: 'drag should not submit',
    );

    // Release — this is the only place upward submission happens.
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(60.0);
    await tester.pumpAndSettle();

    expect(container.read(exportControllerProvider).quality, 60);
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets(
    'releasing after dragging back to original value does not change state',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(pumpHarness(container: container));

      container
          .read(exportControllerProvider.notifier)
          .setFormat(ExportFormat.jpg);
      // Preset quality to 80 so the "drag away and back" case is
      // observable.
      container.read(exportControllerProvider.notifier).setQuality(80);
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      // Drag away, then back.
      slider.onChanged!(40.0);
      slider.onChanged!(80.0);
      // Release at the original value — setQuality's own `if (==) return`
      // short-circuits so nothing changes.
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(80.0);
      await tester.pumpAndSettle();

      expect(container.read(exportControllerProvider).quality, 80);
      expect(find.text('80%'), findsOneWidget);
    },
  );
}
