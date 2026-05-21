import 'package:fl_picraft/core/constants/app_info.dart';
import 'package:fl_picraft/features/about/presentation/screens/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Builds a minimal harness around [AboutScreen] so widget queries
/// resolve without dragging in the full router / Riverpod scope.
Widget _harness() {
  return const MaterialApp(home: AboutScreen());
}

void main() {
  group('formatAppVersion', () {
    test('includes full-width parens + "build" when buildNumber present', () {
      final info = _packageInfo(version: '1.2.3', buildNumber: '7');
      expect(formatAppVersion(info), 'v1.2.3（build 7）');
    });

    test('omits parens entirely when buildNumber is empty', () {
      final info = _packageInfo(version: '1.0.0', buildNumber: '');
      expect(formatAppVersion(info), 'v1.0.0');
    });
  });

  group('AboutScreen', () {
    setUp(() {
      // `package_info_plus` ships a mock channel — seed it BEFORE
      // pumping the widget so the FutureBuilder resolves to a known
      // value instead of throwing `MissingPluginException` under
      // `flutter test`.
      PackageInfo.setMockInitialValues(
        appName: 'Fl PiCraft',
        packageName: 'com.example.fl_picraft',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
        installerStore: '',
      );
    });

    testWidgets('renders AppBar title "关于"', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // Two "关于" strings on the page in principle (AppBar + body), so
      // pin to the AppBar via its widget type.
      final appBarTitle = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('关于'),
      );
      expect(appBarTitle, findsOneWidget);
    });

    testWidgets('shows app name + description from AppInfo', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text(AppInfo.name), findsOneWidget);
      expect(find.text(AppInfo.description), findsOneWidget);
    });

    testWidgets('shows mocked version label "v1.0.0（build 1）"', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('v1.0.0（build 1）'), findsOneWidget);
    });

    testWidgets('lists three action tiles in order: 项目源码 / 问题反馈 / 开源许可', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // All three titles present.
      expect(find.text('项目源码'), findsOneWidget);
      expect(find.text('问题反馈'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);

      // Order check via vertical offset — earlier tiles have a smaller
      // dy than later tiles.
      final sourceY = tester.getTopLeft(find.text('项目源码')).dy;
      final issuesY = tester.getTopLeft(find.text('问题反馈')).dy;
      final licenseY = tester.getTopLeft(find.text('开源许可')).dy;
      expect(sourceY, lessThan(issuesY));
      expect(issuesY, lessThan(licenseY));
    });

    testWidgets('source + issues subtitles strip https:// prefix', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('github.com/RebornQ/fl_picraft'), findsOneWidget);
      expect(find.text('github.com/RebornQ/fl_picraft/issues'), findsOneWidget);
      // Neither subtitle should leak the protocol.
      expect(find.text(AppInfo.gitHubRepoUrl), findsNothing);
      expect(find.text(AppInfo.gitHubIssuesUrl), findsNothing);
    });

    testWidgets('open-source license tile has no subtitle', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      final licenseTile = find.ancestor(
        of: find.text('开源许可'),
        matching: find.byType(ListTile),
      );
      expect(licenseTile, findsOneWidget);
      // ListTile.subtitle should be null on the license entry.
      final widget = tester.widget<ListTile>(licenseTile);
      expect(widget.subtitle, isNull);
    });

    testWidgets('uses leading icons specified in PRD §D3.3', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // Each leading icon should appear exactly once across the three
      // action tiles.
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });
  });

  group('AboutScreen — version label fallback', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Fl PiCraft',
        packageName: 'com.example.fl_picraft',
        version: '2.0.0',
        buildNumber: '',
        buildSignature: '',
        installerStore: '',
      );
    });

    testWidgets('renders "v{version}" when buildNumber is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('v2.0.0'), findsOneWidget);
    });
  });
}

PackageInfo _packageInfo({
  required String version,
  required String buildNumber,
}) {
  return PackageInfo(
    appName: 'Fl PiCraft',
    packageName: 'com.example.fl_picraft',
    version: version,
    buildNumber: buildNumber,
    buildSignature: '',
    installerStore: '',
  );
}
