import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../format.dart';
import '../mega_service.dart';
import '../platform/desktop.dart';
import '../prefs.dart';
import '../schedule.dart';
import '../security/security_controller.dart';
import 'dialogs.dart';
import 'form_bits.dart';

Future<void> showScheduleDialog(
  BuildContext context, {
  SecurityController? security,
}) => showDialog<void>(
  context: context,
  builder: (_) => ScheduleDialog(security: security),
);

/// Header calendar button (desktop): pick weekly / monthly / a date, save it
/// to launchd or Task Scheduler, test it, read how it works.
class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({super.key, this.security});

  final SecurityController? security;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  late CheckSchedule _draft;
  CheckSchedule? _saved;
  bool _installed = false;
  bool? _remembered;
  List<ScheduledRunEntry> _runs = const [];
  bool _busy = false;
  bool _loading = true;
  String? _message;
  bool _messageIsError = false;

  SecurityController? get _security => widget.security;

  @override
  void initState() {
    super.initState();
    _saved = CheckSchedule.decode(Prefs.checkSchedule);
    _draft =
        _saved ??
        const CheckSchedule(
          kind: ScheduleKind.weekly,
          weekday: DateTime.monday,
          hour: 10,
        );
    _refresh();
  }

  Future<void> _refresh() async {
    final installed = await Scheduler.isInstalled();
    final runs = await AppInstance.recentRuns(limit: 4);
    final remembered = await _security?.isRemembered();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _runs = runs;
      _remembered = remembered;
      _loading = false;
    });
  }

  void _say(String? text, {bool error = false}) => setState(() {
    _message = text;
    _messageIsError = error;
  });

  Future<void> _save() async {
    final problem = _draft.validate(DateTime.now());
    if (problem != null) {
      _say(problem, error: true);
      return;
    }
    setState(() => _busy = true);
    final sec = _security;
    if (sec != null && sec.canRemember && _remembered != true) {
      final err = await sec.setRemembered(true);
      if (err != null) {
        setState(() => _busy = false);
        _say(
          "Couldn't remember the master password on this computer, which "
          'scheduled checks need: $err',
          error: true,
        );
        return;
      }
    }
    final err = await Scheduler.install(_draft);
    if (err == null) await Prefs.setCheckSchedule(_draft.encode());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _saved = _draft;
    });
    await _refresh();
    final next = _draft.nextRun(DateTime.now());
    _say(
      err ??
          'Saved. Next check: ${next == null ? '—' : _when(next)}. '
              'You can close the app; the system will start it.',
      error: err != null,
    );
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final err = await Scheduler.remove();
    if (err == null) await Prefs.setCheckSchedule(null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _saved = null;
    });
    await _refresh();
    _say(err ?? 'Schedule removed.', error: err != null);
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    final err = await Scheduler.runNow();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      err ??
          'Started, exactly as the system will. Because this window is '
              'open, the check is handed over to it: it starts here within '
              'about 30 seconds.',
      error: err != null,
    );
  }

  static String _when(DateTime d) =>
      '${CheckSchedule.weekdayNames[d.weekday - 1].substring(0, 3)} '
      '${Fmt.dateTime(d)}';

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _draft.hour, minute: _draft.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) {
      setState(() => _draft = _draft.copyWith(hour: t.hour, minute: t.minute));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      initialDate: _draft.date != null && !_draft.date!.isBefore(now)
          ? _draft.date!
          : DateTime(now.year, now.month, now.day + 1),
    );
    if (d != null) setState(() => _draft = _draft.copyWith(date: d));
  }

  // ---- pieces --------------------------------------------------------------

  Widget _status() {
    final saved = _saved;
    final on = _installed && saved != null;
    final next = saved?.nextRun(DateTime.now());
    final color = on ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.event_available_rounded : Icons.event_busy_rounded,
                size: 18,
                color: on ? AppTheme.successSoft : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loading
                      ? 'Checking the schedule…'
                      : on
                      ? '${saved.describe()}${next == null ? '' : '  ·  next: ${_when(next)}'}'
                      : _installed
                      ? 'A schedule is installed, but this app has no record '
                            'of it. Save again or remove it.'
                      : 'No scheduled checks.',
                  style: AppTheme.body,
                ),
              ),
            ],
          ),
          if (_runs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Recent scheduled checks', style: AppTheme.caption),
            const SizedBox(height: 4),
            for (final r in _runs)
              Text(
                '${Fmt.dateTime(r.at)}   ${r.summary}',
                style: AppTheme.caption.copyWith(color: AppTheme.textPrimary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _form() {
    final d = _draft;
    Widget field(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [FieldLabel(label), child],
    );

    final Widget dayField = switch (d.kind) {
      ScheduleKind.weekly => field(
        'Day',
        DropdownButtonFormField<int>(
          initialValue: d.weekday,
          items: [
            for (var i = 1; i <= 7; i++)
              DropdownMenuItem(
                value: i,
                child: Text(CheckSchedule.weekdayNames[i - 1]),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() => _draft = d.copyWith(weekday: v)),
        ),
      ),
      ScheduleKind.monthly => field(
        'Day of the month',
        DropdownButtonFormField<int>(
          initialValue: d.dayOfMonth,
          items: [
            for (var i = 1; i <= 28; i++)
              DropdownMenuItem(value: i, child: Text(CheckSchedule.ordinal(i))),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() => _draft = d.copyWith(dayOfMonth: v)),
        ),
      ),
      ScheduleKind.once => field(
        'Date',
        OutlinedButton.icon(
          style: AppTheme.ghostButton,
          onPressed: _busy ? null : _pickDate,
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(
            d.date == null ? 'Pick a date' : CheckSchedule.longDate(d.date!),
          ),
        ),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('How often'),
        SegmentedButton<ScheduleKind>(
          segments: const [
            ButtonSegment(
              value: ScheduleKind.weekly,
              label: Text('Weekly'),
              icon: Icon(Icons.view_week_rounded, size: 16),
            ),
            ButtonSegment(
              value: ScheduleKind.monthly,
              label: Text('Monthly'),
              icon: Icon(Icons.calendar_view_month_rounded, size: 16),
            ),
            ButtonSegment(
              value: ScheduleKind.once,
              label: Text('On a date'),
              icon: Icon(Icons.event_rounded, size: 16),
            ),
          ],
          selected: {d.kind},
          showSelectedIcon: false,
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() => _draft = d.copyWith(kind: s.first)),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 3, child: dayField),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: field(
                'Time',
                OutlinedButton.icon(
                  style: AppTheme.ghostButton,
                  onPressed: _busy ? null : _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(d.timeText),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(d.describe(), style: AppTheme.caption),
      ],
    );
  }

  Widget _check(bool ok, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 16,
          color: ok ? AppTheme.successSoft : AppTheme.dangerSoft,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTheme.caption)),
        ?action,
      ],
    ),
  );

  Widget _requirements() {
    final sec = _security;
    final where = AppInstance.locationWarning;
    final device = sec?.deviceName ?? 'this computer';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('For it to work'),
        _check(
          where == null,
          where ?? 'The schedule starts this copy: ${AppInstance.executable}',
        ),
        if (sec != null)
          _check(
            _remembered == true,
            _remembered == true
                ? 'Master password remembered on $device '
                      '(${sec.rememberStoreName}).'
                : 'The master password must be remembered on $device so the '
                      'check can open your passwords on its own. Saving the '
                      'schedule turns this on.',
          ),
        _check(
          MegaService.isInstalled,
          MegaService.isInstalled
              ? 'MEGAcmd is installed.'
              : 'MEGAcmd is missing. Install it first (see README).',
        ),
        _check(
          true,
          'Stay signed in to the app. The computer must be on and you must be '
          'logged in to it at that time. ${_missedRunNote()}',
        ),
      ],
    );
  }

  static String _missedRunNote() => Scheduler.systemName.startsWith('launchd')
      ? 'If the Mac is asleep, the check runs when it wakes up; if it was '
            'off, that check is skipped.'
      : 'If the PC was asleep or off, the check runs as soon as possible '
            'after you sign in again.';

  Widget _code(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTheme.caption)),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 15),
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgBase,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: SelectableText(
            text,
            style: AppTheme.mono.copyWith(fontSize: 11.5, height: 1.45),
          ),
        ),
      ],
    ),
  );

  Widget _howItWorks() {
    final mac = Scheduler.systemName.startsWith('launchd');
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text('How it works, and doing it by hand', style: AppTheme.body),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save hands the schedule to ${Scheduler.systemName}. At that '
            'time it starts the app with ${CheckSchedule.argument}: the app '
            'opens a window, checks every account (same pauses as "Check all '
            'accounts"), saves the results to Supabase and quits 15 seconds '
            'later. That also counts as Supabase activity, so a free project '
            "doesn't pause.\n\n"
            'If the app is already open, nothing new starts: the open window '
            'runs the check instead. If something needs you (signed out, a '
            '2FA code, the master password), the window stays open and '
            'waits.\n\n'
            '${mac ? 'The schedule is a LaunchAgent file' : 'The schedule is a task in'}: '
            '${Scheduler.definitionPath}\n'
            'Log of scheduled checks: ${AppInstance.logPath}',
            style: AppTheme.caption,
          ),
          _code(
            mac
                ? 'Set it up by hand (Terminal)'
                : 'Set it up by hand (Command Prompt)',
            Scheduler.manualInstall(_draft),
          ),
          _code('See if it is installed', Scheduler.manualCheck),
          _code('Remove it by hand', Scheduler.manualRemove),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final changed = _saved == null || _saved!.encode() != _draft.encode();
    return MegaDialog(
      icon: Icons.event_repeat_rounded,
      iconColor: AppTheme.megaBlue,
      title: 'Scheduled checks',
      width: 620,
      actions: [
        if (_installed)
          TextButton(
            onPressed: _busy ? null : _remove,
            child: const Text('Remove schedule'),
          ),
        if (_installed)
          OutlinedButton.icon(
            style: AppTheme.ghostButton,
            onPressed: _busy ? null : _test,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Test now'),
          ),
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _busy || (!changed && _installed) ? null : _save,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: Text(_installed ? 'Save changes' : 'Save schedule'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Let the computer check all your MEGA accounts by itself, without '
            'opening the app.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: 14),
          _status(),
          const SizedBox(height: 18),
          _form(),
          const SizedBox(height: 18),
          _requirements(),
          _howItWorks(),
          if (_message != null) ...[
            const SizedBox(height: 6),
            InlineMessage(_message!, error: _messageIsError),
          ],
        ],
      ),
    );
  }
}
