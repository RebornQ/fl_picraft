import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_info.dart';

/// Formats the version label surfaced on the About screen + License page
/// header.
///
/// - `pubspec` `1.0.0+1` → `'v1.0.0（build 1）'`
/// - Web / platforms where `buildNumber` is empty → `'v1.0.0'`
///
/// Uses full-width parentheses + the literal word "build" so the label
/// reads naturally next to the surrounding zh-CN AppBar / ListTile copy.
String formatAppVersion(PackageInfo info) {
  final version = info.version;
  final buildNumber = info.buildNumber;
  return buildNumber.isEmpty ? 'v$version' : 'v$version（build $buildNumber）';
}

/// Strips the `https://` (or `http://`) protocol prefix from a URL for
/// display as a ListTile subtitle. Lets the URL stay scannable without
/// drawing the user's eye to the scheme.
String _stripProtocol(String url) {
  return url.replaceFirst(RegExp(r'^https?://'), '');
}

/// "关于" 屏 — surfaces the app icon, name, description, version, and
/// shortcuts to project source, issues feed, and aggregated open-source
/// license list.
///
/// Reached via `context.push('/settings/about')` from
/// [`SettingsScreen`]. Lives in its own `features/about/` feature
/// (not under `settings/`) so the About surface can be reached from
/// other future entry points (e.g. a home-screen info icon) without
/// crossing feature boundaries — see this task's PRD §D1.
///
/// Stateful: holds a cached `Future<PackageInfo>` so the version label
/// doesn't refetch on every rebuild. PRD §D5.1 explicitly opts for
/// `FutureBuilder` over a Riverpod provider because the read is one-shot
/// and isolated to this screen.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      // Top-level screens fill the container width per
      // `.trellis/spec/frontend/responsive-layout.md` — the maxWidth
      // cap below is applied INSIDE the SafeArea on the main content
      // column only, leaving the Scaffold body itself unbounded.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              children: [
                _AppIdentitySection(packageInfoFuture: _packageInfoFuture),
                const SizedBox(height: 24),
                _AboutActionsCard(onLicenseTap: _onLicenseTap),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onLicenseTap() async {
    final info = await _packageInfoFuture;
    if (!mounted) return;
    showLicensePage(
      context: context,
      applicationName: AppInfo.name,
      applicationVersion: formatAppVersion(info),
      applicationIcon: Image.asset(
        AppInfo.iconAssetPath,
        width: 64,
        height: 64,
      ),
    );
  }
}

/// Top of the About screen — app icon, name, description, version.
///
/// Extracted into its own widget so the version FutureBuilder doesn't
/// rebuild the entire screen each frame the future resolves.
class _AppIdentitySection extends StatelessWidget {
  const _AppIdentitySection({required this.packageInfoFuture});

  final Future<PackageInfo> packageInfoFuture;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Source webp is already alpha-baked into the launcher rounded
        // shape — no ClipRRect needed (see PRD §D4).
        Image.asset(AppInfo.iconAssetPath, width: 112, height: 112),
        const SizedBox(height: 12),
        Text(
          AppInfo.name,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppInfo.description,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<PackageInfo>(
          future: packageInfoFuture,
          builder: (context, snapshot) {
            final label = snapshot.hasData
                ? formatAppVersion(snapshot.data!)
                : 'v…';
            return Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Card that bundles the three About actions (project source, issues,
/// license). Ordering follows PRD §D3.4: identity → feedback → legal.
class _AboutActionsCard extends StatelessWidget {
  const _AboutActionsCard({required this.onLicenseTap});

  final VoidCallback onLicenseTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('项目源码'),
            subtitle: Text(_stripProtocol(AppInfo.gitHubRepoUrl)),
            onTap: () => _launchExternal(context, AppInfo.gitHubRepoUrl),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('问题反馈'),
            subtitle: Text(_stripProtocol(AppInfo.gitHubIssuesUrl)),
            onTap: () => _launchExternal(context, AppInfo.gitHubIssuesUrl),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('开源许可'),
            onTap: onLicenseTap,
          ),
        ],
      ),
    );
  }
}

/// Opens [url] in the user's default external browser. Shows a zh-CN
/// SnackBar fallback when the platform reports the URL is unlaunchable
/// or [launchUrl] throws (offline, no browser registered, sandboxed
/// platform, etc.).
///
/// Uses [LaunchMode.externalApplication] explicitly to avoid in-app
/// webview surfaces that interrupt the user's browsing context — see
/// PRD §D7.
Future<void> _launchExternal(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.parse(url);
  try {
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      _showLaunchFailureSnackBar(messenger, url);
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showLaunchFailureSnackBar(messenger, url);
    }
  } catch (_) {
    _showLaunchFailureSnackBar(messenger, url);
  }
}

void _showLaunchFailureSnackBar(ScaffoldMessengerState messenger, String url) {
  messenger.showSnackBar(SnackBar(content: Text('无法打开链接，请检查网络或手动访问：$url')));
}
