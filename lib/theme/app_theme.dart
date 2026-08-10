import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CoStudy design tokens, ported from the Figma prototype
/// (CoStudy Phase 1 Design). Values are the exact constants from the
/// prototype's `C` object — not approximations.
abstract final class AppColors {
  static const blue = Color(0xFF3B6FFF);
  static const blueDark = Color(0xFF2A50E0);
  static const blueLight = Color(0xFFEEF2FF);

  /// ── THE ONE COLOUR RULE ────────────────────────────────────────────────
  /// Yellow appears ONLY on the Coalition Found moment — the instant a
  /// session is confirmed. Nowhere else in the app: not on buttons, tabs,
  /// badges, or decoration. It is the single bright colour, so when it
  /// appears it means "it worked".
  ///
  /// The one exception is the mascot's yellow blob, which is the character
  /// itself rather than UI chrome.
  ///
  /// Coalition Found is Phase 4. Nothing in this build may use these.
  static const yellow = Color(0xFFFFD23F);
  static const yellowDark = Color(0xFFE6B800);

  static const lavender = Color(0xFFC4B5FD);
  static const lavenderLight = Color(0xFFF0EBFF);

  static const offWhite = Color(0xFFFAF8F3);
  static const white = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF1A1A2E);
  static const charcoalMid = Color(0xFF3D3D5C);
  static const gray = Color(0xFFE8E6E1);
  static const grayMid = Color(0xFF9291A5);
  static const green = Color(0xFF2DD4A0);
  static const greenLight = Color(0xFFECFDF5);
  static const greenDeep = Color(0xFF1A6B4A);
  static const red = Color(0xFFFF4D6D);
  static const redLight = Color(0xFFFFE8EC);

  /// Hairline between rows inside a card — warmer than [gray].
  static const hairline = Color(0xFFF0EEE8);
}

/// Corner radii from the design brief: 14 buttons, 18 cards, 24 sheets.
/// The prototype also uses a few larger radii for hero surfaces.
abstract final class AppRadius {
  static const button = 14.0;
  static const card = 18.0;
  static const sheet = 24.0;
  static const cardLarge = 20.0;
  static const hero = 26.0;
  static const pill = 999.0;
}

/// Minimum touch target, per the design brief and WCAG.
const double kMinTouchTarget = 48.0;

/// Display face. Plus Jakarta Sans across the interface.
///
/// Served through google_fonts, which fetches once and caches to disk. That
/// is a deliberate tradeoff: no font binaries in the repo, but the very first
/// launch on a device with no network falls back to the platform face. For an
/// offline demo the fonts should be bundled as assets instead — see the note
/// in the commit message.
TextStyle display({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = AppColors.charcoal,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// Mono face. DM Mono, reserved for times, counts, and session codes — never
/// for body copy. Keeps digits from jittering as they change.
TextStyle mono({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.grayMid,
  double? letterSpacing,
}) {
  return GoogleFonts.dmMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

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
    textTheme: GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: AppColors.charcoalMid,
      displayColor: AppColors.charcoal,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.offWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.charcoal,
      titleTextStyle: display(size: 20, weight: FontWeight.w800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.gray,
        disabledForegroundColor: AppColors.grayMid,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size(0, kMinTouchTarget),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.charcoal,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: AppColors.grayMid,
      ),
      border: _inputBorder(AppColors.gray),
      enabledBorder: _inputBorder(AppColors.gray),
      focusedBorder: _inputBorder(AppColors.blue, width: 2),
      errorBorder: _inputBorder(AppColors.red, width: 2),
      focusedErrorBorder: _inputBorder(AppColors.red, width: 2),
      errorStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: AppColors.red,
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// The standard white card: 1.5px warm-grey border, 20px radius, no shadow.
/// Used for every grouped surface in the prototype.
BoxDecoration cardDecoration({Color? color, Color? border, double? radius}) {
  return BoxDecoration(
    color: color ?? AppColors.white,
    borderRadius: BorderRadius.circular(radius ?? AppRadius.cardLarge),
    border: Border.all(color: border ?? AppColors.gray, width: 1.5),
  );
}
