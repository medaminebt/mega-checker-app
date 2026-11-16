import 'package:flutter/material.dart';

/// One set of colour tokens. [AppTheme] reads the active one, so the same
/// widget code draws both looks.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.borderSubtle,
    required this.hairline,
    required this.stateHover,
    required this.accentText,
    required this.success,
    required this.successSoft,
    required this.dangerSoft,
    required this.rowAlt,
    required this.rowHover,
    required this.tableHeader,
  });

  final Brightness brightness;
  final Color bgBase; // canvas
  final Color bgSurface; // cards, panels, modals
  final Color bgElevated; // tooltips, raised
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color borderSubtle; // input outlines
  final Color hairline; // dividers on surfaces
  final Color stateHover;
  final Color accentText; // indigo used as text / links / small icons
  final Color success;
  final Color successSoft; // green badge text
  final Color dangerSoft; // red badge text
  final Color rowAlt; // every other table row
  final Color rowHover;
  final Color tableHeader;

  /// MEGA's default experience (the original look of the app).
  static const dark = AppPalette(
    brightness: Brightness.dark,
    bgBase: Color(0xFF000000),
    bgSurface: Color(0xFF1B1B1B),
    bgElevated: Color(0xFF242F47),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA6A6AF),
    textMuted: Color(0xFF6B6B75),
    textInverse: Color(0xFF000000),
    borderSubtle: Color(0xFF374151),
    hairline: Color(0xFF2A2A2A),
    stateHover: Color(0xFF2A2A2A),
    accentText: Color(0xFF9DA0F5),
    success: Color(0xFF00A886),
    successSoft: Color(0xFF3DD6A8),
    dangerSoft: Color(0xFFFF6B70),
    rowAlt: Color(0xFF1F1F1F),
    rowHover: Color(0xFF222222),
    tableHeader: Color(0xFF141414),
  );

  /// Light counterpart: white panels on a soft grey canvas, the same brand
  /// red and indigo, text colours darkened to keep 4.5:1 contrast.
  static const light = AppPalette(
    brightness: Brightness.light,
    bgBase: Color(0xFFF4F4F6),
    bgSurface: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF15151A),
    textSecondary: Color(0xFF55555F),
    textMuted: Color(0xFF74747E),
    textInverse: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFCFD3DA),
    hairline: Color(0xFFE6E7EB),
    stateHover: Color(0xFFEDEDF1),
    accentText: Color(0xFF3F42C3),
    success: Color(0xFF00A886),
    successSoft: Color(0xFF007A5C),
    dangerSoft: Color(0xFFC81E25),
    rowAlt: Color(0xFFFAFAFB),
    rowHover: Color(0xFFF1F1F5),
    tableHeader: Color(0xFFF7F7F9),
  );
}

/// MEGA design system — the tokens from the "MEGA — UX/UI Color System &
/// Theme" sheet, in a dark (MEGA's default) and a light palette. Colours and
/// text styles follow the active palette ([use]); brand colours, radii and
/// the font are the same in both.
class AppTheme {
  static AppPalette _p = AppPalette.dark;
  static _Styles _s = _Styles(AppPalette.dark);

  /// Switch every token to the [b] palette. The app root calls this and then
  /// rebuilds the whole tree (see `main.dart`).
  static void use(Brightness b) {
    final next = b == Brightness.light ? AppPalette.light : AppPalette.dark;
    if (identical(next, _p)) return;
    _p = next;
    _s = _Styles(next);
  }

  static Brightness get brightness => _p.brightness;
  static bool get isDark => _p.brightness == Brightness.dark;
  static AppPalette get palette => _p;

  // ---- Brand (same in both palettes) ---------------------------------------
  static const Color megaRed = Color(0xFFD9272E); // --brand-primary
  static const Color megaRedHover = Color(0xFFC22026);
  static const Color megaRedAlt = Color(0xFFDD1405); // Monza red
  static const Color megaBlue = Color(0xFF3F42C3); // --brand-secondary
  static const Color ashGrey = Color(0xFFA6A6AF);
  static const Color stateFocus = megaBlue;

  /// Text on a red or indigo fill (buttons, badges): white in both looks.
  static const Color onBrand = Color(0xFFFFFFFF);

  // ---- Palette tokens ------------------------------------------------------
  static Color get bgBase => _p.bgBase;
  static Color get bgSurface => _p.bgSurface;
  static Color get bgElevated => _p.bgElevated;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get textInverse => _p.textInverse;
  static Color get borderSubtle => _p.borderSubtle;
  static Color get hairline => _p.hairline;
  static Color get stateHover => _p.stateHover;
  static Color get rowAlt => _p.rowAlt;
  static Color get rowHover => _p.rowHover;
  static Color get tableHeader => _p.tableHeader;

  /// Icons of buttons that can't be used right now.
  static Color get disabledIcon => _p.textMuted.withValues(alpha: 0.35);

  /// Indigo for text, links and small icons (lightened on dark).
  static Color get megaBlueSoft => _p.accentText;

  // ---- Status (semantic) ---------------------------------------------------
  // The MEGA sheet has no green; a success colour is still needed for
  // "login OK", so it's tuned to sit next to the brand red / indigo.
  static Color get success => _p.success;
  static Color get successSoft => _p.successSoft;
  static Color get dangerSoft => _p.dangerSoft;

  // ---- Shape tokens (4–8px "crisp, utility" radii) -------------------------
  static const double radiusSm = 4;
  static const double radius = 8;
  static const double radiusLg = 12;

  // ---- Type scale (Lexend, bundled in assets/fonts) ------------------------
  static const String font = 'Lexend';

  static TextStyle get h1 => _s.h1;
  static TextStyle get h2 => _s.h2;
  static TextStyle get h3 => _s.h3;
  static TextStyle get body => _s.body;
  static TextStyle get bodySecondary => _s.bodySecondary;
  static TextStyle get caption => _s.caption;
  static TextStyle get overline => _s.overline;
  static TextStyle get label => _s.label;
  static TextStyle get mono => _s.mono;

  // ---- Reusable button styles ---------------------------------------------

  /// `.btn-secondary` — indigo outline.
  static ButtonStyle get secondaryButton => _s.secondaryButton;

  /// `.btn-ghost-light` — grey outline, for low-emphasis actions.
  static ButtonStyle get ghostButton => _s.ghostButton;

  // ---- ThemeData -----------------------------------------------------------
  /// Material theme for the active palette.
  static ThemeData theme() {
    // The constructors (not copyWith) so the container colours follow
    // primary / secondary, as the original dark-only theme did.
    final make = isDark ? ColorScheme.dark : ColorScheme.light;
    final scheme = make(
      primary: megaRed,
      onPrimary: onBrand,
      secondary: megaBlue,
      onSecondary: onBrand,
      tertiary: megaBlueSoft,
      error: megaRed,
      onError: onBrand,
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
      brightness: brightness,
      fontFamily: font,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgBase,
      canvasColor: bgBase,
      dividerColor: hairline,
      hoverColor: stateHover,
      splashFactory: NoSplash.splashFactory,
      textTheme: TextTheme(
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
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: hairline, space: 1),
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
            (s) => s.contains(WidgetState.disabled) ? textMuted : onBrand,
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
        hintStyle: TextStyle(fontFamily: font, color: textMuted, fontSize: 13),
        labelStyle: TextStyle(fontFamily: font, color: textSecondary),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? megaRed : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(onBrand),
        side: BorderSide(color: borderSubtle, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: megaRed,
        linearTrackColor: stateHover,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: bgSurface,
        surfaceTintColor: Colors.transparent,
        textStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderSubtle),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: borderSubtle),
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
        textStyle: TextStyle(
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
        contentTextStyle: TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        actionTextColor: megaBlueSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderSubtle),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(borderSubtle.withValues(alpha: 0.9)),
        radius: const Radius.circular(8),
      ),
    );
  }
}

/// Text and button styles for one palette, built once per switch.
class _Styles {
  _Styles(AppPalette p)
    : h1 = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.78, // -0.03em
        height: 1.15,
        color: p.textPrimary,
      ),
      h2 = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4, // -0.02em
        color: p.textPrimary,
      ),
      h3 = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
      body = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 14,
        height: 1.5,
        color: p.textPrimary,
      ),
      bodySecondary = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 14,
        height: 1.5,
        color: p.textSecondary,
      ),
      caption = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: p.textSecondary,
      ),
      overline = const TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3, // 0.12em
        color: AppTheme.megaRed,
      ),
      label = TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: p.textSecondary,
      ),
      // Menlo on macOS, Consolas / Cascadia Mono on Windows. A browser only
      // has the fonts the app bundles, so the web build ends on Lexend.
      mono = TextStyle(
        fontFamily: 'Menlo',
        fontFamilyFallback: const [
          'Consolas',
          'Cascadia Mono',
          'Courier New',
          AppTheme.font,
        ],
        fontSize: 12.5,
        color: p.textPrimary,
      ),
      secondaryButton =
          OutlinedButton.styleFrom(
            foregroundColor: p.accentText,
            side: const BorderSide(color: AppTheme.megaBlue),
            textStyle: const TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              AppTheme.megaBlue.withValues(alpha: 0.14),
            ),
          ),
      ghostButton = OutlinedButton.styleFrom(
        foregroundColor: p.textSecondary,
        side: BorderSide(color: p.borderSubtle),
        textStyle: const TextStyle(
          fontFamily: AppTheme.font,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
      ).copyWith(overlayColor: WidgetStatePropertyAll(p.stateHover));

  final TextStyle h1, h2, h3, body, bodySecondary, caption, overline, label;
  final TextStyle mono;
  final ButtonStyle secondaryButton, ghostButton;
}
