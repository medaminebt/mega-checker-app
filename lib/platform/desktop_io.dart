// Desktop build (macOS, Windows): lock files, the OS scheduler and the
// system keychain.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../schedule.dart';

String get _home => Platform.environment['HOME'] ?? '';

/// Folder for the lock files, the hand-off file and the scheduled-check log:
/// `~/Library/Application Support/mega-checker-app` on macOS,
/// `%APPDATA%\mega-checker-app` on Windows.
Directory get _dataDir {
  if (Platform.isWindows) {
    final appData =
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return Directory('$appData\\mega-checker-app');
  }
  if (Platform.isMacOS) {
    return Directory('$_home/Library/Application Support/mega-checker-app');
  }
  return Directory(
    '${_home.isEmpty ? Directory.systemTemp.path : _home}/.mega-checker-app',
  );
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

String _out(ProcessResult r) {
  final s = '${r.stdout}\n${r.stderr}'.trim();
  return s.isEmpty ? 'exit code ${r.exitCode}' : s;
}

/// Coordinates the copies of the app that can run at the same time.
///
/// * `app.lock` is held by an open app window for as long as it's open. A
///   scheduled run that finds it taken doesn't start a second copy (two
///   copies would fight over MEGAcmd's single login and over the Supabase
///   session); it leaves a `check-request` file instead, and the open window
///   runs the check.
/// * `checks.lock` is held while MEGAcmd is in use, so two copies never log
///   in at the same time.
///
/// The operating system releases both locks when a process exits, even if it
/// crashes.
class AppInstance {
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  static bool _enabled = false;

  // Kept open (and referenced) for the life of the process: closing it would
  // release the lock.
  static RandomAccessFile? _appLock;
  static RandomAccessFile? _checksLock;

  /// Whether this copy holds `app.lock` (the first window opened).
  static bool get ownsAppLock => _appLock != null;

  /// Turn the lock files on. `main()` does this; widget tests don't, so they
  /// never touch the real Application Support folder.
  static void enable() => _enabled = isSupported;

  /// (file, lockedByAnotherProcess). Unexpected errors count as "not
  /// locked", so a broken folder never blocks the app.
  static Future<(RandomAccessFile?, bool)> _tryLock(String name) async {
    try {
      final dir = _dataDir;
      await dir.create(recursive: true);
      final f = await File(_join(dir.path, name)).open(mode: FileMode.append);
      try {
        await f.lock(FileLock.exclusive);
        return (f, false);
      } on FileSystemException {
        await f.close();
        return (null, true);
      }
    } catch (_) {
      return (null, false);
    }
  }

  /// Hold `app.lock` for as long as this copy runs. False when another copy
  /// of the app already holds it.
  static Future<bool> claim() async {
    if (!_enabled) return true;
    final (f, busy) = await _tryLock('app.lock');
    _appLock = f;
    return !busy;
  }

  /// Take `checks.lock` before using MEGAcmd. False when another copy is
  /// checking accounts right now.
  static Future<bool> acquireChecks() async {
    if (!_enabled || _checksLock != null) return true;
    final (f, busy) = await _tryLock('checks.lock');
    _checksLock = f;
    return !busy;
  }

  static Future<void> releaseChecks() async {
    final f = _checksLock;
    _checksLock = null;
    if (f == null) return;
    try {
      await f.unlock();
    } catch (_) {}
    try {
      await f.close();
    } catch (_) {}
  }

  static File get _requestFile => File(_join(_dataDir.path, 'check-request'));

  /// Ask the open app window to run the scheduled check.
  static Future<void> requestScheduledCheck() async {
    await _dataDir.create(recursive: true);
    await _requestFile.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
  }

  /// True (once) when a scheduled run asked this window to check, less than
  /// 12 hours ago.
  static Future<bool> takeScheduledRequest() async {
    if (!_enabled) return false;
    final f = _requestFile;
    try {
      if (!await f.exists()) return false;
      final at = DateTime.tryParse((await f.readAsString()).trim());
      await f.delete();
      return at != null &&
          DateTime.now().toUtc().difference(at) < const Duration(hours: 12);
    } catch (_) {
      return false;
    }
  }

  static String get logPath => _join(_dataDir.path, 'scheduled-checks.log');

  /// Append to the scheduled-check log (one JSON object per line, last 200
  /// kept).
  static Future<void> logRun(ScheduledRunEntry entry) async {
    if (!_enabled) return;
    try {
      await _dataDir.create(recursive: true);
      final f = File(logPath);
      var lines = await f.exists() ? await f.readAsLines() : <String>[];
      lines = [...lines.where((l) => l.trim().isNotEmpty), jsonEncode(entry)];
      if (lines.length > 200) lines = lines.sublist(lines.length - 200);
      await f.writeAsString('${lines.join('\n')}\n', flush: true);
    } catch (_) {}
  }

  /// Newest first.
  static Future<List<ScheduledRunEntry>> recentRuns({int limit = 5}) async {
    try {
      final f = File(logPath);
      if (!await f.exists()) return const [];
      final entries = (await f.readAsLines())
          .map(ScheduledRunEntry.fromJson)
          .whereType<ScheduledRunEntry>()
          .toList();
      return entries.reversed.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Test-only: replaces [executable] (README screenshots).
  static String? debugExecutable;

  /// The program the schedule starts: this very copy of the app.
  static String get executable =>
      debugExecutable ?? Platform.resolvedExecutable;

  static String _bundle(String exe) {
    final i = exe.indexOf('.app/');
    return i < 0 ? exe : exe.substring(0, i + 4);
  }

  /// A warning when the schedule would point at a copy that's likely to move
  /// or be rebuilt.
  static String? get locationWarning {
    final exe = executable;
    if (Platform.isMacOS && !exe.startsWith('/Applications/')) {
      return 'This copy of the app runs from ${_bundle(exe)}. Move it to the '
          'Applications folder first (or run ./build.sh --install), then set '
          'up the schedule from there, so it keeps working after you rebuild '
          'or move things.';
    }
    if (Platform.isWindows && exe.toLowerCase().contains(r'\build\windows\')) {
      return 'This copy runs from the build folder. Copy the whole Release '
          'folder somewhere permanent (for example Documents\\mega-checker-app) '
          'and set up the schedule from that copy.';
    }
    return null;
  }

  static void quit() => exit(0);
}

/// Installs the schedule with the operating system.
///
/// * **macOS**: a LaunchAgent in `~/Library/LaunchAgents`, loaded into your
///   login session with `launchctl`. If the Mac is asleep at that time, it
///   runs when it wakes up.
/// * **Windows**: a Task Scheduler task (`schtasks /Create /XML`) that runs
///   only while you're signed in, and catches up after a missed start.
class Scheduler {
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  static String get systemName =>
      Platform.isMacOS ? 'launchd (a LaunchAgent)' : 'Windows Task Scheduler';

  static const _label = CheckSchedule.launchdLabel;
  static const _task = CheckSchedule.windowsTaskName;

  static String get _plistPath => '$_home/Library/LaunchAgents/$_label.plist';

  static String get _launchdLog => _join(_dataDir.path, 'launchd.log');

  static String get _schtasks {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\schtasks.exe';
  }

  /// Where to look for it by hand.
  static String get definitionPath => Platform.isMacOS
      ? _plistPath
      : 'Task Scheduler › Task Scheduler Library › $_task';

  static Future<String> _domain() async {
    final r = await Process.run('/usr/bin/id', ['-u']);
    return 'gui/${r.stdout.toString().trim()}';
  }

  /// Error message, or null on success. Replaces an existing schedule.
  static Future<String?> install(CheckSchedule schedule) async {
    try {
      if (Platform.isMacOS) return await _installMac(schedule);
      if (Platform.isWindows) return await _installWindows(schedule);
      return 'Scheduled checks are only available on macOS and Windows.';
    } catch (e) {
      return '$e';
    }
  }

  static Future<String?> _installMac(CheckSchedule s) async {
    await _dataDir.create(recursive: true);
    final plist = File(_plistPath);
    await plist.parent.create(recursive: true);
    await plist.writeAsString(
      s.launchdPlist(executable: AppInstance.executable, logFile: _launchdLog),
      flush: true,
    );
    final lint = await Process.run('/usr/bin/plutil', ['-lint', plist.path]);
    if (lint.exitCode != 0) {
      return 'The schedule file is invalid: ${_out(lint)}';
    }

    final domain = await _domain();
    await Process.run('/bin/launchctl', ['bootout', '$domain/$_label']);
    var r = await Process.run('/bin/launchctl', [
      'bootstrap',
      domain,
      plist.path,
    ]);
    if (r.exitCode != 0) {
      // "Bootstrap failed: 5" right after a bootout: give launchd a moment.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      r = await Process.run('/bin/launchctl', [
        'bootstrap',
        domain,
        plist.path,
      ]);
    }
    if (r.exitCode != 0) {
      r = await Process.run('/bin/launchctl', ['load', '-w', plist.path]);
    }
    if (r.exitCode != 0) {
      return "launchctl couldn't load the schedule: ${_out(r)}";
    }
    return null;
  }

  static Future<String?> _installWindows(CheckSchedule s) async {
    await _dataDir.create(recursive: true);
    final env = Platform.environment;
    final user = env['USERNAME'] ?? '';
    final domain = env['USERDOMAIN'] ?? '';
    final xml = s.windowsTaskXml(
      executable: AppInstance.executable,
      userId: domain.isEmpty ? user : '$domain\\$user',
      now: DateTime.now(),
    );
    final file = File(_join(_dataDir.path, 'scheduled-check-task.xml'));
    // schtasks reads task XML reliably only as UTF-16 with a byte-order mark.
    await file.writeAsBytes(_utf16le(xml), flush: true);
    final r = await Process.run(_schtasks, [
      '/Create',
      '/TN',
      _task,
      '/XML',
      file.path,
      '/F',
    ]);
    if (r.exitCode != 0) return 'Task Scheduler refused the task: ${_out(r)}';
    return null;
  }

  static List<int> _utf16le(String s) {
    final out = <int>[0xFF, 0xFE];
    for (final u in s.codeUnits) {
      out
        ..add(u & 0xff)
        ..add(u >> 8);
    }
    return out;
  }

  /// Error message, or null on success (also when nothing was installed).
  static Future<String?> remove() async {
    try {
      if (Platform.isMacOS) {
        // File first: if bootout ends this very process (a scheduled run
        // retiring its one-time schedule), the agent must not come back at
        // the next login.
        final f = File(_plistPath);
        if (await f.exists()) await f.delete();
        await Process.run('/bin/launchctl', [
          'bootout',
          '${await _domain()}/$_label',
        ]);
        return null;
      }
      if (Platform.isWindows) {
        if (!await isInstalled()) return null;
        final r = await Process.run(_schtasks, ['/Delete', '/TN', _task, '/F']);
        return r.exitCode == 0 ? null : "Couldn't delete the task: ${_out(r)}";
      }
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Whether the operating system currently has the schedule.
  static Future<bool> isInstalled() async {
    try {
      if (Platform.isMacOS) {
        if (!await File(_plistPath).exists()) return false;
        final r = await Process.run('/bin/launchctl', [
          'print',
          '${await _domain()}/$_label',
        ]);
        return r.exitCode == 0;
      }
      if (Platform.isWindows) {
        final r = await Process.run(_schtasks, ['/Query', '/TN', _task]);
        return r.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  /// Start the scheduled job right now, exactly as the OS would (a test).
  static Future<String?> runNow() async {
    try {
      if (Platform.isMacOS) {
        final r = await Process.run('/bin/launchctl', [
          'kickstart',
          '${await _domain()}/$_label',
        ]);
        return r.exitCode == 0 ? null : "Couldn't start it: ${_out(r)}";
      }
      if (Platform.isWindows) {
        final r = await Process.run(_schtasks, ['/Run', '/TN', _task]);
        return r.exitCode == 0 ? null : "Couldn't start it: ${_out(r)}";
      }
      return 'Not supported on this system.';
    } catch (e) {
      return '$e';
    }
  }

  // ---- doing it by hand ----------------------------------------------------

  static const _winDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  /// Commands that set up the same schedule without the app's button.
  static String manualInstall(CheckSchedule s) {
    final exe = AppInstance.executable;
    if (Platform.isMacOS) {
      return '# 1. Save this file as\n'
          '#    $_plistPath\n'
          '${s.launchdPlist(executable: exe, logFile: _launchdLog)}\n'
          '# 2. Load it into your login session (Terminal):\n'
          'launchctl bootstrap gui/\$(id -u) "$_plistPath"';
    }
    if (Platform.isWindows) {
      final run = '/TR "\\"$exe\\" ${CheckSchedule.argument}"';
      final when = switch (s.kind) {
        ScheduleKind.weekly => '/SC WEEKLY /D ${_winDays[s.weekday - 1]}',
        ScheduleKind.monthly => '/SC MONTHLY /D ${s.dayOfMonth}',
        ScheduleKind.once =>
          '/SC ONCE /SD <date in your Windows date format, e.g. '
              '${s.date?.day ?? 1}/${s.date?.month ?? 1}/${s.date?.year ?? 2026}>',
      };
      return 'rem Command Prompt (not as administrator):\n'
          'schtasks /Create /TN "$_task" $run $when /ST ${s.timeText} /IT /F';
    }
    return '';
  }

  static String get manualCheck => Platform.isMacOS
      ? 'launchctl print gui/\$(id -u)/$_label'
      : 'schtasks /Query /TN "$_task" /V /FO LIST';

  static String get manualRemove => Platform.isMacOS
      ? 'launchctl bootout gui/\$(id -u)/$_label\nrm "$_plistPath"'
      : 'schtasks /Delete /TN "$_task" /F';
}

/// Remembers the vault's data key on this computer so the app (and the
/// scheduled check) can open without typing the master password.
///
/// * **macOS**: a generic password in your login Keychain, written and read
///   with Apple's `security` tool (the secret goes through stdin, never the
///   command line).
/// * **Windows**: a file in `%APPDATA%\mega-checker-app\keys`, encrypted with
///   DPAPI so only your Windows account on this PC can decrypt it.
class DeviceSecrets {
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  static String get storeName => Platform.isMacOS
      ? 'your macOS login Keychain'
      : 'a file only your Windows account can decrypt (DPAPI)';

  static String get deviceName => Platform.isMacOS ? 'this Mac' : 'this PC';

  static const _service = 'mega-checker-app';
  static final _safeChars = RegExp(r'[^A-Za-z0-9._:-]');
  static final _base64 = RegExp(r'^[A-Za-z0-9+/=_-]+$');

  static String _safe(String id) => id.replaceAll(_safeChars, '_');

  static File _winFile(String id) => File(
    _join(
      _join(_dataDir.path, 'keys'),
      '${_safe(id).replaceAll(':', '_')}.bin',
    ),
  );

  /// Stores [secret] (base64 text). True when it was stored and reads back.
  static Future<bool> write(String id, String secret) async {
    if (!_base64.hasMatch(secret)) return false;
    try {
      if (Platform.isMacOS) {
        final p = await Process.start('/usr/bin/security', ['-i']);
        final drained = Future.wait([
          p.stdout.drain<void>(),
          p.stderr.drain<void>(),
        ]);
        p.stdin.writeln(
          'add-generic-password -U -a "${_safe(id)}" -s "$_service" '
          '-l "mega-checker-app remembered key" -w "$secret"',
        );
        await p.stdin.close();
        await p.exitCode;
        await drained;
        return await read(id) == secret;
      }
      if (Platform.isWindows) {
        final blob = _Dpapi.protect(utf8.encode(secret));
        if (blob == null) return false;
        final f = _winFile(id);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(blob, flush: true);
        return await read(id) == secret;
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> read(String id) async {
    try {
      if (Platform.isMacOS) {
        final r = await Process.run('/usr/bin/security', [
          'find-generic-password',
          '-a',
          _safe(id),
          '-s',
          _service,
          '-w',
        ]);
        if (r.exitCode != 0) return null;
        final s = r.stdout.toString().trim();
        return s.isEmpty ? null : s;
      }
      if (Platform.isWindows) {
        final f = _winFile(id);
        if (!await f.exists()) return null;
        final plain = _Dpapi.unprotect(await f.readAsBytes());
        return plain == null ? null : utf8.decode(plain);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> delete(String id) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('/usr/bin/security', [
          'delete-generic-password',
          '-a',
          _safe(id),
          '-s',
          _service,
        ]);
      } else if (Platform.isWindows) {
        final f = _winFile(id);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }
}

// ---- Windows DPAPI (crypt32.dll) ---------------------------------------------

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Utf16> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptProtectDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _CryptUnprotectNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Pointer<Utf16>> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptUnprotectDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);

/// `CryptProtectData` / `CryptUnprotectData` for the current Windows user.
class _Dpapi {
  static const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _protect = _crypt32
      .lookupFunction<_CryptProtectNative, _CryptProtectDart>(
        'CryptProtectData',
      );
  static final _unprotect = _crypt32
      .lookupFunction<_CryptUnprotectNative, _CryptUnprotectDart>(
        'CryptUnprotectData',
      );
  static final _localFree = _kernel32
      .lookupFunction<_LocalFreeNative, _LocalFreeNative>('LocalFree');

  static List<int>? protect(List<int> data) => _run(data, encrypt: true);

  static List<int>? unprotect(List<int> data) => _run(data, encrypt: false);

  static List<int>? _run(List<int> data, {required bool encrypt}) {
    if (data.isEmpty) return null;
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final buffer = calloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buffer;
      final ok = encrypt
          ? _protect(
              input,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _uiForbidden,
              output,
            )
          : _unprotect(
              input,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _uiForbidden,
              output,
            );
      if (ok == 0) return null;
      final result = List<int>.of(
        output.ref.pbData.asTypedList(output.ref.cbData),
      );
      _localFree(output.ref.pbData.cast());
      return result;
    } finally {
      calloc.free(buffer);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
