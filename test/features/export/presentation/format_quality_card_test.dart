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
}
