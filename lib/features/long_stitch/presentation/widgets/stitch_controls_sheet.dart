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
class StitchControlsSheet extends StatelessWidget {
  const StitchControlsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: const StitchControlsPanel(),
    );
  }
}
