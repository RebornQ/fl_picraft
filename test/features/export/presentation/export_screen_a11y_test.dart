import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/export/presentation/screens/export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/export',
    routes: [
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

void main() {
  group('ExportScreen accessibility', () {
    testWidgets('meets Android tap target guideline (48×48 dp)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('meets iOS tap target guideline (44×44 pt)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('meets text-contrast guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('meets labeled-tappable-node guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
