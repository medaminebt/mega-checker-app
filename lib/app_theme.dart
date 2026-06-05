import 'package:flutter/material.dart';

/// Centralised design system, FlutterFlow-style: named color tokens, a type
/// scale, and standardized shapes for buttons / cards / fields. Change a value
/// here and it updates everywhere.
class AppTheme {
  // ---- Brand colors ------------------------------------------------------
  static const Color primary = Color(0xFF4F46E5); // indigo
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color secondary = Color(0xFF7C3AED); // violet
  static const Color tertiary = Color(0xFF06B6D4); // cyan

  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);

  // ---- Surfaces & text ---------------------------------------------------
  static const Color primaryBackground = Color(0xFFF1F4F9);
  static const Color secondaryBackground = Color(0xFFFFFFFF);
  static const Color alternate = Color(0xFFE5E7EB); // borders / dividers
  static const Color primaryText = Color(0xFF14181B);
  static const Color secondaryText = Color(0xFF64748B);

  // ---- Shape tokens ------------------------------------------------------
  static const double buttonRadius = 12;
  static const double cardRadius = 16;
  static const double fieldRadius = 10;

  // ---- Type scale --------------------------------------------------------
  static const String _font = '.AppleSystemUIFont';
  static const TextStyle titleLarge = TextStyle(
      fontFamily: _font,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: primaryText);
  static const TextStyle titleMedium = TextStyle(
      fontFamily: _font,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: primaryText);
  static const TextStyle bodyMedium = TextStyle(
      fontFamily: _font, fontSize: 14, color: primaryText);
  static const TextStyle bodySmall = TextStyle(
      fontFamily: _font, fontSize: 12.5, color: secondaryText);
  static const TextStyle labelSmall = TextStyle(
      fontFamily: _font,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: secondaryText);
  static const TextStyle mono =
      TextStyle(fontFamily: 'Menlo', fontSize: 13, color: primaryText);

  // ---- ThemeData ---------------------------------------------------------
  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      error: error,
    );
    OutlineInputBorder fieldBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      fontFamily: _font,
      scaffoldBackgroundColor: primaryBackground,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: secondaryBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: alternate),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(
              fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(buttonRadius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          textStyle: const TextStyle(
              fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          side: BorderSide(color: primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(buttonRadius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: fieldBorder(alternate),
        enabledBorder: fieldBorder(Colors.transparent),
        focusedBorder: fieldBorder(primary, 1.5),
        hintStyle: const TextStyle(color: secondaryText, fontSize: 13),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
