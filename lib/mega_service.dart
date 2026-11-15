import 'models.dart';
import 'platform/cmd_result.dart';
import 'platform/native.dart';

/// Drives MEGAcmd to test an account: logout (clean slate) → login → touch the
/// account (whoami + df + ls) so activity registers and storage is read →
/// logout. Returns a classified result; the caller stores it in Supabase.
/// [freeUpSpace] does the same with a clean-up step after the login.
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
    return _session(acct);
  }

  /// Test-only hook for [freeUpSpace].
  static Future<LoginResult> Function(Account, FreeUpAction)? overrideFreeUp;

  /// Log in, permanently delete the Rubbish Bin's contents or all old file
  /// versions, re-read the storage, log out. Counts as a keep-alive login
  /// too. [LoginResult.actionError] is set when the login worked but the
  /// clean-up didn't.
  static Future<LoginResult> freeUpSpace(
    Account acct,
    FreeUpAction action,
  ) async {
    final override = overrideFreeUp;
    if (override != null) return override(acct, action);
    return _session(acct, action: action);
  }

  /// logout (clean slate) → login → optional clean-up → whoami + df + ls →
  /// logout.
  static Future<LoginResult> _session(
    Account acct, {
    FreeUpAction? action,
  }) async {
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
      final actionError = action == null ? null : await _freeUp(action);
      // Read-only actions that unambiguously count as activity. `df` also
      // gives us the account's used / total storage, bin and versions.
      await MegaCmd.run('whoami', []);
      final df = await MegaCmd.run('df', [], timeoutSec: 60);
      final report = df == null ? null : parseDf(df.output);
      await MegaCmd.run('ls', ['/']);
      await MegaCmd.run('logout', [], timeoutSec: 60);
      return LoginResult(
        LoginOutcome.success,
        actionError ?? 'logged in successfully',
        storage: report?.storage,
        rubbishBytes: report?.rubbishBytes,
        versionsBytes: report?.versionsBytes,
        actionError: actionError,
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

  /// Runs the clean-up while logged in. Returns an error text, or null.
  ///
  /// `//bin` is MEGAcmd's name for the Rubbish Bin; MEGAcmd expands the `*`
  /// itself (no shell is involved), and an already-empty bin answers
  /// "No such file or directory", which isn't an error here.
  static Future<String?> _freeUp(FreeUpAction action) async {
    final CmdResult? r;
    switch (action) {
      case FreeUpAction.emptyRubbishBin:
        r = await MegaCmd.run('rm', ['-r', '-f', '//bin/*'], timeoutSec: 900);
        if (r != null && r.output.contains('No such file or directory')) {
          return null;
        }
      case FreeUpAction.deleteVersions:
        r = await MegaCmd.run('deleteversions', [
          '-f',
          '--all',
        ], timeoutSec: 900);
    }
    if (r == null) return 'MEGAcmd disappeared mid-run';
    if (r.exitCode != 0) {
      final what = action == FreeUpAction.emptyRubbishBin
          ? 'Emptying the Rubbish Bin'
          : 'Deleting old versions';
      return '$what failed: ${_lastMeaningfulLine(r.output)}';
    }
    return null;
  }

  // ---- storage -------------------------------------------------------------

  // `mega-df` (no -h) prints sizes in bytes, e.g.
  //   Cloud drive:               5242880 in       3 file(s) and       1 folder(s)
  //   Inbox:                           0 in       0 file(s) and       0 folder(s)
  //   Rubbish bin:                104857 in       2 file(s) and       0 folder(s)
  //   ---------------------------------------------------------------------------
  //   USED STORAGE:          1234567                         5.88% of 21474836480
  //   ---------------------------------------------------------------------------
  //   Total size taken up by file versions:        52428
  // Every size column is padded/truncated to 12 chars by MEGAcmd, so ≥ ~1 TB
  // shows up as "21...552". For USED STORAGE that falls back to percent ×
  // total; the bin / versions figures are then left unknown.
  static final _dfRe = RegExp(
    r'USED STORAGE:\s*(\S+)\s+([\d.]+|-+)%\s+of\s+(\d+)',
    caseSensitive: false,
  );
  static final _binRe = RegExp(
    r'Rubbish bin:\s*(\S+)\s+in\s',
    caseSensitive: false,
  );
  static final _versionsRe = RegExp(
    r'Total size taken up by file versions:\s*(\S+)',
    caseSensitive: false,
  );

  /// Parse the output of `mega-df` into used / total bytes. Returns null when
  /// the output doesn't contain the `USED STORAGE` line (e.g. not logged in).
  static StorageInfo? parseDfOutput(String output) => parseDf(output)?.storage;

  /// Everything the app reads from `mega-df`, or null when the output has no
  /// `USED STORAGE` line.
  static DfReport? parseDf(String output) {
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
    int? size(RegExp re) {
      final g = re.firstMatch(normalised)?.group(1);
      return g == null ? null : int.tryParse(g);
    }

    return DfReport(
      StorageInfo(used, total),
      rubbishBytes: size(_binRe),
      versionsBytes: size(_versionsRe),
    );
  }
}

/// What `mega-df` reports.
class DfReport {
  const DfReport(this.storage, {this.rubbishBytes, this.versionsBytes});

  final StorageInfo storage;

  /// Size of the Rubbish Bin (null if missing or truncated).
  final int? rubbishBytes;

  /// "Total size taken up by file versions" (null if missing or truncated).
  final int? versionsBytes;
}
