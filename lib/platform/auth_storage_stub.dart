// Desktop: supabase_flutter's default session storage is used.
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthStorage {
  /// Whether "sign out when the browser closes" applies here (web only).
  static bool get isSupported => false;

  /// The storage to give `Supabase.initialize`, or null for the default.
  static LocalStorage? forProject(String supabaseUrl) => null;

  /// Move the saved session to match the current setting.
  static void applySetting() {}
}
