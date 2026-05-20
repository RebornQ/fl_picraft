import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stitch_controls_panel.dart';

/// Bottom-sticky parameter sheet matching the design mock
/// (`_2_长图拼接/code.html` lines ~196–260).
///
/// Thin presentational wrapper around [StitchControlsPanel]: adds a
/// top-rounded Material elevation so the controls feel like a sheet
/// docked to the bottom of the editor. The actual controls (mode
/// segmented, subtitle toggle, sliders, color swatches) live in the
/// panel widget so the expanded / large screen widths can dock the
/// same panel against the right edge of the canvas — see
/// `stitch_editor_screen.dart` for the responsive switch.
///
/// The sheet caps its own height at `min(screenHeight * 0.22, 320)` (with a
/// 200 dp floor for very short windows) and wraps the panel in a
/// [SingleChildScrollView] so the sheet itself never grows past the cap
/// while every control stays reachable through scrolling. This frees up
/// visual area for the preview canvas on compact / medium widths — the
/// expanded / large path already wraps the panel in its own
/// [SingleChildScrollView] (see `stitch_editor_screen.dart`) so the
/// scroll behavior is consistent across size classes.
class StitchControlsSheet extends StatelessWidget {
  const StitchControlsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Reading screen height through MediaQuery is correct here — the
    // sheet sits at the bottom of the scaffold body, so the screen
    // height (minus app bar + bottom nav) is the right basis for the
    // cap. A LayoutBuilder wouldn't see screen height because the
    // sheet's parent column doesn't pass it down as constraints.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(200.0, math.min(screenHeight * 0.22, 320.0));
    return Material(
      elevation: 8,
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 80),
          child: StitchControlsPanel(),
        ),
      ),
    );
  }
}
