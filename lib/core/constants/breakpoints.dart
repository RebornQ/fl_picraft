import 'package:flutter/widgets.dart';

/// Material 3 Window Size Class breakpoints in logical pixels (dp).
///
/// Sourced from
/// <https://m3.material.io/foundations/layout/applying-layout/window-size-classes>.
/// Use [windowSizeClassOf] for a typed switch and [maxContentWidth] to
/// cap content on very wide windows.
class Breakpoints {
  Breakpoints._();

  /// Boundary between **compact** (phone portrait) and **medium**
  /// (phone landscape / small tablet). Window widths strictly less than
  /// this value are treated as compact.
  static const double compact = 600;

  /// Boundary between **medium** and **expanded** (large tablet /
  /// small desktop).
  static const double medium = 840;

  /// Boundary between **expanded** and **large** (full desktop).
  static const double expanded = 1200;

  /// Cap on the rendered content width for every top-level screen.
  /// Beyond this, padding/center grows so cards do not stretch to
  /// fill 27-inch monitors.
  static const double maxContentWidth = 1200;
}

/// Window size buckets paired with [Breakpoints].
///
/// Use [windowSizeClassOf] to derive the active bucket from a
/// [BuildContext]; consumers then `switch` on the enum which gives the
/// compiler exhaustive checks when a new bucket is added later.
enum WindowSizeClass {
  /// `< 600 dp`. Phone portrait. Default in mobile orientation.
  compact,

  /// `[600, 840) dp`. Phone landscape or small tablet portrait.
  medium,

  /// `[840, 1200) dp`. Large tablet or small desktop window.
  expanded,

  /// `>= 1200 dp`. Full desktop window. Content should be capped at
  /// [Breakpoints.maxContentWidth].
  large,
}

/// Resolves the [WindowSizeClass] of the nearest [MediaQuery] in
/// [context].
///
/// Prefer this over reading [MediaQuery.sizeOf] directly so layout
/// branches are expressed as an exhaustive enum switch and stay aligned
/// with the Material 3 specification.
WindowSizeClass windowSizeClassOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return windowSizeClassFromWidth(width);
}

/// Pure-Dart variant of [windowSizeClassOf] for tests / callers that
/// already have the width in hand (avoids constructing a fake
/// [BuildContext]).
WindowSizeClass windowSizeClassFromWidth(double width) {
  if (width < Breakpoints.compact) return WindowSizeClass.compact;
  if (width < Breakpoints.medium) return WindowSizeClass.medium;
  if (width < Breakpoints.expanded) return WindowSizeClass.expanded;
  return WindowSizeClass.large;
}
