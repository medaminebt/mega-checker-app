import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/schedule.dart';

void main() {
  // Wednesday 18 November 2026, 12:00 local time.
  final now = DateTime(2026, 11, 18, 12);

  group('nextRun', () {
    test('weekly: next matching weekday at that time', () {
      const mon = CheckSchedule(
        kind: ScheduleKind.weekly,
        weekday: 1,
        hour: 10,
      );
      expect(mon.nextRun(now), DateTime(2026, 11, 23, 10));

      const wedLater = CheckSchedule(
        kind: ScheduleKind.weekly,
        weekday: 3,
        hour: 13,
      );
      expect(wedLater.nextRun(now), DateTime(2026, 11, 18, 13));

      const wedEarlier = CheckSchedule(
        kind: ScheduleKind.weekly,
        weekday: 3,
        hour: 11,
      );
      expect(wedEarlier.nextRun(now), DateTime(2026, 11, 25, 11));
    });

    test('monthly: this month if still ahead, else next month', () {
      expect(
        const CheckSchedule(
          kind: ScheduleKind.monthly,
          dayOfMonth: 20,
        ).nextRun(now),
        DateTime(2026, 11, 20, 10),
      );
      expect(
        const CheckSchedule(
          kind: ScheduleKind.monthly,
          dayOfMonth: 15,
          hour: 8,
          minute: 30,
        ).nextRun(now),
        DateTime(2026, 12, 15, 8, 30),
      );
      // December → January of the next year.
      expect(
        const CheckSchedule(
          kind: ScheduleKind.monthly,
          dayOfMonth: 1,
        ).nextRun(DateTime(2026, 12, 5)),
        DateTime(2027, 1, 1, 10),
      );
    });

    test('once: the moment itself, or null once it has passed', () {
      final s = CheckSchedule(
        kind: ScheduleKind.once,
        date: DateTime(2026, 12, 1),
        hour: 9,
      );
      expect(s.nextRun(now), DateTime(2026, 12, 1, 9));
      expect(s.nextRun(DateTime(2026, 12, 1, 9, 1)), isNull);
      expect(s.validate(now), isNull);
      expect(s.validate(DateTime(2027)), contains('future'));
      expect(
        const CheckSchedule(kind: ScheduleKind.once).validate(now),
        'Pick a date.',
      );
    });
  });

  test('describe', () {
    expect(
      const CheckSchedule(
        kind: ScheduleKind.weekly,
        weekday: 7,
        hour: 9,
      ).describe(),
      'Every Sunday at 09:00',
    );
    expect(
      const CheckSchedule(
        kind: ScheduleKind.monthly,
        dayOfMonth: 22,
      ).describe(),
      'On the 22nd of every month at 10:00',
    );
    expect(
      CheckSchedule(
        kind: ScheduleKind.once,
        date: DateTime(2026, 12, 1),
        hour: 18,
        minute: 5,
      ).describe(),
      'Once, on Tuesday 1 December 2026 at 18:05',
    );
    expect(CheckSchedule.ordinal(11), '11th');
    expect(CheckSchedule.ordinal(23), '23rd');
  });

  test('encode / decode round-trip', () {
    final s = CheckSchedule(
      kind: ScheduleKind.once,
      date: DateTime(2027, 3, 4),
      hour: 7,
      minute: 45,
    );
    final back = CheckSchedule.decode(s.encode())!;
    expect(back.kind, ScheduleKind.once);
    expect(back.date, DateTime(2027, 3, 4));
    expect(back.timeText, '07:45');
    expect(CheckSchedule.decode('garbage'), isNull);
    expect(CheckSchedule.decode(null), isNull);
  });

  group('macOS LaunchAgent', () {
    String plist(CheckSchedule s) => s.launchdPlist(
      executable: '/Applications/mega checker & co.app/Contents/MacOS/x',
      logFile: '/tmp/launchd.log',
    );

    test('calendar keys per kind', () {
      final weekly = plist(
        const CheckSchedule(kind: ScheduleKind.weekly, weekday: 7, hour: 6),
      );
      expect(weekly, contains('<key>Weekday</key>\n\t\t<integer>0</integer>'));
      expect(weekly, contains('<key>Hour</key>\n\t\t<integer>6</integer>'));
      expect(weekly, contains('<string>--scheduled-check</string>'));
      expect(weekly, contains('mega checker &amp; co.app'));
      expect(weekly, contains(CheckSchedule.launchdLabel));

      final monthly = plist(
        const CheckSchedule(kind: ScheduleKind.monthly, dayOfMonth: 15),
      );
      expect(monthly, contains('<key>Day</key>\n\t\t<integer>15</integer>'));
      expect(monthly, isNot(contains('Weekday')));

      final once = plist(
        CheckSchedule(kind: ScheduleKind.once, date: DateTime(2026, 12, 1)),
      );
      expect(once, contains('<key>Month</key>\n\t\t<integer>12</integer>'));
      expect(once, contains('<key>Day</key>\n\t\t<integer>1</integer>'));
    });

    test('plutil accepts it', () async {
      final dir = await Directory.systemTemp.createTemp('plist');
      try {
        for (final s in [
          const CheckSchedule(kind: ScheduleKind.weekly),
          const CheckSchedule(kind: ScheduleKind.monthly, dayOfMonth: 28),
          CheckSchedule(kind: ScheduleKind.once, date: DateTime(2026, 12, 31)),
        ]) {
          final f = File('${dir.path}/t.plist')..writeAsStringSync(plist(s));
          final r = await Process.run('/usr/bin/plutil', ['-lint', f.path]);
          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        }
      } finally {
        await dir.delete(recursive: true);
      }
    }, skip: !Platform.isMacOS ? 'needs macOS plutil' : false);
  });

  group('Windows task', () {
    String xml(CheckSchedule s) => s.windowsTaskXml(
      executable: r'C:\Apps\mega-checker-app\mega-checker-app.exe',
      userId: r'PC\me',
      now: now,
    );

    test('triggers per kind, start = next run', () {
      final weekly = xml(
        const CheckSchedule(kind: ScheduleKind.weekly, weekday: 1, hour: 10),
      );
      expect(weekly, contains('<Monday />'));
      expect(
        weekly,
        contains('<StartBoundary>2026-11-23T10:00:00</StartBoundary>'),
      );
      expect(weekly, contains('<WeeksInterval>1</WeeksInterval>'));
      expect(weekly, contains('<LogonType>InteractiveToken</LogonType>'));
      expect(weekly, contains('<StartWhenAvailable>true</StartWhenAvailable>'));
      expect(weekly, contains('<Arguments>--scheduled-check</Arguments>'));
      expect(
        weekly,
        contains(
          r'<WorkingDirectory>C:\Apps\mega-checker-app</WorkingDirectory>',
        ),
      );
      expect(weekly, contains(r'<UserId>PC\me</UserId>'));

      final monthly = xml(
        const CheckSchedule(kind: ScheduleKind.monthly, dayOfMonth: 15),
      );
      expect(monthly, contains('<Day>15</Day>'));
      expect(monthly, contains('<January /><February />'));
      expect(monthly, contains('<December />'));

      final once = xml(
        CheckSchedule(
          kind: ScheduleKind.once,
          date: DateTime(2026, 12, 1),
          hour: 9,
          minute: 30,
        ),
      );
      expect(once, contains('<TimeTrigger>'));
      expect(
        once,
        contains('<StartBoundary>2026-12-01T09:30:00</StartBoundary>'),
      );
    });

    test(
      'well-formed XML',
      () async {
        final dir = await Directory.systemTemp.createTemp('task');
        try {
          for (final s in [
            const CheckSchedule(kind: ScheduleKind.weekly),
            const CheckSchedule(kind: ScheduleKind.monthly),
            CheckSchedule(kind: ScheduleKind.once, date: DateTime(2026, 12, 1)),
          ]) {
            // Written as UTF-8 here, so drop the UTF-16 declaration for xmllint.
            final f = File('${dir.path}/t.xml')
              ..writeAsStringSync(
                xml(s).replaceFirst('encoding="UTF-16"', 'encoding="UTF-8"'),
              );
            final r = await Process.run('xmllint', ['--noout', f.path]);
            expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          }
        } finally {
          await dir.delete(recursive: true);
        }
      },
      skip: !File('/usr/bin/xmllint').existsSync() ? 'needs xmllint' : false,
    );
  });

  test('run log entries round-trip and summarise', () {
    final e = ScheduledRunEntry(
      at: DateTime(2026, 11, 16, 10),
      ok: 12,
      failed: 1,
    );
    final back = ScheduledRunEntry.fromJson(
      '{"at":"${e.at.toUtc().toIso8601String()}","ok":12,"failed":1}',
    )!;
    expect(back.at, e.at);
    expect(back.summary, '12 logged in, 1 failed');
    expect(
      ScheduledRunEntry(at: e.at, note: 'Waiting for you: signed out').summary,
      'Waiting for you: signed out',
    );
    expect(ScheduledRunEntry.fromJson('nope'), isNull);
  });
}
