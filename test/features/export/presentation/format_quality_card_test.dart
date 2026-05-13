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

  testWidgets('renders both format buttons + the quality slider initially', (
    tester,
  ) async {
    await tester.pumpWidget(pumpHarness());

    expect(find.text('JPG'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    // Initial state is JPG → quality slider must be visible.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('最小体积'), findsOneWidget);
    expect(find.text('最高质量'), findsOneWidget);
  });

  testWidgets('selecting PNG hides the quality slider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));
    expect(find.byType(Slider), findsOneWidget);

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.png);
    await tester.pumpAndSettle();

    // Quality slider is now hidden — PNG is lossless.
    expect(find.byType(Slider), findsNothing);
    expect(find.text('85%'), findsNothing);
    expect(find.text('最小体积'), findsNothing);
  });

  testWidgets('switching back to JPG re-renders the slider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.png);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);

    container
        .read(exportControllerProvider.notifier)
        .setFormat(ExportFormat.jpg);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('tapping the PNG button updates the controller', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));
    expect(container.read(exportControllerProvider).format, ExportFormat.jpg);

    await tester.tap(find.text('PNG'));
    await tester.pumpAndSettle();

    expect(container.read(exportControllerProvider).format, ExportFormat.png);
  });

  testWidgets('quality slider reflects controller state', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpHarness(container: container));

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
