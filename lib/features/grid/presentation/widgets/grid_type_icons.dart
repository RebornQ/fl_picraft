import 'package:flutter/material.dart';

import '../../domain/entities/grid_type.dart';

/// UI-only metadata: which Material icon represents a given [GridType].
///
/// Lives in `presentation/` so the domain entity stays Flutter-free
/// (per `.trellis/spec/frontend/directory-structure.md` and
/// `cross-layer-thinking-guide.md` "Mistake 3: Leaky Abstractions").
/// The icons mirror the design mock's material symbols
/// (`view_agenda`, `view_day`, `view_column`, `grid_view`,
/// `dashboard`, `apps`, `calendar_view_month`) from
/// `_3_宫格切图/code.html` lines 158–201.
extension GridTypeIcon on GridType {
  IconData get icon {
    switch (this) {
      case GridType.g1x2:
        return Icons.view_agenda_outlined;
      case GridType.g2x1:
        return Icons.view_week_outlined;
      case GridType.g1x3:
        return Icons.view_day_outlined;
      case GridType.g3x1:
        return Icons.view_column_outlined;
      case GridType.g1x4:
        return Icons.view_stream_outlined;
      case GridType.g4x1:
        return Icons.view_column_outlined;
      case GridType.g2x2:
        return Icons.grid_view_outlined;
      case GridType.g2x3:
        return Icons.dashboard_outlined;
      case GridType.g3x2:
        return Icons.dashboard_outlined;
      case GridType.g3x3:
        return Icons.apps_outlined;
      case GridType.g4x4:
        return Icons.calendar_view_month_outlined;
    }
  }
}
