import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accounts_repository.dart';
import 'app_theme.dart';
import 'prefs.dart';
import 'screens/home_page.dart';
import 'screens/setup_screen.dart';
import 'screens/sign_in_screen.dart';
import 'widgets/mega_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  runApp(const MegaKeepAliveApp());
}

class MegaKeepAliveApp extends StatelessWidget {
  const MegaKeepAliveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEGA Keep-Alive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      themeMode: ThemeMode.dark,
      home: const AppGate(),
    );
  }
}

/// Decides which screen to show:
///   no Supabase config → [SetupScreen]
///   not signed in      → [SignInScreen]
///   signed in          → [HomePage]
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _booting = true;
  bool _ready = false; // Supabase initialised with the saved config
  String? _bootError;
  Session? _session;
  StreamSubscription<AuthState>? _authSub;

  SupabaseClient get _client => Supabase.instance.client;

  String? get _host {
    final url = Prefs.supabaseUrl;
    return url == null ? null : Uri.tryParse(url)?.host;
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    if (Prefs.hasSupabaseConfig) {
      try {
        await _initSupabase(Prefs.supabaseUrl!, Prefs.supabaseKey!);
      } catch (e) {
        _bootError = describeError(e);
      }
    }
    if (mounted) setState(() => _booting = false);
  }

  Future<void> _initSupabase(String url, String key) async {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      // No OAuth / magic links → no deep-link handling needed on desktop.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      debug: false,
    );
    _ready = true;
    _session = _client.auth.currentSession;
    _authSub = _client.auth.onAuthStateChange.listen((s) {
      if (mounted) setState(() => _session = s.session);
    });
  }

  Future<void> _disposeSupabase() async {
    await _authSub?.cancel();
    _authSub = null;
    if (_ready) {
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
    }
    _ready = false;
    _session = null;
  }

  /// Ask the API for the table without signing in. With the schema applied
  /// this is refused (anon has no access) or returns nothing — both prove the
  /// URL and key work. A missing table is reported later, after sign-in.
  Future<String?> _probe() async {
    try {
      await _client
          .from(SupabaseAccountsRepository.table)
          .select('id')
          .limit(1);
      return null;
    } on PostgrestException catch (e) {
      if (const ['42501', 'PGRST205', '42P01'].contains(e.code)) return null;
      return describeError(e);
    } catch (e) {
      return describeError(e);
    }
  }

  /// Used by [SetupScreen]: initialise, test, and save the config.
  Future<String?> _connect(String url, String key) async {
    await _disposeSupabase();
    try {
      await _initSupabase(url, key);
    } catch (e) {
      await _disposeSupabase();
      return describeError(e);
    }
    final problem = await _probe();
    if (problem != null) {
      await _disposeSupabase();
      return problem;
    }
    await Prefs.saveSupabaseConfig(url, key);
    if (mounted) setState(() => _bootError = null);
    return null;
  }

  Future<String?> _signIn(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      Prefs.lastSignInEmail = email;
      if (mounted) setState(() => _session = res.session);
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  Future<void> _signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared anyway.
    }
    if (mounted) setState(() => _session = null);
  }

  Future<void> _changeProject() async {
    await _disposeSupabase();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(child: MegaLogo(size: 64, glow: true)),
      );
    }
    if (!_ready) {
      return SetupScreen(
        initialUrl: Prefs.supabaseUrl,
        initialKey: Prefs.supabaseKey,
        initialError: _bootError,
        onConnect: _connect,
      );
    }
    final session = _session;
    if (session == null) {
      return SignInScreen(
        projectHost: _host,
        onSignIn: _signIn,
        onChangeProject: _changeProject,
      );
    }
    return HomePage(
      key: ValueKey(session.user.id),
      repository: SupabaseAccountsRepository(_client),
      userEmail: session.user.email,
      projectHost: _host,
      onSignOut: _signOut,
      onChangeProject: _changeProject,
    );
  }
}
