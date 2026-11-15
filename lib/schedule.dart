import 'dart:convert';

/// When the scheduled "check all accounts" runs.
enum ScheduleKind { weekly, monthly, once }

/// A scheduled check, as picked in the *Scheduled checks* dialog.
///
/// The operating system starts the app with [argument] at that time:
/// a LaunchAgent on macOS (`launchd`), a task in Task Scheduler on Windows.
/// The app then checks every account and quits by itself.
class CheckSchedule {
  const CheckSchedule({
    required this.kind,
    this.weekday = DateTime.monday,
    this.dayOfMonth = 1,
    this.date,
    this.hour = 10,
    this.minute = 0,
  });

  final ScheduleKind kind;

  /// Weekly: [DateTime.monday] (1) … [DateTime.sunday] (7).
  final int weekday;

  /// Monthly: 1–28, so it exists in every month.
  final int dayOfMonth;

  /// Once: the day (local time; only year / month / day are used).
  final DateTime? date;

  final int hour;
  final int minute;

  /// Command-line flag that starts a scheduled run.
  static const argument = '--scheduled-check';

  /// macOS LaunchAgent label (also the plist file name).
  static const launchdLabel = 'com.megakeepalive.scheduled-check';

  /// Windows Task Scheduler task name.
  static const windowsTaskName = 'mega-checker-app scheduled check';

  static const weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // ---- persistence ---------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'weekday': weekday,
    'day_of_month': dayOfMonth,
    if (date != null)
      'date':
          '${date!.year.toString().padLeft(4, '0')}-${_two(date!.month)}-${_two(date!.day)}',
    'hour': hour,
    'minute': minute,
  };

  String encode() => jsonEncode(toJson());

  static CheckSchedule? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final kind = ScheduleKind.values.byName(m['kind'] as String);
      final d = m['date'] == null ? null : DateTime.parse(m['date'] as String);
      return CheckSchedule(
        kind: kind,
        weekday: (m['weekday'] as num?)?.toInt() ?? DateTime.monday,
        dayOfMonth: (m['day_of_month'] as num?)?.toInt() ?? 1,
        date: d == null ? null : DateTime(d.year, d.month, d.day),
        hour: (m['hour'] as num?)?.toInt() ?? 10,
        minute: (m['minute'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  CheckSchedule copyWith({
    ScheduleKind? kind,
    int? weekday,
    int? dayOfMonth,
    DateTime? date,
    int? hour,
    int? minute,
  }) => CheckSchedule(
    kind: kind ?? this.kind,
    weekday: weekday ?? this.weekday,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    date: date ?? this.date,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  // ---- text ----------------------------------------------------------------

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get timeText => '${_two(hour)}:${_two(minute)}';

  static String ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  /// `Monday 1 December 2026`
  static String longDate(DateTime d) =>
      '${weekdayNames[d.weekday - 1]} ${d.day} ${monthNames[d.month - 1]} '
      '${d.year}';

  /// `Every Monday at 10:00`, `On the 15th of every month at 10:00`,
  /// `Once, on Monday 1 December 2026 at 10:00`.
  String describe() => switch (kind) {
    ScheduleKind.weekly => 'Every ${weekdayNames[weekday - 1]} at $timeText',
    ScheduleKind.monthly =>
      'On the ${ordinal(dayOfMonth)} of every month at $timeText',
    ScheduleKind.once =>
      date == null
          ? 'Once (no date picked)'
          : 'Once, on ${longDate(date!)} at $timeText',
  };

  /// Problem with the picked values, or null when they're fine.
  String? validate(DateTime now) {
    if (kind == ScheduleKind.once) {
      if (date == null) return 'Pick a date.';
      if (nextRun(now) == null) return 'Pick a date and time in the future.';
    }
    if (kind == ScheduleKind.monthly && (dayOfMonth < 1 || dayOfMonth > 28)) {
      return 'Pick a day between 1 and 28.';
    }
    return null;
  }

  // ---- timing --------------------------------------------------------------

  /// The next time this schedule fires after [now] (local time), or null for
  /// a one-time schedule whose moment has passed. Built from calendar fields
  /// (not by adding hours), so daylight-saving changes don't shift it.
  DateTime? nextRun(DateTime now) {
    switch (kind) {
      case ScheduleKind.weekly:
        for (var i = 0; i <= 7; i++) {
          final c = DateTime(now.year, now.month, now.day + i, hour, minute);
          if (c.weekday == weekday && c.isAfter(now)) return c;
        }
        return null; // unreachable
      case ScheduleKind.monthly:
        for (var i = 0; i <= 1; i++) {
          final c = DateTime(now.year, now.month + i, dayOfMonth, hour, minute);
          if (c.isAfter(now)) return c;
        }
        return null; // unreachable
      case ScheduleKind.once:
        final d = date;
        if (d == null) return null;
        final c = DateTime(d.year, d.month, d.day, hour, minute);
        return c.isAfter(now) ? c : null;
    }
  }

  // ---- macOS: launchd LaunchAgent -------------------------------------------

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// `~/Library/LaunchAgents/com.megakeepalive.scheduled-check.plist`.
  ///
  /// launchd calendar intervals have no year, so a one-time schedule is
  /// written as "every year on that day" and the app removes the agent after
  /// it has run.
  String launchdPlist({required String executable, required String logFile}) {
    final interval = <String, int>{
      if (kind == ScheduleKind.weekly) 'Weekday': weekday % 7, // 0 = Sunday
      if (kind == ScheduleKind.monthly) 'Day': dayOfMonth,
      if (kind == ScheduleKind.once && date != null) ...{
        'Month': date!.month,
        'Day': date!.day,
      },
      'Hour': hour,
      'Minute': minute,
    };
    final dict = interval.entries
        .map(
          (e) => '\t\t<key>${e.key}</key>\n\t\t<integer>${e.value}</integer>\n',
        )
        .join();
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Created by mega-checker-app: ${_xml(describe())}.
     Remove it from the app (Scheduled checks > Remove schedule). -->
<plist version="1.0">
<dict>
\t<key>Label</key>
\t<string>$launchdLabel</string>
\t<key>ProgramArguments</key>
\t<array>
\t\t<string>${_xml(executable)}</string>
\t\t<string>$argument</string>
\t</array>
\t<key>StartCalendarInterval</key>
\t<dict>
$dict\t</dict>
\t<key>ProcessType</key>
\t<string>Interactive</string>
\t<key>StandardErrorPath</key>
\t<string>${_xml(logFile)}</string>
</dict>
</plist>
''';
  }

  // ---- Windows: Task Scheduler ----------------------------------------------

  static String _windowsTime(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}:00';

  /// Task Scheduler XML for `schtasks /Create /XML`. Runs only while you're
  /// signed in to Windows (the app has a window), catches up after a missed
  /// start (PC asleep or off), and never starts a second copy.
  String windowsTaskXml({
    required String executable,
    required String userId,
    required DateTime now,
  }) {
    final start = nextRun(now) ?? now;
    final boundary = '<StartBoundary>${_windowsTime(start)}</StartBoundary>';
    final String trigger;
    switch (kind) {
      case ScheduleKind.weekly:
        trigger =
            '''
    <CalendarTrigger>
      $boundary
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <DaysOfWeek>
          <${weekdayNames[weekday - 1]} />
        </DaysOfWeek>
        <WeeksInterval>1</WeeksInterval>
      </ScheduleByWeek>
    </CalendarTrigger>''';
      case ScheduleKind.monthly:
        final months = monthNames.map((m) => '<$m />').join();
        trigger =
            '''
    <CalendarTrigger>
      $boundary
      <Enabled>true</Enabled>
      <ScheduleByMonth>
        <DaysOfMonth>
          <Day>$dayOfMonth</Day>
        </DaysOfMonth>
        <Months>$months</Months>
      </ScheduleByMonth>
    </CalendarTrigger>''';
      case ScheduleKind.once:
        trigger =
            '''
    <TimeTrigger>
      $boundary
      <Enabled>true</Enabled>
    </TimeTrigger>''';
    }
    final sep = executable.lastIndexOf('\\');
    final workDir = sep > 0 ? executable.substring(0, sep) : '';
    return '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>${_xml('Checks every MEGA account with mega-checker-app: ${describe()}. Remove it from the app (Scheduled checks > Remove schedule).')}</Description>
  </RegistrationInfo>
  <Triggers>
$trigger
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>${_xml(userId)}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <ExecutionTimeLimit>PT4H</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>${_xml(executable)}</Command>
      <Arguments>$argument</Arguments>
      <WorkingDirectory>${_xml(workDir)}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
''';
  }
}

/// One line of the scheduled-check log (shown in the dialog).
class ScheduledRunEntry {
  const ScheduledRunEntry({
    required this.at,
    this.ok = 0,
    this.failed = 0,
    this.stopped = false,
    this.note,
  });

  final DateTime at;
  final int ok;
  final int failed;
  final bool stopped;

  /// Why it couldn't run, or how it was handled ("handed to the open app").
  final String? note;

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'ok': ok,
    'failed': failed,
    if (stopped) 'stopped': true,
    if (note != null) 'note': note,
  };

  static ScheduledRunEntry? fromJson(String line) {
    try {
      final m = jsonDecode(line) as Map<String, dynamic>;
      return ScheduledRunEntry(
        at: DateTime.parse(m['at'] as String).toLocal(),
        ok: (m['ok'] as num?)?.toInt() ?? 0,
        failed: (m['failed'] as num?)?.toInt() ?? 0,
        stopped: m['stopped'] == true,
        note: m['note'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String get summary {
    final n = note;
    if (ok == 0 && failed == 0 && n != null) return n;
    final s =
        '$ok logged in, $failed failed${stopped ? ' (stopped early)' : ''}';
    return n == null ? s : '$s · $n';
  }
}
