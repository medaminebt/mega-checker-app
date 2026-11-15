import 'models.dart';
import 'platform/native.dart';

/// Drives MEGAcmd to test an account: logout (clean slate) → login → touch the
/// account (whoami + df + ls) so activity registers and storage is read →
/// logout. Returns a classified result; the caller stores it in Supabase.
///
/// Desktop only (macOS, Windows). In the web build [isSupported] is false and
/// the UI disables the check buttons.
class MegaService {
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Test-only hook: when set, [keepAlive] returns this instead of touching
  /// MEGAcmd or the network.
  static Future<LoginResult> Function(Account)? overrideKeepAlive;

  /// Test-only hook: forces [isSupported] (e.g. false to render the web
  /// version's UI in a desktop test).
  static bool? debugSupported;

  /// Whether this build can run checks at all (false in a browser).
  static bool get isSupported =>
      debugSupported ?? (overrideKeepAlive != null || MegaCmd.isSupported);

  static bool get isInstalled => MegaCmd.isInstalled;

  static String _lastMeaningfulLine(String s) {
    final lines = s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? 'unknown error' : lines.last;
  }

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
    if (!MegaCmd.isSupported) {
      return LoginResult(LoginOutcome.unsupported, MegaCmd.installHint);
    }
    if (!MegaCmd.isInstalled) {
      return LoginResult(LoginOutcome.megacmdMissing, MegaCmd.installHint);
    }

    // Make sure the background server is up (detached) before we pipe commands.
    await MegaCmd.ensureServer();

    // Start from a clean state (also clears any "already logged in" error).
    await MegaCmd.run('logout', [], timeoutSec: 30);

    final res = await MegaCmd.run('login', [email, acct.password]);
    if (res == null) {
      return LoginResult(LoginOutcome.error, 'MEGAcmd disappeared mid-run');
    }

    final out = res.output;
    final lower = out.toLowerCase();

    if (res.exitCode == 0 && !lower.contains('login failed')) {
      // Read-only actions that unambiguously count as activity. `df` also
      // gives us the account's used / total storage.
      await MegaCmd.run('whoami', []);
      final df = await MegaCmd.run('df', [], timeoutSec: 60);
      final storage = df == null ? null : parseDfOutput(df.output);
      await MegaCmd.run('ls', ['/']);
      await MegaCmd.run('logout', [], timeoutSec: 60);
      return LoginResult(
        LoginOutcome.success,
        'logged in successfully',
        storage: storage,
      );
    }

    // Failed: classify, clean up any partial session.
    final detail = _lastMeaningfulLine(out);
    await MegaCmd.run('logout', [], timeoutSec: 60);

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
    final normalised = output.replaceAll('\r\n', '\n'); // Windows line endings
    final m = _dfRe.firstMatch(normalised);
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
