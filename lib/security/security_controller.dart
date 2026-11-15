/// What the Security and Scheduled-checks dialogs can do. The app gate
/// (`main.dart`) implements it, because it owns the Supabase session and the
/// unlocked vault; the home page only shows the dialogs.
abstract class SecurityController {
  // ---- 2FA -----------------------------------------------------------------

  /// e.g. "On · authenticator app added 15 Nov 2026".
  String get twoFactorSummary;

  // ---- master password -----------------------------------------------------

  /// Returns an error message, or null on success.
  Future<String?> changeMasterPassword(String current, String next);

  /// Replaces the recovery key. Returns (new key, null) or (null, error).
  Future<(String?, String?)> newRecoveryKey();

  // ---- remembered key (desktop) --------------------------------------------

  /// Whether "remember on this computer" exists here (desktop only).
  bool get canRemember;

  /// "this Mac" / "this PC".
  String get deviceName;

  /// Where the key is kept, e.g. "your macOS login Keychain".
  String get rememberStoreName;

  Future<bool> isRemembered();

  /// Returns an error message, or null on success.
  Future<String?> setRemembered(bool on);

  // ---- browser session (web) -----------------------------------------------

  /// Whether "sign out when the browser closes" exists here (web only).
  bool get canSignOutOnBrowserClose;

  bool get signOutOnBrowserClose;

  Future<void> setSignOutOnBrowserClose(bool on);
}
