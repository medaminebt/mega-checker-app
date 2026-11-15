import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'accounts_repository.dart';
import 'app_theme.dart';
import 'format.dart';
import 'platform/auth_storage.dart';
import 'platform/desktop.dart';
import 'prefs.dart';
import 'schedule.dart';
import 'screens/home_page.dart';
import 'screens/mfa_screens.dart';
import 'screens/setup_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/vault_screens.dart';
import 'security/encrypted_repository.dart';
import 'security/security_controller.dart';
import 'security/vault_crypto.dart';
import 'security/vault_store.dart';
import 'widgets/form_bits.dart';
import 'widgets/mega_logo.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();

  // Started by the OS schedule (launchd / Task Scheduler)?
  final scheduled =
      AppInstance.isSupported && args.contains(CheckSchedule.argument);
  if (AppInstance.isSupported) {
    AppInstance.enable();
    final first = await AppInstance.claim();
    if (scheduled && !first) {
      // The app is already open: that window runs the check instead of a
      // second copy fighting over MEGAcmd and the Supabase session.
      await AppInstance.requestScheduledCheck();
      await AppInstance.logRun(
        ScheduledRunEntry(
          at: DateTime.now(),
          note: 'Handed over to the open app window',
        ),
      );
      AppInstance.quit();
      return;
    }
  }
  runApp(MegaKeepAliveApp(scheduledRun: scheduled));
}

class MegaKeepAliveApp extends StatelessWidget {
  const MegaKeepAliveApp({super.key, this.scheduledRun = false});

  /// Started with `--scheduled-check`: check everything, then quit.
  final bool scheduledRun;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEGA Keep-Alive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      themeMode: ThemeMode.dark,
      home: AppGate(scheduledRun: scheduledRun),
    );
  }
}

enum _Vault { unknown, loading, missing, locked, unlocked, error }

class _Message implements Exception {
  _Message(this.text);
  final String text;

  @override
  String toString() => text;
}

/// Decides which screen to show:
///   no Supabase config        → [SetupScreen]
///   not signed in             → [SignInScreen]
///   2FA on, code not entered  → [MfaChallengeScreen]
///   (2FA is optional: it is turned on and off in the Security dialog)
///   no master password yet    → [VaultSetupScreen]
///   vault locked              → [UnlockScreen]
///   otherwise                 → [HomePage]
class AppGate extends StatefulWidget {
  const AppGate({super.key, this.scheduledRun = false});

  final bool scheduledRun;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> implements SecurityController {
  bool _booting = true;
  bool _ready = false; // Supabase initialised with the saved config
  String? _bootError;
  Session? _session;
  StreamSubscription<AuthState>? _authSub;

  // Master password / encryption.
  _Vault _vault = _Vault.unknown;
  String? _vaultUser; // user id the vault state below belongs to
  SecretKey? _dataKey;
  SecretKey? _pendingKey; // vault just created; waiting for "I saved it"
  String? _vaultError;
  AccountsRepository? _repo;

  bool _loggedWait = false;

  SupabaseClient get _client => Supabase.instance.client;
  VaultStore get _vaultStore => SupabaseVaultStore(_client);

  String? get _host {
    final url = Prefs.supabaseUrl;
    return url == null ? null : Uri.tryParse(url)?.host;
  }

  /// Key under which the vault key is remembered on this computer.
  String get _rememberId => '${_host ?? 'supabase'}:${_session?.user.id}';

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
      // No OAuth / magic links → nothing to read from deep links or the
      // browser's address bar. On the web the session goes to localStorage
      // or sessionStorage ("sign out when the browser closes").
      authOptions: FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: AuthStorage.forProject(url),
      ),
      debug: false,
    );
    _ready = true;
    _session = _client.auth.currentSession;
    _authSub = _client.auth.onAuthStateChange.listen((s) {
      if (!mounted) return;
      setState(() {
        _session = s.session;
        if (s.session == null) _clearVault();
      });
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
    _clearVault();
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
    // Signing out also forgets the key remembered on this computer.
    if (_session != null) await DeviceSecrets.delete(_rememberId);
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared anyway.
    }
    if (mounted) {
      setState(() {
        _session = null;
        _clearVault();
      });
    }
  }

  Future<void> _changeProject() async {
    await _disposeSupabase();
    if (mounted) setState(() {});
  }

  // ---- two-step sign-in (TOTP, optional) -----------------------------------

  Factor? get _verifiedTotp => _session?.user.factors
      ?.where(
        (f) =>
            f.factorType == FactorType.totp &&
            f.status == FactorStatus.verified,
      )
      .firstOrNull;

  Future<TotpSetup> _startEnrol() async {
    final mfa = _client.auth.mfa;
    try {
      // A half-finished setup (app closed before the first code) leaves an
      // unverified factor behind; clear it so a fresh QR code can be made.
      final factors = await mfa.listFactors();
      for (final f in factors.all) {
        if (f.status == FactorStatus.unverified) {
          try {
            await mfa.unenroll(f.id);
          } catch (_) {}
        }
      }
      final r = await mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'mega-checker-app',
        friendlyName: 'Authenticator ${Fmt.dateTime(DateTime.now())}',
      );
      final totp = r.totp;
      if (totp == null) throw _Message('Supabase sent no QR code.');
      return TotpSetup(factorId: r.id, uri: totp.uri, secret: totp.secret);
    } on _Message {
      rethrow;
    } catch (e) {
      throw _Message(describeError(e));
    }
  }

  Future<String?> _verifyEnrol(String factorId, String code) async {
    try {
      await _client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
      await _refreshFactors();
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  /// Reloads the user (and so the list of 2FA factors) from Supabase.
  Future<void> _refreshFactors() async {
    try {
      await _client.auth.mfa.listFactors(); // refreshes the session
    } catch (_) {
      // Offline: keep what the session already says.
    }
    if (mounted) setState(() => _session = _client.auth.currentSession);
  }

  /// Signed in with only the password: check that 2FA wasn't turned on
  /// (maybe on another computer) since this session started. The database
  /// would then hide every row, and the vault would look missing.
  Future<bool> _codeNowNeeded() async {
    final mfa = _client.auth.mfa;
    if (mfa.getAuthenticatorAssuranceLevel().currentLevel ==
        AuthenticatorAssuranceLevels.aal2) {
      return false;
    }
    try {
      await mfa.listFactors(); // refreshes the session and its factors
    } catch (_) {
      return false; // offline: loading the vault reports it
    }
    final aal = mfa.getAuthenticatorAssuranceLevel();
    return aal.currentLevel != AuthenticatorAssuranceLevels.aal2 &&
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  Future<String?> _verifyCode(String code) async {
    try {
      var factor = _verifiedTotp;
      if (factor == null) {
        final list = await _client.auth.mfa.listFactors();
        factor = list.totp.firstOrNull;
      }
      if (factor == null) {
        // 2FA was turned off on another device: nothing to enter.
        if (mounted) setState(() => _session = _client.auth.currentSession);
        return null;
      }
      await _client.auth.mfa.challengeAndVerify(
        factorId: factor.id,
        code: code,
      );
      if (mounted) setState(() => _session = _client.auth.currentSession);
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  // ---- master password -----------------------------------------------------

  void _clearVault() {
    _vault = _Vault.unknown;
    _vaultUser = null;
    _dataKey = null;
    _pendingKey = null;
    _vaultError = null;
    _repo = null;
  }

  /// Start loading the vault for [userId] (once per user).
  void _ensureVault(String userId) {
    if (_vaultUser == userId) return;
    _clearVault();
    _vaultUser = userId;
    _vault = _Vault.loading;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVault());
  }

  Future<void> _loadVault() async {
    final user = _vaultUser;
    if (mounted && _vault != _Vault.loading) {
      setState(() => _vault = _Vault.loading);
    }
    try {
      if (await _codeNowNeeded()) {
        if (!mounted || user != _vaultUser) return;
        // Show the code prompt; the vault loads again once it's entered.
        setState(() {
          _session = _client.auth.currentSession;
          _clearVault();
        });
        return;
      }
      if (!mounted || user != _vaultUser) return;
      final rec = await _vaultStore.fetch();
      if (!mounted || user != _vaultUser) return;
      if (rec == null) {
        setState(() => _vault = _Vault.missing);
        return;
      }
      final remembered = await _rememberedKey(rec);
      if (!mounted || user != _vaultUser) return;
      if (remembered != null) {
        _unlockWith(remembered);
      } else {
        setState(() => _vault = _Vault.locked);
      }
    } catch (e) {
      if (!mounted || user != _vaultUser) return;
      setState(() {
        _vault = _Vault.error;
        _vaultError = describeError(e);
      });
      _noteWaiting("couldn't open the vault: ${describeError(e)}");
    }
  }

  /// The key remembered on this computer, if it still fits the vault.
  Future<SecretKey?> _rememberedKey(VaultRecord rec) async {
    if (!DeviceSecrets.isSupported) return null;
    final stored = await DeviceSecrets.read(_rememberId);
    if (stored == null) return null;
    try {
      final key = SecretKey(base64.decode(stored));
      if (await VaultCrypto.checkKey(rec, key)) return key;
    } catch (_) {}
    await DeviceSecrets.delete(_rememberId); // stale (vault was reset)
    return null;
  }

  Future<bool> _remember(SecretKey key) async =>
      DeviceSecrets.write(_rememberId, base64.encode(await key.extractBytes()));

  void _unlockWith(SecretKey key) {
    setState(() {
      _dataKey = key;
      _repo = EncryptedAccountsRepository(
        SupabaseAccountsRepository(_client),
        FieldCipher(key),
      );
      _vault = _Vault.unlocked;
    });
  }

  Future<VaultRecord> _freshRecord() async {
    final rec = await _vaultStore.fetch();
    if (rec == null) throw _Message('No master password is set.');
    return rec;
  }

  Future<String> _createVault(String password, bool remember) async {
    final created = await VaultCrypto.create(password);
    try {
      await _vaultStore.insert(created.record);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Set on another device a moment ago.
        unawaited(_loadVault());
        throw _Message(
          'A master password was already set (maybe on another device). '
          'Unlock with that one.',
        );
      }
      throw _Message(describeError(e));
    } catch (e) {
      throw _Message(describeError(e));
    }
    _pendingKey = created.dataKey;
    if (remember) await _remember(created.dataKey);
    return created.recoveryKey.toString();
  }

  void _finishVaultSetup() {
    final key = _pendingKey;
    _pendingKey = null;
    if (key != null) _unlockWith(key);
  }

  Future<String?> _unlock(String password, bool remember) async {
    try {
      final rec = await _freshRecord();
      final key = await VaultCrypto.unlock(rec, password);
      if (key == null) return 'Wrong master password.';
      if (remember && !await _remember(key)) {
        return "Unlocked, but couldn't save it in ${DeviceSecrets.storeName}. "
            'Try again without Remember.';
      }
      _unlockWith(key);
      return null;
    } catch (e) {
      return e is _Message ? e.text : describeError(e);
    }
  }

  Future<String?> _recover(
    String recoveryKey,
    String newPassword,
    bool remember,
  ) async {
    try {
      final rec = await _freshRecord();
      final key = await VaultCrypto.unlockWithRecoveryKey(rec, recoveryKey);
      if (key == null) return "That recovery key doesn't match.";
      final updated = await VaultCrypto.rewrap(rec, key, newPassword);
      await _vaultStore.update(updated);
      if (remember) await _remember(key);
      _unlockWith(key);
      return null;
    } catch (e) {
      return e is _Message ? e.text : describeError(e);
    }
  }

  Future<String?> _resetVault() async {
    try {
      // Secrets first: if this fails, nothing is lost.
      await SupabaseAccountsRepository(_client).clearSecrets();
      await _vaultStore.delete();
      await DeviceSecrets.delete(_rememberId);
      if (mounted) {
        setState(() {
          _vault = _Vault.missing;
        });
      }
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  /// A scheduled run that can't go on without you: say so in its log, once.
  void _noteWaiting(String what) {
    if (!widget.scheduledRun || _loggedWait) return;
    _loggedWait = true;
    unawaited(
      AppInstance.logRun(
        ScheduledRunEntry(at: DateTime.now(), note: 'Waiting for you: $what'),
      ),
    );
  }

  // ---- SecurityController (Security & Scheduled checks dialogs) ------------

  @override
  bool get twoFactorOn => _verifiedTotp != null;

  @override
  String get twoFactorSummary {
    final f = _verifiedTotp;
    return f == null
        ? 'Off'
        : 'On · authenticator app, added ${Fmt.dateTime(f.createdAt)}';
  }

  @override
  Future<TotpSetup> startTwoFactor() => _startEnrol();

  @override
  Future<String?> confirmTwoFactor(String factorId, String code) =>
      _verifyEnrol(factorId, code);

  @override
  Future<void> cancelTwoFactor(String factorId) async {
    try {
      await _client.auth.mfa.unenroll(factorId);
    } catch (_) {
      // Left unverified; the next "Turn on 2FA" clears it.
    }
  }

  @override
  Future<String?> turnOffTwoFactor(String code) async {
    try {
      await _refreshFactors();
      final factor = _verifiedTotp;
      if (factor == null) return null; // already off (another device)
      // Prove the phone is at hand, then remove the factor. Supabase also
      // refuses to remove it from a session that skipped the code.
      await _client.auth.mfa.challengeAndVerify(
        factorId: factor.id,
        code: code,
      );
      await _client.auth.mfa.unenroll(factor.id);
      await _refreshFactors();
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  @override
  Future<String?> changeMasterPassword(String current, String next) async {
    try {
      final rec = await _freshRecord();
      final key = await VaultCrypto.unlock(rec, current);
      if (key == null) return 'Your current master password is wrong.';
      final updated = await VaultCrypto.rewrap(rec, key, next);
      await _vaultStore.update(updated);
      return null;
    } catch (e) {
      return e is _Message ? e.text : describeError(e);
    }
  }

  @override
  Future<(String?, String?)> newRecoveryKey() async {
    final key = _dataKey;
    if (key == null) return (null, 'Unlock first.');
    try {
      final rec = await _freshRecord();
      final (updated, recovery) = await VaultCrypto.newRecoveryKey(rec, key);
      await _vaultStore.update(updated);
      return (recovery.toString(), null);
    } catch (e) {
      return (null, e is _Message ? e.text : describeError(e));
    }
  }

  @override
  bool get canRemember => DeviceSecrets.isSupported;

  @override
  String get deviceName => DeviceSecrets.deviceName;

  @override
  String get rememberStoreName => DeviceSecrets.storeName;

  @override
  Future<bool> isRemembered() async =>
      DeviceSecrets.isSupported &&
      await DeviceSecrets.read(_rememberId) != null;

  @override
  Future<String?> setRemembered(bool on) async {
    if (!on) {
      await DeviceSecrets.delete(_rememberId);
      return null;
    }
    final key = _dataKey;
    if (key == null) return 'Unlock first.';
    return await _remember(key)
        ? null
        : "Couldn't save it in ${DeviceSecrets.storeName}.";
  }

  @override
  bool get canSignOutOnBrowserClose => AuthStorage.isSupported;

  @override
  bool get signOutOnBrowserClose => Prefs.signOutOnBrowserClose;

  @override
  Future<void> setSignOutOnBrowserClose(bool on) async {
    await Prefs.setSignOutOnBrowserClose(on);
    AuthStorage.applySetting();
  }

  // ---- screens -------------------------------------------------------------

  static const _splash = Scaffold(
    body: Center(child: MegaLogo(size: 64, glow: true)),
  );

  @override
  Widget build(BuildContext context) {
    if (_booting) return _splash;
    if (!_ready) {
      _noteWaiting('the Supabase connection is not set up');
      return SetupScreen(
        initialUrl: Prefs.supabaseUrl,
        initialKey: Prefs.supabaseKey,
        initialError: _bootError,
        onConnect: _connect,
      );
    }
    final session = _session;
    if (session == null) {
      _noteWaiting('signed out');
      return SignInScreen(
        projectHost: _host,
        onSignIn: _signIn,
        onChangeProject: _changeProject,
        notice: widget.scheduledRun
            ? 'A scheduled check is waiting. Sign in to let it run.'
            : null,
      );
    }
    final email = session.user.email;

    // 2FA is optional: only accounts with an authenticator app set up get
    // the code prompt. Everyone else goes straight on.
    final aal = _client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal.currentLevel != AuthenticatorAssuranceLevels.aal2 &&
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2) {
      _noteWaiting('the 2FA code');
      return MfaChallengeScreen(
        onVerify: _verifyCode,
        onSignOut: _signOut,
        email: email,
        waitingForScheduledCheck: widget.scheduledRun,
      );
    }

    _ensureVault(session.user.id);
    switch (_vault) {
      case _Vault.unknown:
      case _Vault.loading:
        return _splash;
      case _Vault.error:
        return _VaultErrorScreen(
          message: _vaultError ?? 'Something went wrong.',
          onRetry: _loadVault,
          onSignOut: _signOut,
        );
      case _Vault.missing:
        _noteWaiting('no master password is set');
        return VaultSetupScreen(
          onCreate: _createVault,
          onDone: _finishVaultSetup,
          onSignOut: _signOut,
          email: email,
          canRemember: DeviceSecrets.isSupported,
          deviceName: DeviceSecrets.deviceName,
        );
      case _Vault.locked:
        _noteWaiting('the master password (tick Remember to avoid this)');
        return UnlockScreen(
          onUnlock: _unlock,
          onRecover: _recover,
          onReset: _resetVault,
          onSignOut: _signOut,
          email: email,
          canRemember: DeviceSecrets.isSupported,
          deviceName: DeviceSecrets.deviceName,
          waitingForScheduledCheck: widget.scheduledRun,
        );
      case _Vault.unlocked:
        return HomePage(
          key: ValueKey(session.user.id),
          repository: _repo!,
          userEmail: email,
          projectHost: _host,
          onSignOut: _signOut,
          onChangeProject: _changeProject,
          security: this,
          scheduledRun: widget.scheduledRun,
          watchScheduleRequests:
              AppInstance.ownsAppLock && !widget.scheduledRun,
          onQuit: AppInstance.quit,
          signOutNote: DeviceSecrets.isSupported
              ? 'If the master password is remembered on '
                    '${DeviceSecrets.deviceName}, it is forgotten too (turn '
                    'Remember on again after signing in, for scheduled '
                    'checks).'
              : null,
        );
    }
  }
}

class _VaultErrorScreen extends StatelessWidget {
  const _VaultErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: "Couldn't open your passwords",
      subtitle: 'The app reads your encryption settings from Supabase first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineMessage(message),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onSignOut, child: const Text('Sign out')),
        ],
      ),
    );
  }
}
