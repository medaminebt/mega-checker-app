// Web: the session lives in localStorage or sessionStorage.
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../prefs.dart';

class AuthStorage {
  static bool get isSupported => true;

  static _BrowserAuthStorage? _current;

  /// Uses the same key as supabase_flutter's default storage, so a session
  /// saved by an older version of the app is still found.
  static LocalStorage? forProject(String supabaseUrl) {
    final ref = Uri.parse(supabaseUrl).host.split('.').first;
    return _current = _BrowserAuthStorage('sb-$ref-auth-token');
  }

  /// Call after changing `Prefs.signOutOnBrowserClose` while signed in.
  static void applySetting() => _current?.sync();
}

/// sessionStorage is cleared when the tab (or the whole browser) is closed;
/// localStorage stays until you sign out.
class _BrowserAuthStorage extends LocalStorage {
  _BrowserAuthStorage(this.key);

  final String key;

  web.Storage get _active => Prefs.signOutOnBrowserClose
      ? web.window.sessionStorage
      : web.window.localStorage;

  web.Storage get _other => Prefs.signOutOnBrowserClose
      ? web.window.localStorage
      : web.window.sessionStorage;

  /// Keep the session only in the storage the setting asks for.
  void sync() {
    final elsewhere = _other.getItem(key);
    if (elsewhere == null) return;
    if (_active.getItem(key) == null) _active.setItem(key, elsewhere);
    _other.removeItem(key);
  }

  @override
  Future<void> initialize() async => sync();

  @override
  Future<bool> hasAccessToken() async => _active.getItem(key) != null;

  @override
  Future<String?> accessToken() async => _active.getItem(key);

  @override
  Future<void> removePersistedSession() async {
    web.window.localStorage.removeItem(key);
    web.window.sessionStorage.removeItem(key);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _active.setItem(key, persistSessionString);
    _other.removeItem(key);
  }
}
