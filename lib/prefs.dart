import 'package:shared_preferences/shared_preferences.dart';

/// Small local settings stored with `shared_preferences`: the app's
/// `NSUserDefaults` plist on macOS, a JSON file in `%APPDATA%` on Windows,
/// `localStorage` in the web build. Nothing secret about MEGA lives here —
/// the accounts themselves are in Supabase.
///
/// Note: `supabase_flutter` also keeps its sign-in session in
/// shared_preferences, so you stay signed in between launches.
class Prefs {
  static SharedPreferences? _p;

  /// Load the preferences once at start-up (see `main()`). Until then the
  /// getters return defaults and the setters are no-ops — handy in tests.
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static const _kUrl = 'supabase_url';
  static const _kKey = 'supabase_publishable_key';
  static const _kLastEmail = 'last_sign_in_email';
  static const _kShowSecrets = 'show_secrets';
  static const _kSortColumn = 'sort_column';
  static const _kSortAsc = 'sort_asc';
  static const _kSignOutOnClose = 'sign_out_on_browser_close';
  static const _kSchedule = 'check_schedule';

  // ---- Supabase connection -----------------------------------------------

  static String? get supabaseUrl => _p?.getString(_kUrl);
  static String? get supabaseKey => _p?.getString(_kKey);

  static bool get hasSupabaseConfig =>
      (supabaseUrl ?? '').isNotEmpty && (supabaseKey ?? '').isNotEmpty;

  static Future<void> saveSupabaseConfig(String url, String key) async {
    await _p?.setString(_kUrl, url);
    await _p?.setString(_kKey, key);
  }

  static Future<void> clearSupabaseConfig() async {
    await _p?.remove(_kUrl);
    await _p?.remove(_kKey);
  }

  // ---- convenience -------------------------------------------------------

  /// Pre-fills the sign-in email field.
  static String get lastSignInEmail => _p?.getString(_kLastEmail) ?? '';
  static set lastSignInEmail(String v) => _p?.setString(_kLastEmail, v);

  /// Whether passwords and MEGA keys are shown in clear text.
  static bool get showSecrets => _p?.getBool(_kShowSecrets) ?? false;
  static set showSecrets(bool v) => _p?.setBool(_kShowSecrets, v);

  /// Table sort: `null`, `'status'`, `'email'`, `'login'` or `'storage'`.
  static String? get sortColumn => _p?.getString(_kSortColumn);
  static set sortColumn(String? v) =>
      v == null ? _p?.remove(_kSortColumn) : _p?.setString(_kSortColumn, v);

  static bool get sortAsc => _p?.getBool(_kSortAsc) ?? true;
  static set sortAsc(bool v) => _p?.setBool(_kSortAsc, v);

  // ---- security & scheduling ---------------------------------------------

  /// Web: keep the sign-in session in sessionStorage, so closing the tab or
  /// browser signs you out (see `platform/auth_storage_web.dart`).
  static bool get signOutOnBrowserClose =>
      _p?.getBool(_kSignOutOnClose) ?? false;
  static Future<void> setSignOutOnBrowserClose(bool v) async =>
      _p?.setBool(_kSignOutOnClose, v);

  /// Desktop: the scheduled check as JSON (see `CheckSchedule.encode`), or
  /// null when none is set up. The OS holds the real schedule; this copy
  /// fills the dialog and tells a scheduled run whether it was a one-off.
  static String? get checkSchedule => _p?.getString(_kSchedule);
  static Future<void> setCheckSchedule(String? json) async =>
      json == null ? _p?.remove(_kSchedule) : _p?.setString(_kSchedule, json);
}
