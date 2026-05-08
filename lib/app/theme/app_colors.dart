import 'package:flutter/material.dart';

/// MD3 color tokens lifted from the UI design source
/// `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_1_首页/code.html`.
///
/// These are the raw light-mode palette values; the [ColorScheme] is
/// constructed from them in [AppTheme]. Dark-mode is generated via
/// [ColorScheme.fromSeed] using [primary] as the seed.
class AppColors {
  AppColors._();

  // Primary
  static const Color primary = Color(0xFF4F378A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF6750A4);
  static const Color onPrimaryContainer = Color(0xFFE0D2FF);

  // Secondary
  static const Color secondary = Color(0xFF625B71);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFE8DEF9);
  static const Color onSecondaryContainer = Color(0xFF686177);

  // Tertiary
  static const Color tertiary = Color(0xFF633B48);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF7D5260);
  static const Color onTertiaryContainer = Color(0xFFFFCBDA);

  // Error
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // Background / surface
  static const Color background = Color(0xFFFEF7FF);
  static const Color onBackground = Color(0xFF1D1A22);
  static const Color surface = Color(0xFFFEF7FF);
  static const Color onSurface = Color(0xFF1D1A22);
  static const Color onSurfaceVariant = Color(0xFF494551);
  static const Color surfaceVariant = Color(0xFFE7E0EB);

  // Surface containers
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF9F1FD);
  static const Color surfaceContainer = Color(0xFFF3EBF7);
  static const Color surfaceContainerHigh = Color(0xFFEDE6F1);
  static const Color surfaceContainerHighest = Color(0xFFE7E0EB);
  static const Color surfaceDim = Color(0xFFDFD7E3);
  static const Color surfaceBright = Color(0xFFFEF7FF);

  // Outline
  static const Color outline = Color(0xFF7A7582);
  static const Color outlineVariant = Color(0xFFCBC4D2);

  // Inverse
  static const Color inverseSurface = Color(0xFF322F37);
  static const Color inverseOnSurface = Color(0xFFF6EEFA);
  static const Color inversePrimary = Color(0xFFCFBCFF);
}
