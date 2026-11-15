import 'platform/desktop.dart';
import 'prefs.dart';
import 'schedule.dart';

/// Bookkeeping after a scheduled check (in the scheduled copy of the app, or
/// in the open window it handed the check to).
class ScheduledRuns {
  /// Log the run, and retire a one-time schedule whose moment has passed.
  static Future<void> record(ScheduledRunEntry entry) async {
    await AppInstance.logRun(entry);
    final s = CheckSchedule.decode(Prefs.checkSchedule);
    if (s != null &&
        s.kind == ScheduleKind.once &&
        s.nextRun(DateTime.now()) == null) {
      await Prefs.setCheckSchedule(null);
      // Last: on macOS this unloads the very job that may be running us.
      await Scheduler.remove();
    }
  }
}
