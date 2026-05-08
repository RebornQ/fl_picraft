import 'package:fl_picraft/features/long_stitch/domain/entities/stitch_mode.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_mode_segmented.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders both Chinese mode labels', (tester) async {
    await tester.pumpWidget(
      wrap(StitchModeSegmented(value: StitchMode.vertical, onChanged: (_) {})),
    );

    expect(find.text('竖向'), findsOneWidget);
    expect(find.text('横向'), findsOneWidget);
  });

  testWidgets('tapping the inactive segment fires onChanged with that mode', (
    tester,
  ) async {
    StitchMode? lastValue;

    await tester.pumpWidget(
      wrap(
        StitchModeSegmented(
          value: StitchMode.vertical,
          onChanged: (mode) => lastValue = mode,
        ),
      ),
    );

    await tester.tap(find.text('横向'));
    await tester.pumpAndSettle();

    expect(lastValue, StitchMode.horizontal);
  });

  testWidgets('tapping the already-active segment still emits the same value '
      '(parent decides whether to ignore)', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      wrap(
        StitchModeSegmented(
          value: StitchMode.vertical,
          onChanged: (_) => calls++,
        ),
      ),
    );

    await tester.tap(find.text('竖向'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
