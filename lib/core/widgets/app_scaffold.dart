import 'package:flutter/material.dart';

import 'bottom_nav_bar.dart';

/// Wraps a screen body with the shared [AppBottomNavBar].
///
/// Used by every top-level route so that the navigation chrome is consistent
/// without coupling individual screens to GoRouter shell internals.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(child: child),
      bottomNavigationBar: const AppBottomNavBar(),
      floatingActionButton: floatingActionButton,
    );
  }
}
