import 'package:flutter/material.dart';

/// CoStudy design tokens.
///
/// Only the values the auth screens actually use are defined here. The rest of
/// the palette arrives with the screens that need it.
abstract final class AppColors {
  static const blue = Color(0xFF3B6FFF);
  static const blueDark = Color(0xFF2A50E0);
  static const blueLight = Color(0xFFEEF2FF);

  /// RESERVED for the "Coalition Found" moment and nowhere else. It is the one
  /// bright colour in the app, so that when it appears it means "it worked".
  /// Not used on these screens — listed so nobody reaches for it by accident.
  static const yellow = Color(0xFFFFD23F);

  static const offWhite = Color(0xFFFAF8F3);
  static const white = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF1A1A2E);
  static const charcoalMid = Color(0xFF3D3D5C);
  static const gray = Color(0xFFE8E6E1);
  static const grayMid = Color(0xFF9291A5);
  static const green = Color(0xFF2DD4A0);
  static const greenLight = Color(0xFFECFDF5);
  static const red = Color(0xFFFF4D6D);
}

abstract final class AppRadius {
  static const button = 14.0;
  static const card = 18.0;
  static const sheet = 24.0;
}

/// Minimum touch target, per the design brief and WCAG.
const double kMinTouchTarget = 48.0;

ThemeData buildCoStudyTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blue,
    surface: AppColors.offWhite,
    error: AppColors.red,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.offWhite,
    useMaterial3: true,
    // Plus Jakarta Sans is the display face in the design. Bundling the font
    // is a separate change; until then the platform default keeps the layout
    // honest rather than silently substituting something that only looks close.
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.charcoal,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: AppColors.charcoalMid,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: AppColors.charcoalMid,
        height: 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.gray,
        disabledForegroundColor: AppColors.grayMid,
        minimumSize: const Size.fromHeight(kMinTouchTarget + 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size.fromHeight(kMinTouchTarget),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      hintStyle: const TextStyle(color: AppColors.grayMid),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.gray),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.gray),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.red, width: 2),
      ),
    ),
  );
}
