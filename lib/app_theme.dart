import 'package:flutter/material.dart';

/// MEGA design system — the tokens from the "MEGA — UX/UI Color System &
/// Theme" sheet, dark theme (MEGA's default experience). Change a value here
/// and it updates everywhere.
class AppTheme {
  // ---- Brand ---------------------------------------------------------------
  static const Color megaRed = Color(0xFFD9272E); // --brand-primary
  static const Color megaRedHover = Color(0xFFC22026);
  static const Color megaRedAlt = Color(0xFFDD1405); // Monza red
  static const Color megaBlue = Color(0xFF3F42C3); // --brand-secondary
  static const Color megaBlueSoft = Color(0xFF9DA0F5); // blue text on dark
  static const Color ashGrey = Color(0xFFA6A6AF);

  // ---- Dark theme tokens ---------------------------------------------------
  static const Color bgBase = Color(0xFF000000); // canvas
  static const Color bgSurface = Color(0xFF1B1B1B); // cards, panels, modals
  static const Color bgElevated = Color(0xFF242F47); // tooltips, raised
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA6A6AF);
  static const Color textMuted = Color(0xFF6B6B75);
  static const Color textInverse = Color(0xFF000000);
  static const Color borderSubtle = Color(0xFF374151); // input outlines
  static const Color hairline = Color(0xFF2A2A2A); // dividers on surfaces
  static const Color stateHover = Color(0xFF2A2A2A);
  static const Color stateFocus = megaBlue;

  // ---- Status (semantic) ---------------------------------------------------
  // The MEGA sheet has no green; a success colour is still needed for
  // "login OK", so it's tuned to sit next to the brand red / indigo.
  static const Color success = Color(0xFF00A886);
  static const Color successSoft = Color(0xFF3DD6A8);
  static const Color dangerSoft = Color(0xFFFF6B70); // red badge text

  // ---- Shape tokens (4–8px "crisp, utility" radii) -------------------------
  static const double radiusSm = 4;
  static const double radius = 8;
  static const double radiusLg = 12;

  // ---- Type scale (Lexend, bundled in assets/fonts) ------------------------
  static const String font = 'Lexend';

  static const TextStyle h1 = TextStyle(
    fontFamily: font,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.78, // -0.03em
    height: 1.15,
    color: textPrimary,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: font,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4, // -0.02em
    color: textPrimary,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: font,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontFamily: font,
    fontSize: 14,
    height: 1.5,
    color: textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontFamily: font,
    fontSize: 14,
    height: 1.5,
    color: textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: font,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );
  static const TextStyle overline = TextStyle(
    fontFamily: font,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.3, // 0.12em
    color: megaRed,
  );
  static const TextStyle label = TextStyle(
    fontFamily: font,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: textSecondary,
  );
  static const TextStyle mono = TextStyle(
    fontFamily: 'Menlo',
    fontSize: 12.5,
    color: textPrimary,
  );

  // ---- Reusable button styles ---------------------------------------------

  /// `.btn-secondary` — indigo outline (text lightened for contrast on black).
  static final ButtonStyle secondaryButton =
      OutlinedButton.styleFrom(
        foregroundColor: megaBlueSoft,
        side: const BorderSide(color: megaBlue),
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ).copyWith(
        overlayColor: WidgetStatePropertyAll(megaBlue.withValues(alpha: 0.14)),
      );

  /// `.btn-ghost-light` — grey outline, for low-emphasis actions.
  static final ButtonStyle ghostButton = OutlinedButton.styleFrom(
    foregroundColor: textSecondary,
    side: const BorderSide(color: borderSubtle),
    textStyle: const TextStyle(
      fontFamily: font,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  ).copyWith(overlayColor: const WidgetStatePropertyAll(stateHover));

  // ---- ThemeData -----------------------------------------------------------
  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: megaRed,
      onPrimary: textPrimary,
      secondary: megaBlue,
      onSecondary: textPrimary,
      tertiary: megaBlueSoft,
      error: megaRed,
      onError: textPrimary,
      surface: bgSurface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: bgElevated,
      outline: borderSubtle,
      outlineVariant: hairline,
    );

    OutlineInputBorder fieldBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: font,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgBase,
      canvasColor: bgBase,
      dividerColor: hairline,
      hoverColor: stateHover,
      splashFactory: NoSplash.splashFactory,
      textTheme: const TextTheme(
        bodyMedium: body,
        bodySmall: caption,
        titleMedium: h3,
        titleLarge: h2,
        labelLarge: TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: megaBlueSoft,
        selectionColor: megaBlue.withValues(alpha: 0.45),
        selectionHandleColor: megaBlue,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: hairline, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return stateHover;
            if (s.contains(WidgetState.hovered) ||
                s.contains(WidgetState.pressed)) {
              return megaRedHover;
            }
            return megaRed;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? textMuted : textPrimary,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: font,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: megaBlueSoft,
          textStyle: const TextStyle(
            fontFamily: font,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          hoverColor: stateHover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: bgBase,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: fieldBorder(borderSubtle),
        enabledBorder: fieldBorder(hairline),
        disabledBorder: fieldBorder(hairline),
        focusedBorder: fieldBorder(stateFocus, 1.5),
        errorBorder: fieldBorder(megaRed),
        focusedErrorBorder: fieldBorder(megaRed, 1.5),
        hintStyle: const TextStyle(
          fontFamily: font,
          color: textMuted,
          fontSize: 13,
        ),
        labelStyle: const TextStyle(fontFamily: font, color: textSecondary),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? megaRed : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(textPrimary),
        side: const BorderSide(color: borderSubtle, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: megaRed,
        linearTrackColor: stateHover,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: borderSubtle),
        ),
        titleTextStyle: h2,
        contentTextStyle: bodySecondary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bgElevated,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderSubtle),
        ),
        textStyle: const TextStyle(
          fontFamily: font,
          fontSize: 12,
          color: textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 350),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgBase,
        contentTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        actionTextColor: megaBlueSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(borderSubtle.withValues(alpha: 0.9)),
        radius: const Radius.circular(8),
      ),
    );
  }
}
