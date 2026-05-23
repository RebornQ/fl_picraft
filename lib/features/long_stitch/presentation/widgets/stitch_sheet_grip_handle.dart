import 'package:flutter/material.dart';

/// Small grip-handle visual at the top of a bottom sheet body.
///
/// Used by the long-stitch compact-mode sheets
/// ([showStitchAddActionSheet], [showStitchImageSheet],
/// [showStitchParamsSheet]) so all three share the same visual rhythm
/// at the top of their body — a 4 dp tall, 40 dp wide rounded pill in
/// `colorScheme.outlineVariant`, centered horizontally with 12 dp
/// vertical padding.
///
/// This is the **decorative grip** we hand-paint inside the sheet
/// body itself. We don't rely on `showModalBottomSheet`'s
/// `showDragHandle: true` because some sheets use a custom
/// `backgroundColor: Colors.transparent` + inner `Material` (e.g.
/// the params sheet's `DraggableScrollableSheet` form) which doesn't
/// surface the SDK-supplied drag handle reliably across the sheets.
/// Painting the grip ourselves keeps the three sheets visually
/// consistent regardless of which sheet shape is in use.
class StitchSheetGripHandle extends StatelessWidget {
  const StitchSheetGripHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
