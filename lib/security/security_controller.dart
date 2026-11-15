/// What an authenticator app needs (from Supabase's TOTP enrolment).
class TotpSetup {
  const TotpSetup({
    required this.factorId,
    required this.uri,
    required this.secret,
  });

  final String factorId;

  /// `otpauth://totp/…` — shown as a QR code.
  final String uri;

  /// The same secret as text, for typing in by hand.
  final String secret;
}

/// What the Security and Scheduled-checks dialogs can do. The app gate
/// (`main.dart`) implements it, because it owns the Supabase session and the
/// unlocked vault; the home page only shows the dialogs.
abstract class SecurityController {
  // ---- 2FA (optional) ------------------------------------------------------

  /// Whether an authenticator app is set up. When it is, every sign-in asks
  /// for a 6-digit code after the password.
  bool get twoFactorOn;

  /// e.g. "On · authenticator app, added 15 Nov 2026" or "Off".
  String get twoFactorSummary;

  /// Turning 2FA on, step 1: a new authenticator-app factor (QR code).
  /// Throws with a readable message.
  Future<TotpSetup> startTwoFactor();

  /// Step 2: the first code from the app. Returns an error message, or null
  /// once 2FA is on.
  Future<String?> confirmTwoFactor(String factorId, String code);

  /// Drops a setup that was never confirmed (dialog closed). Best effort.
  Future<void> cancelTwoFactor(String factorId);

  /// Turns 2FA off after checking a current code. Returns an error message,
  /// or null once it is off.
  Future<String?> turnOffTwoFactor(String code);

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
