// Desktop build (macOS, Windows): MEGAcmd processes + Finder / Explorer.
import 'dart:io';

import 'cmd_result.dart';

/// A resolved MEGAcmd command: the executable plus leading arguments.
class _Command {
  const _Command(this.exe, this.prefix);
  final String exe;
  final List<String> prefix;
}

/// Runs MEGAcmd commands (`login`, `logout`, `whoami`, `df`, `ls`).
///
/// - **macOS / Linux**: one `mega-<command>` script per command.
/// - **Windows**: the `mega-*.bat` wrappers all call
///   `MEGAclient.exe <command> …`; calling it directly skips cmd.exe, whose
///   quoting would
///   mangle passwords containing `& ^ % "` and similar characters.
class MegaCmd {
  static bool get isSupported => true;

  // Where the mega-* tools usually live on a Mac. The app may be launched
  // from Finder with a minimal PATH, so explicit paths are checked first.
  static const List<String> _unixDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/Applications/MEGAcmd.app/Contents/MacOS',
    '/usr/bin',
  ];

  // MEGAcmd's Windows installer puts everything in %LOCALAPPDATA%\MEGAcmd.
  static List<String> get _windowsDirs {
    final env = Platform.environment; // case-insensitive keys on Windows
    return [
      for (final v in ['LOCALAPPDATA', 'ProgramFiles', 'ProgramFiles(x86)'])
        if ((env[v] ?? '').isNotEmpty) '${env[v]}\\MEGAcmd',
    ];
  }

  static String get installHint => Platform.isMacOS
      ? 'MEGAcmd not found — install with: brew install --cask megacmd'
      : 'MEGAcmd not found — install it from https://mega.io/cmd';

  static String? _findExecutable(String name, List<String> dirs) {
    final sep = Platform.isWindows ? '\\' : '/';
    for (final d in dirs) {
      final p = '$d$sep$name';
      if (File(p).existsSync()) return p;
    }
    try {
      final w = Process.runSync(Platform.isWindows ? 'where' : 'which', [name]);
      if (w.exitCode == 0) {
        final p = w.stdout.toString().split(RegExp(r'[\r\n]+')).first.trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  static _Command? _resolve(String command) {
    if (Platform.isWindows) {
      final exe = _findExecutable('MEGAclient.exe', _windowsDirs);
      return exe == null ? null : _Command(exe, [command]);
    }
    final exe = _findExecutable('mega-$command', _unixDirs);
    return exe == null ? null : _Command(exe, const []);
  }

  static bool get isInstalled => _resolve('login') != null;

  /// PATH that includes the MEGAcmd dirs. Crucial on macOS when the app is
  /// launched from Finder: that gives a minimal PATH, and `mega-login` would
  /// otherwise fail to find/start its background server (`mega-cmd-server`)
  /// and just hang. Windows needs nothing: the client is called by full path.
  static Map<String, String>? get _environment {
    if (Platform.isWindows) return null;
    final existing = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return {'PATH': '${_unixDirs.join(':')}:$existing'};
  }

  static bool _serverReady = false;

  /// Start the MEGAcmd background server once, **detached**, so it doesn't
  /// inherit the pipes of a later Process.run() (which is what makes the first
  /// login hang when the app is launched from Finder). Subsequent commands
  /// then just connect to the already-running server and return promptly.
  static Future<void> ensureServer() async {
    if (_serverReady) return;
    final c = _resolve('whoami');
    if (c == null) return;
    try {
      await Process.start(
        c.exe,
        c.prefix,
        mode: ProcessStartMode.detached,
        environment: _environment,
      );
      // Give the server a moment to come up on first launch.
      await Future.delayed(const Duration(seconds: 3));
    } catch (_) {}
    _serverReady = true;
  }

  /// Run one MEGAcmd command. Returns null when MEGAcmd isn't installed.
  static Future<CmdResult?> run(
    String command,
    List<String> args, {
    int timeoutSec = 90,
  }) async {
    final c = _resolve(command);
    if (c == null) return null;
    try {
      final r = await Process.run(c.exe, [
        ...c.prefix,
        ...args,
      ], environment: _environment).timeout(Duration(seconds: timeoutSec));
      return CmdResult(r.exitCode, '${r.stdout}', '${r.stderr}');
    } catch (e) {
      return CmdResult(-1, '', e.toString());
    }
  }
}

/// Shows an exported file in the system file manager.
class FileManager {
  static String? get revealLabel {
    if (Platform.isMacOS) return 'Reveal in Finder';
    if (Platform.isWindows) return 'Show in Explorer';
    if (Platform.isLinux) return 'Open folder';
    return null;
  }

  static Future<void> reveal(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        // explorer.exe always exits with 1, so the result is ignored.
        await Process.run('explorer.exe', ['/select,', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [File(path).parent.path]);
      }
    } catch (_) {}
  }
}
