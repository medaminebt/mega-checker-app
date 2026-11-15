/// Where the Supabase sign-in session is kept.
///
/// Web: `localStorage` (stay signed in) or `sessionStorage` (signed out when
/// the tab or browser closes), following `Prefs.signOutOnBrowserClose`.
/// Desktop: null, i.e. supabase_flutter's default (shared_preferences).
library;

export 'auth_storage_stub.dart'
    if (dart.library.js_interop) 'auth_storage_web.dart';
