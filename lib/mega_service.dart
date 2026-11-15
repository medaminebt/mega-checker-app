import 'dart:io';

import 'models.dart';

/// Drives MEGAcmd to test an account: logout (clean slate) → login → touch the
/// account (whoami + df + ls) so activity registers and storage is read →
/// logout. Returns a classified result; the caller stores it in Supabase.
class MegaService {
  // Where the mega-* tools usually live on an Apple-Silicon Mac. The app may be
  // launched from Finder with a minimal PATH, so we check explicit paths first.
  static const List<String> _searchDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/Applications/MEGAcmd.app/Contents/MacOS',
  ];

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? _resolve(String cmd) {
    for (final d in _searchDirs) {
      final p = '$d/$cmd';
      if (File(p).existsSync()) return p;
    }
    try {
      final w = Process.runSync('which', [cmd]);
      if (w.exitCode == 0) {
        final p = w.stdout.toString().trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  static bool get isInstalled => _resolve('mega-login') != null;

  /// PATH that includes the MEGAcmd dirs. Crucial when the app is launched from
  /// Finder: that gives a minimal PATH, and `mega-login` would otherwise fail to
  /// find/start its background server (`mega-cmd-server`) and just hang.
  static String get _augmentedPath {
    final existing = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return '${_searchDirs.join(':')}:$existing';
  }

  static Future<ProcessResult?> _run(
    String cmd,
    List<String> args, {
    int timeoutSec = 90,
  }) async {
    final exe = _resolve(cmd);
    if (exe == null) return null;
    try {
      return await Process.run(
        exe,
        args,
        environment: {'PATH': _augmentedPath},
      ).timeout(Duration(seconds: timeoutSec));
    } catch (e) {
      return ProcessResult(0, -1, '', e.toString());
    }
  }

  static bool _serverReady = false;

  /// Start the MEGAcmd background server once, **detached**, so it doesn't
  /// inherit the pipes of a later Process.run() (which is what makes the first
  /// login hang when the app is launched from Finder). Subsequent commands then
  /// just connect to the already-running server and return promptly.
  static Future<void> _ensureServer() async {
    if (_serverReady) return;
    final exe = _resolve('mega-whoami');
    if (exe == null) return;
    try {
      await Process.start(
        exe,
        [],
        mode: ProcessStartMode.detached,
        environment: {'PATH': _augmentedPath},
      );
      // Give the server a moment to come up on first launch.
      await Future.delayed(const Duration(seconds: 3));
    } catch (_) {}
    _serverReady = true;
  }

  static String _lastMeaningfulLine(String s) {
    final lines = s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? 'unknown error' : lines.last;
  }

  /// Test-only hook: when set, [keepAlive] returns this instead of touching
  /// MEGAcmd or the network.
  static Future<LoginResult> Function(Account)? overrideKeepAlive;

  /// Test one account's login and refresh its activity.
  static Future<LoginResult> keepAlive(Account acct) async {
    final override = overrideKeepAlive;
    if (override != null) return override(acct);

    final email = acct.email;

    if (!_emailRe.hasMatch(email)) {
      return LoginResult(
        LoginOutcome.invalidEmail,
        'invalid email address format',
      );
    }
    if (!isInstalled) {
      return LoginResult(
        LoginOutcome.megacmdMissing,
        'MEGAcmd not found — install with: brew install --cask megacmd',
      );
    }

    // Make sure the background server is up (detached) before we pipe commands.
    await _ensureServer();

    // Start from a clean state (also clears any "already logged in" error).
    await _run('mega-logout', [], timeoutSec: 30);

    final res = await _run('mega-login', [email, acct.password]);
    if (res == null) {
      return LoginResult(LoginOutcome.error, 'MEGAcmd disappeared mid-run');
    }

    final out = '${res.stdout}\n${res.stderr}';
    final lower = out.toLowerCase();

    if (res.exitCode == 0 && !lower.contains('login failed')) {
      // Read-only actions that unambiguously count as activity. `df` also
      // gives us the account's used / total storage.
      await _run('mega-whoami', []);
      final df = await _run('mega-df', [], timeoutSec: 60);
      final storage = df == null
          ? null
          : parseDfOutput('${df.stdout}\n${df.stderr}');
      await _run('mega-ls', ['/']);
      await _run('mega-logout', [], timeoutSec: 60);
      return LoginResult(
        LoginOutcome.success,
        'logged in successfully',
        storage: storage,
      );
    }

    // Failed: classify, clean up any partial session.
    final detail = _lastMeaningfulLine(out);
    await _run('mega-logout', [], timeoutSec: 60);

    if (lower.contains('email or password')) {
      return LoginResult(LoginOutcome.wrongCredentials, detail);
    }
    if (lower.contains('2fa') ||
        lower.contains('two-factor') ||
        lower.contains('multi-factor') ||
        lower.contains('mfa')) {
      return LoginResult(LoginOutcome.needs2fa, detail);
    }
    return LoginResult(LoginOutcome.error, detail);
  }

  // ---- storage -------------------------------------------------------------

  // `mega-df` (no -h) prints sizes in bytes, e.g.
  //   USED STORAGE:          1234567                         5.88% of 21474836480
  // The used column is padded/truncated to 12 chars by MEGAcmd, so ≥ ~1 TB
  // shows up as "21...552" — in that case fall back to percent × total.
  static final _dfRe = RegExp(
    r'USED STORAGE:\s*(\S+)\s+([\d.]+|-+)%\s+of\s+(\d+)',
    caseSensitive: false,
  );

  /// Parse the output of `mega-df` into used / total bytes. Returns null when
  /// the output doesn't contain the `USED STORAGE` line (e.g. not logged in).
  static StorageInfo? parseDfOutput(String output) {
    final m = _dfRe.firstMatch(output);
    if (m == null) return null;
    final total = int.tryParse(m.group(3)!);
    if (total == null) return null;
    var used = int.tryParse(m.group(1)!);
    if (used == null) {
      final pct = double.tryParse(m.group(2)!);
      if (pct == null) return null;
      used = (total * pct / 100).round();
    }
    return StorageInfo(used, total);
  }
}
