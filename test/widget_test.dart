// Smoke test for the application root.
//
// Verifies the home screen renders the greeting and feature cards described
// in the base architecture PRD. Real feature behaviour is tested per-feature.

import 'package:fl_picraft/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen shows greeting and feature cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AppRoot()));
    await tester.pumpAndSettle();

    expect(find.text('你好，创作者'), findsOneWidget);
    expect(find.text('长图拼接'), findsWidgets);
    expect(find.text('宫格切图'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
