// Web build: a browser can't start programs or open Finder / Explorer.
import 'cmd_result.dart';

class MegaCmd {
  /// False: MEGAcmd is a desktop program, it can't run inside a browser.
  static bool get isSupported => false;
  static bool get isInstalled => false;

  static String get installHint =>
      'Account checks need the desktop app (macOS or Windows) — MEGAcmd '
      "can't run in a browser.";

  static Future<void> ensureServer() async {}

  static Future<CmdResult?> run(
    String command,
    List<String> args, {
    int timeoutSec = 90,
  }) async => null;
}

class FileManager {
  /// Label of the "show the exported file" action, or null when there's none.
  static String? get revealLabel => null;

  static Future<void> reveal(String path) async {}
}
