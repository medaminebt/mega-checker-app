// Web build: no processes, no files, no keychain.
import '../schedule.dart';

class AppInstance {
  static bool get isSupported => false;
  static bool get ownsAppLock => false;
  static void enable() {}
  static Future<bool> claim() async => true;
  static Future<bool> acquireChecks() async => true;
  static Future<void> releaseChecks() async {}
  static Future<void> requestScheduledCheck() async {}
  static Future<bool> takeScheduledRequest() async => false;
  static Future<void> logRun(ScheduledRunEntry entry) async {}
  static Future<List<ScheduledRunEntry>> recentRuns({int limit = 5}) async =>
      const [];
  static String get logPath => '';
  static String? debugExecutable;
  static String get executable => '';
  static String? get locationWarning => null;
  static void quit() {}
}

class Scheduler {
  static bool get isSupported => false;
  static String get systemName => '';
  static String get definitionPath => '';
  static Future<String?> install(CheckSchedule schedule) async =>
      'Scheduled checks need the desktop app.';
  static Future<String?> remove() async => null;
  static Future<bool> isInstalled() async => false;
  static Future<String?> runNow() async =>
      'Scheduled checks need the desktop app.';
  static String manualInstall(CheckSchedule schedule) => '';
  static String get manualCheck => '';
  static String get manualRemove => '';
}

class DeviceSecrets {
  static bool get isSupported => false;
  static String get storeName => '';
  static String get deviceName => 'this browser';
  static Future<bool> write(String id, String secret) async => false;
  static Future<String?> read(String id) async => null;
  static Future<void> delete(String id) async {}
}
