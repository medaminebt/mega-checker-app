import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'prefs.dart';

/// The appearance picked in the app: always dark (default), always light,
/// or the same as the operating system / browser.
class Appearance {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  /// Read the saved choice and switch [AppTheme] to it (after `Prefs.init`).
  static void load() {
    mode.value = Prefs.themeMode;
    AppTheme.use(resolve(mode.value, platformBrightness));
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await Prefs.setThemeMode(m);
  }

  static Brightness get platformBrightness =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  static Brightness resolve(ThemeMode m, Brightness platform) => switch (m) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => platform,
  };

  static String label(ThemeMode m) => switch (m) {
    ThemeMode.system => 'Match system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static IconData icon(ThemeMode m) => switch (m) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };
}
