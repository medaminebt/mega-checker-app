import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../account_import.dart';
import '../accounts_repository.dart';
import '../app_theme.dart';
import '../csv_import.dart';
import '../format.dart';
import '../mega_service.dart';
import '../models.dart';
import '../prefs.dart';
import '../widgets/account_row.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_bits.dart';
import '../widgets/mega_logo.dart';

// Random pause between accounts so logins don't look like one tight burst.
// Mutable so tests can set them to 0.
int kDelayMinSec = 10;
int kDelayMaxSec = 25;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    this.userEmail,
    this.projectHost,
    this.onSignOut,
    this.onChangeProject,
  });

  final AccountsRepository repository;
  final String? userEmail;
  final String? projectHost;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onChangeProject;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Account> _accounts = [];
  bool _loading = true;
  String? _loadError;
  bool _busy = false; // insert / import in progress

  bool _running = false;
  bool _stopRequested = false;
  int _runTotal = 0;
  int _runDone = 0;
  String? _progress;

  bool _showSecrets = Prefs.showSecrets;
  String _filter = '';
  String? _sortColumn = Prefs.sortColumn;
  bool _sortAsc = Prefs.sortAsc;

  // Edits waiting to be written to Supabase: row id → columns to patch.
  final Map<String, Map<String, dynamic>> _pending = {};
  Timer? _flushTimer;
  Future<bool>? _inFlight;
  bool _flushing = false;
  String? _syncError;

  AccountsRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stopRequested = true;
    _flushTimer?.cancel();
    unawaited(_flush()); // don't lose the last edits
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ---- loading & saving ----------------------------------------------------

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await _repo.fetchAll();
      _safeSetState(() {
        _accounts = list;
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() {
        _loadError = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _flush();
    await _load();
  }

  /// Queue a column patch for [a]; it's written after a short debounce (or
  /// right away with [now]).
  void _queue(Account a, Map<String, dynamic> patch, {bool now = false}) {
    final id = a.id;
    if (id == null) return;
    (_pending[id] ??= {}).addAll(patch);
    _flushTimer?.cancel();
    _flushTimer = Timer(
      now ? Duration.zero : const Duration(milliseconds: 800),
      _flush,
    );
  }

  /// Write all queued patches. If a write is already in flight, wait for it
  /// first (so callers like Sign out never leave edits behind). Failed patches
  /// stay queued (Retry in the footer); a duplicate-email conflict can't be
  /// retried, so it's dropped and the list is reloaded from the database.
  Future<bool> _flush() async {
    _flushTimer?.cancel();
    while (_inFlight != null) {
      await _inFlight;
    }
    if (_pending.isEmpty) return _syncError == null;
    final run = _writePending();
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  Future<bool> _writePending() async {
    _flushing = true;
    _safeSetState(() {});
    final batch = Map.of(_pending);
    _pending.clear();
    String? error;
    var conflict = false;
    for (final e in batch.entries) {
      try {
        await _repo.update(e.key, e.value);
      } catch (err) {
        error = describeError(err);
        if (err is PostgrestException && err.code == '23505') {
          conflict = true;
        } else {
          // Keep it for a retry; edits queued meanwhile win.
          _pending[e.key] = {...e.value, ...?_pending[e.key]};
        }
      }
    }
    _flushing = false;
    _safeSetState(() => _syncError = error);

    if (conflict) {
      _snack(error!, error: true);
      await _load();
    } else if (error == null && _pending.isNotEmpty) {
      _flushTimer = Timer(const Duration(milliseconds: 400), _flush);
    }
    return error == null;
  }

  static void _applyLocal(Account a, Map<String, dynamic> p) {
    if (p.containsKey('password')) a.password = p['password'] as String;
    if (p.containsKey('mega_key')) a.megaKey = p['mega_key'] as String;
    if (p.containsKey('notes')) a.notes = p['notes'] as String;
  }

  void _onFieldChanged(Account a, String column, String value) {
    _queue(a, {
      column: column == 'email' ? Account.normaliseEmail(value) : value,
    });
  }

  // ---- adding / importing --------------------------------------------------

  Set<String> get _emailSet =>
      _accounts.map((a) => Account.normaliseEmail(a.email)).toSet();

  /// Insert new emails and (optionally) update known ones, then report.
  Future<void> _applyImport(
    List<Account> incoming, {
    required bool overwrite,
    String? source,
  }) async {
    final plan = AccountImport.plan(_accounts, incoming, overwrite: overwrite);
    final from = source == null ? '' : ' from $source';
    if (plan.toInsert.isEmpty && plan.toUpdate.isEmpty) {
      _snack(
        'Nothing new to save$from — '
        '${plan.unchanged} account(s) already in your list.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final inserted = await _repo.insertAll(plan.toInsert);
      for (final e in plan.toUpdate.entries) {
        await _repo.update(e.key.id!, e.value);
        _applyLocal(e.key, e.value);
      }
      _safeSetState(() => _accounts.addAll(inserted));
      final parts = [
        if (inserted.isNotEmpty) 'added ${inserted.length}',
        if (plan.toUpdate.isNotEmpty) 'updated ${plan.toUpdate.length}',
        if (plan.unchanged > 0) '${plan.unchanged} unchanged',
      ];
      final msg = parts.join(' · ');
      _snack('${msg[0].toUpperCase()}${msg.substring(1)}$from.');
    } catch (e) {
      _snack(describeError(e), error: true);
      await _load(); // resync whatever did get saved
    } finally {
      _safeSetState(() => _busy = false);
    }
  }

  Future<void> _addAccount() async {
    final a = await showDialog<Account>(
      context: context,
      builder: (_) => AddAccountDialog(existingEmails: _emailSet),
    );
    if (a == null) return;
    await _applyImport([a], overwrite: false);
  }

  Future<void> _pasteList() async {
    final r = await showDialog<PasteListResult>(
      context: context,
      builder: (_) => PasteListDialog(existing: _accounts),
    );
    if (r == null) return;
    await _applyImport(r.accounts, overwrite: r.overwrite);
  }

  Future<void> _importCsv() async {
    final path = await CsvImport.pickCsvFile();
    if (path == null) return;
    final List<Account> parsed;
    try {
      parsed = CsvImport.parseFile(path);
    } catch (e) {
      _snack('Import failed: $e', error: true);
      return;
    }
    if (parsed.isEmpty) {
      _snack(
        'No valid rows found (need email + password columns).',
        error: true,
      );
      return;
    }
    // CSV import only adds new emails; existing accounts are left alone.
    await _applyImport(parsed, overwrite: false, source: path.split('/').last);
  }

  Future<void> _export() async {
    final path = await CsvImport.pickSaveCsvFile();
    if (path == null) return;
    final out = path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
    try {
      CsvImport.exportToFile(out, _accounts);
      _snack(
        'Exported ${_accounts.length} account(s) to ${out.split('/').last}.',
        action: SnackBarAction(
          label: 'Reveal in Finder',
          onPressed: () => Process.run('open', ['-R', out]),
        ),
      );
    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
  }

  Future<void> _delete(Account a) async {
    if (!await confirmDelete(context, a)) return;
    try {
      final id = a.id;
      if (id != null) {
        _pending.remove(id);
        await _repo.delete(id);
      }
      _safeSetState(() => _accounts.remove(a));
      _snack('Deleted ${a.email}.');
    } catch (e) {
      _snack(describeError(e), error: true);
    }
  }

  // ---- checking ------------------------------------------------------------

  /// Log in to one account, then store status, last-login time and storage.
  Future<LoginResult> _check(Account a) async {
    _safeSetState(() => a.running = true);
    LoginResult r;
    try {
      r = await MegaService.keepAlive(a);
    } catch (e) {
      r = LoginResult(LoginOutcome.error, '$e');
    }
    final now = DateTime.now();
    final iso = now.toUtc().toIso8601String();
    final patch = <String, dynamic>{
      'last_checked_at': iso,
      'last_status': r.ok ? 'ok' : 'failed',
      'last_error': r.ok ? null : r.errorText,
    };
    a
      ..running = false
      ..lastCheckedAt = now
      ..lastStatus = r.ok ? 'ok' : 'failed'
      ..lastError = r.ok ? null : r.errorText;
    if (r.ok) {
      patch['last_login_at'] = iso;
      a.lastLoginAt = now;
      final s = r.storage;
      if (s != null) {
        patch['storage_used_bytes'] = s.usedBytes;
        patch['storage_total_bytes'] = s.totalBytes;
        a
          ..storageUsedBytes = s.usedBytes
          ..storageTotalBytes = s.totalBytes;
      }
    }
    _safeSetState(() {});
    _queue(a, patch, now: true);
    return r;
  }

  Future<void> _runAll() async {
    if (_running || _accounts.isEmpty) return;
    await _flush();
    final queue = List<Account>.from(_accounts);
    setState(() {
      _running = true;
      _stopRequested = false;
      _runTotal = queue.length;
      _runDone = 0;
    });
    final rng = Random();
    var ok = 0, failed = 0;

    for (var i = 0; i < queue.length; i++) {
      if (_stopRequested || !mounted) break;
      final a = queue[i];
      _safeSetState(() => _progress = 'checking ${a.email}');
      final r = await _check(a);
      r.ok ? ok++ : failed++;
      _safeSetState(() => _runDone = i + 1);

      if (i < queue.length - 1 && !_stopRequested) {
        final delay =
            kDelayMinSec + rng.nextInt(kDelayMaxSec - kDelayMinSec + 1);
        for (var s = delay; s > 0; s--) {
          if (_stopRequested || !mounted) break;
          _safeSetState(() => _progress = 'next account in ${s}s');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    final saved = await _flush();
    if (!mounted) return;
    final stopped = _stopRequested;
    setState(() {
      _running = false;
      _stopRequested = false;
      _progress = null;
    });
    _snack(
      'Done: $ok logged in, $failed failed${stopped ? ' (stopped early)' : ''}.'
      '${saved ? ' Saved to Supabase.' : ''}',
      error: failed > 0 && ok == 0,
    );
  }

  Future<void> _runOne(Account a) async {
    if (_running) return;
    setState(() {
      _running = true;
      _runTotal = 1;
      _runDone = 0;
      _progress = 'checking ${a.email}';
    });
    final r = await _check(a);
    final saved = await _flush();
    if (!mounted) return;
    setState(() {
      _running = false;
      _runDone = 1;
      _progress = null;
    });
    _snack(
      '${a.email}: ${r.ok ? 'logged in' : r.errorText}.'
      '${saved ? ' Saved.' : ''}',
      error: !r.ok,
    );
  }

  // ---- session -------------------------------------------------------------

  Future<void> _signOut() async {
    if (_running) return;
    await _flush();
    await widget.onSignOut?.call();
  }

  Future<void> _changeProject() async {
    if (_running) return;
    await _flush();
    await widget.onChangeProject?.call();
  }

  // ---- helpers -------------------------------------------------------------

  void _snack(String msg, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          width: 620,
          duration: Duration(seconds: error ? 6 : 4),
          action: action,
          content: Row(
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: error ? AppTheme.dangerSoft : AppTheme.successSoft,
                size: 19,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(msg)),
            ],
          ),
        ),
      );
  }

  static int _statusRank(Account a) {
    switch (a.status) {
      case AccountStatus.running:
        return 0;
      case AccountStatus.ok:
        return 1;
      case AccountStatus.untested:
        return 2;
      case AccountStatus.failed:
        return 3;
    }
  }

  // Click a header: same column cycles asc → desc → off; a new column starts
  // ascending. Remembered with shared_preferences.
  void _cycleSort(String column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _sortAsc = true;
      } else if (_sortAsc) {
        _sortAsc = false;
      } else {
        _sortColumn = null;
        _sortAsc = true;
      }
    });
    Prefs.sortColumn = _sortColumn;
    Prefs.sortAsc = _sortAsc;
  }

  List<Account> _visible() {
    final q = _filter.trim().toLowerCase();
    final list = q.isEmpty
        ? List<Account>.from(_accounts)
        : _accounts
              .where(
                (a) =>
                    a.email.toLowerCase().contains(q) ||
                    a.notes.toLowerCase().contains(q),
              )
              .toList();
    final col = _sortColumn;
    if (col != null) {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      list.sort((a, b) {
        final int c;
        switch (col) {
          case 'email':
            c = a.email.toLowerCase().compareTo(b.email.toLowerCase());
          case 'login':
            c = (a.lastLoginAt ?? epoch).compareTo(b.lastLoginAt ?? epoch);
          default:
            c = _statusRank(a).compareTo(_statusRank(b));
        }
        return _sortAsc ? c : -c;
      });
    }
    return list;
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final who = [
      if (widget.userEmail != null) widget.userEmail!,
      if (widget.projectHost != null) widget.projectHost!,
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppTheme.bgBase,
        border: Border(bottom: BorderSide(color: AppTheme.megaRed, width: 3)),
      ),
      child: Row(
        children: [
          const MegaLogo(size: 36, glow: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MEGA Keep-Alive',
                  style: AppTheme.h3.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (who.isNotEmpty)
                  Text(
                    who,
                    style: AppTheme.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: AppTheme.ghostButton.copyWith(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            onPressed: () {
              setState(() => _showSecrets = !_showSecrets);
              Prefs.showSecrets = _showSecrets;
            },
            icon: Icon(
              _showSecrets
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 17,
            ),
            label: Text(
              _showSecrets ? 'Hide passwords & keys' : 'Show passwords & keys',
            ),
          ),
          const SizedBox(width: 8),
          if (widget.onChangeProject != null)
            IconButton(
              tooltip: 'Supabase project settings',
              onPressed: _running ? null : _changeProject,
              icon: const Icon(Icons.dns_rounded, size: 20),
            ),
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _running ? null : _signOut,
              icon: const Icon(Icons.logout_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) return _errorState();

    final visible = _visible();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stats(),
          const SizedBox(height: 22),
          SectionTitle(
            'Your MEGA accounts',
            subtitle:
                'Logins run through MEGAcmd one account at a time, '
                'with a $kDelayMinSec–$kDelayMaxSec s pause in between. '
                'Edits save to Supabase automatically.',
          ),
          const SizedBox(height: 14),
          _toolbar(),
          if (_running) _progressBar(),
          const SizedBox(height: 12),
          Expanded(child: _table(visible)),
          const SizedBox(height: 10),
          _footer(visible.length),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: AppTheme.megaRed,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Couldn\'t load your accounts',
                  style: AppTheme.h2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                InlineMessage(_loadError!),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                    if (widget.onChangeProject != null)
                      OutlinedButton(
                        style: AppTheme.ghostButton,
                        onPressed: _changeProject,
                        child: const Text('Supabase settings'),
                      ),
                    if (widget.onSignOut != null)
                      OutlinedButton(
                        style: AppTheme.ghostButton,
                        onPressed: _signOut,
                        child: const Text('Sign out'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stats() {
    final total = _accounts.length;
    final ok = _accounts.where((a) => a.status == AccountStatus.ok).length;
    final failed = _accounts
        .where((a) => a.status == AccountStatus.failed)
        .length;
    final untested = _accounts
        .where((a) => a.status == AccountStatus.untested)
        .length;
    var used = 0, quota = 0, measured = 0;
    for (final a in _accounts) {
      final s = a.storage;
      if (s == null) continue;
      used += s.usedBytes;
      quota += s.totalBytes;
      measured++;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: 'Accounts',
              value: '$total',
              dot: AppTheme.ashGrey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Logged in',
              value: '$ok',
              dot: AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Failed',
              value: '$failed',
              dot: AppTheme.megaRed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Not checked',
              value: '$untested',
              dot: AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _StatCard(
              label: 'Total storage',
              value: measured == 0
                  ? '—'
                  : '${Fmt.bytes(used)} / ${Fmt.bytes(quota)}',
              dot: AppTheme.megaBlue,
              caption: measured == 0
                  ? 'Measured on each successful login'
                  : 'Across $measured account${measured == 1 ? '' : 's'}',
              fraction: quota == 0 ? null : used / quota,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final disabled = _running || _busy;
    final compact = AppTheme.ghostButton.copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!_running)
                ElevatedButton.icon(
                  onPressed: _accounts.isEmpty || _busy ? null : _runAll,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Check all accounts'),
                )
              else
                ElevatedButton.icon(
                  onPressed: _stopRequested
                      ? null
                      : () => setState(() => _stopRequested = true),
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: Text(_stopRequested ? 'Stopping…' : 'Stop'),
                ),
              OutlinedButton.icon(
                onPressed: disabled ? null : _addAccount,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add account'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : _pasteList,
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                label: const Text('Paste list'),
              ),
              OutlinedButton.icon(
                style: compact,
                onPressed: disabled ? null : _importCsv,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Import CSV'),
              ),
              OutlinedButton.icon(
                style: compact,
                onPressed: disabled || _accounts.isEmpty ? null : _export,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox.square(
          dimension: 48,
          child: OutlinedButton(
            style: compact.copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            onPressed: disabled ? null : _refresh,
            child: const Tooltip(
              message: 'Reload from Supabase',
              child: Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 260,
          child: TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(
              hintText: 'Search email or notes…',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _runTotal > 0 ? _runDone / _runTotal : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_runDone of $_runTotal done  ·  ${_progress ?? ''}',
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _table(List<Account> visible) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tableHeader(),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? _emptyTable()
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = visible[i];
                      return AccountRow(
                        key: ObjectKey(a),
                        account: a,
                        index: i,
                        showSecrets: _showSecrets,
                        enabled: !_running && !_busy,
                        onFieldChanged: (col, v) => _onFieldChanged(a, col, v),
                        onCheck: () => _runOne(a),
                        onDelete: () => _delete(a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    fontFamily: AppTheme.font,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    color: AppTheme.textMuted,
    letterSpacing: 1.1,
  );

  Widget _sortHeader(String label, String column) {
    final active = _sortColumn == column;
    final icon = !active
        ? Icons.unfold_more_rounded
        : (_sortAsc
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded);
    final color = active ? AppTheme.textPrimary : AppTheme.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => _cycleSort(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: _headerStyle.copyWith(color: color),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 14,
              color: active ? AppTheme.megaRed : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader() {
    Widget h(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(t, style: _headerStyle, overflow: TextOverflow.ellipsis),
    );
    Widget left(Widget w) => Align(alignment: Alignment.centerLeft, child: w);
    return Container(
      color: const Color(0xFF141414),
      padding: AccountCols.padding.copyWith(top: 9, bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: AccountCols.status,
            child: left(_sortHeader('STATUS', 'status')),
          ),
          Expanded(
            flex: AccountCols.emailFlex,
            child: left(_sortHeader('EMAIL', 'email')),
          ),
          const SizedBox(width: AccountCols.gap),
          Expanded(flex: AccountCols.passwordFlex, child: h('PASSWORD')),
          const SizedBox(width: AccountCols.gap),
          Expanded(flex: AccountCols.keyFlex, child: h('MEGA KEY')),
          const SizedBox(width: AccountCols.gap),
          SizedBox(
            width: AccountCols.login,
            child: left(_sortHeader('LAST LOGIN · STORAGE', 'login')),
          ),
          const SizedBox(width: AccountCols.gap),
          Expanded(flex: AccountCols.notesFlex, child: h('NOTES')),
          const SizedBox(width: AccountCols.gap),
          SizedBox(
            width: AccountCols.actions,
            child: Align(alignment: Alignment.centerRight, child: h('ACTIONS')),
          ),
        ],
      ),
    );
  }

  Widget _emptyTable() {
    if (_accounts.isNotEmpty) {
      return Center(
        child: Text(
          'No accounts match "$_filter"',
          style: AppTheme.bodySecondary,
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MegaLogo(
              size: 56,
              circle: AppTheme.megaRed.withValues(alpha: 0.18),
              mark: AppTheme.megaRed,
            ),
            const SizedBox(height: 18),
            const Text('No MEGA accounts yet', style: AppTheme.h2),
            const SizedBox(height: 6),
            const Text(
              'Paste your list of emails & passwords, import a CSV, '
              'or add an account by hand.',
              style: AppTheme.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _busy ? null : _pasteList,
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  label: const Text('Paste list'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addAccount,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(int shown) {
    final Widget sync;
    if (_flushing) {
      sync = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: AppTheme.megaBlueSoft,
            ),
          ),
          SizedBox(width: 8),
          Text('Saving to Supabase…', style: AppTheme.caption),
        ],
      );
    } else if (_syncError != null) {
      sync = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Dot(AppTheme.megaRed),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: _syncError!,
              child: Text(
                'Not saved — $_syncError',
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(color: AppTheme.dangerSoft),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(onPressed: _flush, child: const Text('Retry')),
        ],
      );
    } else {
      sync = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(AppTheme.success),
          SizedBox(width: 8),
          Text('All changes saved to Supabase', style: AppTheme.caption),
        ],
      );
    }
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: sync),
          ),
          const SizedBox(width: 16),
          Text('$shown / ${_accounts.length} shown', style: AppTheme.caption),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.dot,
    this.caption,
    this.fraction,
  });

  final String label;
  final String value;
  final Color dot;
  final String? caption;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Dot(dot),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.h1.copyWith(fontSize: 24),
            ),
            if (fraction != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction!.clamp(0.0, 1.0),
                  minHeight: 5,
                  color: AppTheme.megaBlue,
                ),
              ),
            ],
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(
                caption!,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
