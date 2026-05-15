import 'package:fl_picraft/app/theme/app_theme.dart';
import 'package:fl_picraft/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Wraps the home screen so the [SemanticsTester] / `meetsGuideline`
/// matchers can run against the full a11y tree without the
/// `MaterialApp` chrome (which would otherwise add unrelated nodes
/// like the system status bar that pollute the assertions).
Widget _harness() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

void main() {
  group('HomeScreen accessibility', () {
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
