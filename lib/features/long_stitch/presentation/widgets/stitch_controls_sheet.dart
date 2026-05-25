import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stitch_controls_panel.dart';

/// Bottom-sticky parameter sheet matching the design mock
/// (`_2_长图拼接/code.html` lines ~196–260).
///
/// Thin presentational wrapper around [StitchControlsPanel]: adds a
/// top-rounded Material elevation so the controls feel like a sheet
/// docked to the bottom of the editor. The actual controls (TabBar +
/// 4-Tab content) live in the panel widget so the expanded / large
/// screen widths can dock the same panel against the right edge of the
/// canvas — see `stitch_editor_screen.dart` for the responsive switch.
///
/// The sheet caps its own height at `max(260, min(screenHeight * 0.30,
/// 400))` — bumped from the legacy `200~320` cap to accommodate the
/// TabBar header (~48 dp) plus the tallest tab body (≤ 224 dp) added
/// by `05-26-long-stitch-toolbar-tab-redesign`. The cap still floats
/// on the actual viewport so foldable outer screens (~ 400 dp tall)
/// land on the floor while phones / tablets get a proportional sheet.
/// The panel is wrapped in [SingleChildScrollView] so any tab body
/// taller than the slot still scrolls cleanly.
class StitchControlsSheet extends StatelessWidget {
  const StitchControlsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(260.0, math.min(screenHeight * 0.30, 400.0));
    return Material(
      elevation: 8,
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 16),
          child: StitchControlsPanel(),
        ),
      ),
    );
  }
}
