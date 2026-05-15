import 'package:fl_picraft/features/export/presentation/screens/export_screen.dart';
import 'package:fl_picraft/features/export/presentation/widgets/format_quality_card.dart';
import 'package:fl_picraft/features/export/presentation/widgets/save_action_button.dart';
import 'package:fl_picraft/features/export/presentation/widgets/save_disclaimer.dart';
import 'package:fl_picraft/features/export/presentation/widgets/watermark_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _exportHarness({required Size size}) {
  final router = GoRouter(
    initialLocation: '/export',
    routes: [
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/stitch', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/grid', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  group('ExportScreen responsive layout', () {
    testWidgets(
      'compact (< 600 dp) stacks FormatQuality and Watermark vertically',
      (tester) async {
        await tester.pumpWidget(_exportHarness(size: const Size(400, 800)));
        await tester.pumpAndSettle();

        // All settings widgets present.
        expect(find.byType(FormatQualityCard), findsOneWidget);
        expect(find.byType(WatermarkCard), findsOneWidget);
        expect(find.byType(SaveActionButton), findsOneWidget);
        expect(find.byType(SaveDisclaimer), findsOneWidget);

        // FormatQuality and Watermark share the same left edge ⇒ stacked.
        final format = tester.getTopLeft(find.byType(FormatQualityCard));
        final watermark = tester.getTopLeft(find.byType(WatermarkCard));
        expect(format.dx, watermark.dx);
        expect(watermark.dy, greaterThan(format.dy));
      },
    );

    testWidgets(
      'medium (>= 600 dp) lays FormatQuality and Watermark side-by-side',
      (tester) async {
        await tester.pumpWidget(_exportHarness(size: const Size(720, 1024)));
        await tester.pumpAndSettle();

        expect(find.byType(FormatQualityCard), findsOneWidget);
        expect(find.byType(WatermarkCard), findsOneWidget);

        final format = tester.getTopLeft(find.byType(FormatQualityCard));
        final watermark = tester.getTopLeft(find.byType(WatermarkCard));
        // Side-by-side ⇒ same top edge, different left edges.
        expect(format.dy, watermark.dy);
        expect(watermark.dx, greaterThan(format.dx));
      },
    );

    testWidgets('expanded (>= 840 dp) keeps the two-column settings row', (
      tester,
    ) async {
      await tester.pumpWidget(_exportHarness(size: const Size(1024, 800)));
      await tester.pumpAndSettle();

      final format = tester.getTopLeft(find.byType(FormatQualityCard));
      final watermark = tester.getTopLeft(find.byType(WatermarkCard));
      expect(format.dy, watermark.dy);
      expect(watermark.dx, greaterThan(format.dx));
    });

    testWidgets('SaveActionButton stays full-width on every size class', (
      tester,
    ) async {
      // Verify Save button width is more than half the screen width
      // (i.e., it spans the whole settings column, not just one of the
      // two settings cards) on a medium viewport.
      await tester.pumpWidget(_exportHarness(size: const Size(720, 1024)));
      await tester.pumpAndSettle();

      final saveBox = tester.renderObject<RenderBox>(
        find.byType(SaveActionButton),
      );
      final formatBox = tester.renderObject<RenderBox>(
        find.byType(FormatQualityCard),
      );
      // Save button is wider than a single setting card on medium+.
      expect(saveBox.size.width, greaterThan(formatBox.size.width));
    });

    testWidgets('content is capped by maxContentWidth on very wide windows', (
      tester,
    ) async {
      await tester.pumpWidget(_exportHarness(size: const Size(2400, 1080)));
      await tester.pumpAndSettle();

      final scrollViewBox = tester.renderObject<RenderBox>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollViewBox.size.width, lessThanOrEqualTo(1200));
    });
  });
}
