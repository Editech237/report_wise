import 'package:flutter/material.dart';

/// ReportWise brand palette - Cameroon secondary school identity.
/// Keeps the existing green palette (0xFF0B5D3B) as primary but
/// exposes the refined neutrals from the reference design system.
class AppColors {
  // Keep existing palette - user confirmed "current palette is okay"
  static const primary = Color(0xFF0B5D3B);
  static const primaryDark = Color(0xFF083D28);
  static const primaryContainer = Color(0xFF0F7A4A);
  static const secondary = Color(0xFF00639A);
  static const secondaryDim = Color(0xFF96CCFF);

  // Accents kept for status chips - adapted for green primary
  static const accentGreen = Color(0xFF1B5E20);
  static const accentGreenLight = Color(0xFFE8F5E9);
  static const accentAmber = Color(0xFFF57F17);
  static const accentAmberLight = Color(0xFFFFF8E1);
  static const accentRed = Color(0xFFB71C1C);
  static const accentRedLight = Color(0xFFFFEBEE);

  // Surfaces - from reference design (clean, modern dashboard)
  static const background = Color(0xFFFAF8FF);
  static const surfaceLow = Color(0xFFF3F3FB);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF1B1B1F);
  static const onSurfaceVariant = Color(0xFF44474E);

  // Borders
  static const border = Color(0xFFE8E8F0);
  static const divider = Color(0xFFE8E8F0);
}
