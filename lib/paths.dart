import 'dart:convert';
import 'dart:io';

/// App support folder + a tiny config file that remembers the last CSV you
/// opened, so the app can reload it automatically next launch.
class AppPaths {
  static String get dataDir {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = '$home/Library/Application Support/MEGAKeepAlive';
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  static String get _configPath => '$dataDir/config.json';

  /// Default "database" CSV — where accounts are saved when you start from
  /// scratch (no file imported), so they persist across launches.
  static String get dbPath => '$dataDir/accounts.csv';

  static String? get lastCsvPath {
    final f = File(_configPath);
    if (!f.existsSync()) return null;
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return m['lastCsvPath'] as String?;
    } catch (_) {
      return null;
    }
  }

  static set lastCsvPath(String? path) {
    File(_configPath).writeAsStringSync(jsonEncode({'lastCsvPath': path}));
  }
}
