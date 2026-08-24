import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static const primary = AppColors.primary;
  static const primaryContainer = AppColors.primaryContainer;
  static const secondary = AppColors.secondary;
  static const accentGreen = AppColors.accentGreen;
  static const accentGreenLight = AppColors.accentGreenLight;
  static const accentAmber = AppColors.accentAmber;
  static const accentAmberLight = AppColors.accentAmberLight;
  static const accentRed = AppColors.accentRed;
  static const accentRedLight = AppColors.accentRedLight;

  static const surface = AppColors.background;
  static const surfaceLow = AppColors.surfaceLow;
  static const surfaceLowest = AppColors.surfaceLowest;
  static const onSurface = AppColors.onSurface;
  static const onSurfaceVariant = AppColors.onSurfaceVariant;

  static ThemeData get lightTheme {
    // Use Manrope + Lexend if available, fallback to system if not bundled
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primaryContainer,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryDim,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outlineVariant: const Color(0xFFC4C6D0).withOpacity(0.15),
      ),
      scaffoldBackgroundColor: surfaceLow,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 57,
          fontWeight: FontWeight.bold,
          color: onSurface,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 45,
          fontWeight: FontWeight.bold,
          color: onSurface,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(fontFamily: 'Lexend', fontSize: 16, color: onSurfaceVariant),
        bodyMedium: TextStyle(fontFamily: 'Lexend', fontSize: 14, color: onSurfaceVariant),
        labelSmall: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFE1E2EC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: BorderSide(color: primary.withOpacity(0.40), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: const BorderSide(color: accentRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        hintStyle: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 13,
          color: onSurfaceVariant.withOpacity(0.55),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: primary,
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(color: Colors.white),
        selectedLabelTextStyle: const TextStyle(
          fontFamily: 'Lexend',
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Lexend',
          color: Colors.white.withOpacity(0.8),
          fontSize: 12,
        ),
        indicatorColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    );
  }
}
