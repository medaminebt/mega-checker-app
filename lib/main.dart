import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'csv_import.dart';
import 'mega_service.dart';
import 'models.dart';
import 'paths.dart';

void main() {
  runApp(const MegaKeepAliveApp());
}

// Random pause between accounts so logins don't look like one tight burst.
// Mutable so tests can set them to 0.
int kDelayMinSec = 10;
int kDelayMaxSec = 25;

class MegaKeepAliveApp extends StatelessWidget {
  const MegaKeepAliveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEGA Keep-Alive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.debugAccounts});
  final List<Account>? debugAccounts;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Account>? _accounts;
  String? _csvPath;
  bool _running = false;
  bool _stopRequested = false;
  String? _currentEmail;
  bool _showPasswords = false;
  String _filter = '';
  String? _sortColumn; // null = unsorted, 'status' or 'email'
  bool _sortAsc = true;
  int _runTotal = 0;
  int _runDone = 0;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    if (widget.debugAccounts != null) {
      _accounts = widget.debugAccounts;
      _hydrateResults(_accounts!);
      return;
    }
    // Reload the last CSV, or fall back to the main database file if it exists.
    final last = AppPaths.lastCsvPath ??
        (File(AppPaths.dbPath).existsSync() ? AppPaths.dbPath : null);
    if (last != null && File(last).existsSync()) {
      try {
        final parsed = CsvImport.parseFile(last);
        _hydrateResults(parsed);
        _accounts = parsed;
        _csvPath = last;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _hydrateResults(List<Account> accounts) {
    for (final a in accounts) {
      final n = a.notes.toLowerCase();
      final ok = n.lastIndexOf('login ok');
      final fail = n.lastIndexOf('login failed');
      a.lastResult = (ok == -1 && fail == -1) ? '—' : (ok >= fail ? 'ok' : 'failed');
    }
  }

  static String _fmtNow() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  void _appendNote(Account a, String text) {
    final entry = '[${_fmtNow()}] $text';
    a.notes = a.notes.isEmpty ? entry : '${a.notes} | $entry';
  }

  // ---- persistence -------------------------------------------------------
  bool _saveToSource() {
    final accounts = _accounts;
    if (accounts == null) return false;
    // If no file was imported, persist to the main database CSV so nothing is lost.
    _csvPath ??= AppPaths.dbPath;
    try {
      CsvImport.exportToFile(_csvPath!, accounts);
      AppPaths.lastCsvPath = _csvPath;
      return true;
    } catch (e) {
      _snack('Could not write to CSV: $e', error: true);
      return false;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveToSource);
  }

  // ---- import / export ---------------------------------------------------
  Future<void> _importCsv() async {
    final path = await CsvImport.pickCsvFile();
    if (path == null) return;
    try {
      final parsed = CsvImport.parseFile(path);
      if (parsed.isEmpty) {
        _snack('No valid rows found (need email + password columns).',
            error: true);
        return;
      }
      _hydrateResults(parsed);
      setState(() {
        _accounts = parsed;
        _csvPath = path;
      });
      AppPaths.lastCsvPath = path;
      _snack('Imported ${parsed.length} account(s) from ${path.split('/').last}.');
    } catch (e) {
      _snack('Import failed: $e', error: true);
    }
  }

  Future<void> _exportAs() async {
    final accounts = _accounts;
    if (accounts == null) return;
    final path = await CsvImport.pickSaveCsvFile();
    if (path == null) return;
    final out = path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
    try {
      CsvImport.exportToFile(out, accounts);
      // "Save As" semantics: the exported file becomes the active working file
      // so edits keep saving there and the footer's "Reveal in Finder" button
      // points at the exported folder.
      setState(() => _csvPath = out);
      AppPaths.lastCsvPath = out;
      _snack('Exported ${accounts.length} account(s) to ${out.split('/').last}.');
    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
  }

  /// Open Finder at the given file (selecting it) or, if it doesn't exist yet,
  /// at the app's data folder. Used by the footer "Reveal in Finder" button.
  Future<void> _revealInFinder() async {
    final path = _csvPath;
    try {
      if (path != null && File(path).existsSync()) {
        await Process.run('open', ['-R', path]);
      } else {
        await Process.run('open', [AppPaths.dataDir]);
      }
    } catch (e) {
      _snack('Could not open Finder: $e', error: true);
    }
  }

  // ---- editing -----------------------------------------------------------
  void _addAccount() {
    setState(() {
      _accounts ??= [];
      _accounts!.add(Account(email: '', password: '', notes: ''));
    });
    _saveToSource();
  }

  void _deleteAccount(Account a) {
    final list = _accounts!;
    if (!list.remove(a)) return;
    setState(() {});
    _saveToSource();
    _snack('Deleted ${a.email.isEmpty ? 'row' : a.email}.');
  }

  // ---- running -----------------------------------------------------------
  Future<void> _runAll() async {
    final accounts = _accounts;
    if (accounts == null || _running) return;
    setState(() {
      _running = true;
      _stopRequested = false;
      _runTotal = accounts.length;
      _runDone = 0;
    });
    final rng = Random();
    var ok = 0, failed = 0;

    for (var i = 0; i < accounts.length; i++) {
      if (_stopRequested) break;
      final acct = accounts[i];
      setState(() {
        _currentEmail = acct.email;
        acct.lastResult = 'running';
      });
      LoginResult result;
      try {
        result = await MegaService.keepAlive(acct);
      } catch (e) {
        result = LoginResult(LoginOutcome.error, '$e');
      }
      setState(() {
        _appendNote(acct, result.noteText);
        acct.lastResult = result.ok ? 'ok' : result.chipLabel;
        result.ok ? ok++ : failed++;
        _runDone = i + 1;
      });
      _saveToSource();

      if (i < accounts.length - 1 && !_stopRequested) {
        final delay =
            kDelayMinSec + rng.nextInt(kDelayMaxSec - kDelayMinSec + 1);
        for (var s = 0; s < delay; s++) {
          if (_stopRequested) break;
          setState(() => _currentEmail = '${acct.email} → next in ${delay - s}s');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    final saved = _saveToSource();
    setState(() {
      _running = false;
      _currentEmail = null;
    });
    _snack('Done: $ok logged in, $failed failed.'
        '${saved ? ' Saved.' : ''}');
  }

  Future<void> _runOne(Account acct) async {
    if (_running) return;
    setState(() {
      _running = true;
      _runTotal = 1;
      _runDone = 0;
      _currentEmail = acct.email;
      acct.lastResult = 'running';
    });
    LoginResult result;
    try {
      result = await MegaService.keepAlive(acct);
    } catch (e) {
      result = LoginResult(LoginOutcome.error, '$e');
    }
    setState(() {
      _appendNote(acct, result.noteText);
      acct.lastResult = result.ok ? 'ok' : result.chipLabel;
      _running = false;
      _runDone = 1;
      _currentEmail = null;
    });
    final saved = _saveToSource();
    _snack('${acct.email}: ${result.ok ? 'logged in' : result.message}.'
        '${saved ? ' Saved.' : ''}');
  }

  // ---- helpers -----------------------------------------------------------
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: error ? AppTheme.error : AppTheme.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(14),
      ));
  }

  bool _isFailure(String r) => r != 'ok' && r != 'running' && r != '—';

  // Sort order for the Status column: testing → ok → untested → failed.
  static int _statusRank(String r) {
    switch (r) {
      case 'running':
        return 0;
      case 'ok':
        return 1;
      case '—':
        return 2;
      default:
        return 3; // failed / error
    }
  }

  // Click a column header: same column cycles asc → desc → off; a new column
  // starts at ascending.
  void _cycleSort(String column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _sortAsc = true;
      } else if (_sortAsc) {
        _sortAsc = false;
      } else {
        _sortColumn = null;
      }
    });
  }

  Future<void> _confirmAndDelete(Account a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 34),
        title: const Text('Delete this account?', style: AppTheme.titleMedium),
        content: Text(
          a.email.isEmpty
              ? 'This blank row will be removed.'
              : '“${a.email}” will be removed from the table and the CSV file.',
          textAlign: TextAlign.center,
          style: AppTheme.bodySmall,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteAccount(a);
  }

  // ---- build -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: _accounts == null ? _buildEmpty() : _buildMain(),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      titleSpacing: 20,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_sync, size: 20),
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: Text('MEGA Keep-Alive',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ),
        ],
      ),
      actions: [
        if (_accounts != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Material(
              color: Colors.white.withValues(alpha: _showPasswords ? 0.24 : 0.12),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () =>
                    setState(() => _showPasswords = !_showPasswords),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _showPasswords
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 17,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _showPasswords ? 'Hide passwords' : 'Show passwords',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Card(
        child: Container(
          width: 460,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.table_view_rounded,
                    size: 48, color: AppTheme.primary),
              ),
              const SizedBox(height: 24),
              const Text('No accounts loaded', style: AppTheme.titleLarge),
              const SizedBox(height: 10),
              const Text(
                'Import a CSV with columns email, password, notes — or start '
                'from scratch and add accounts by hand.',
                textAlign: TextAlign.center,
                style: AppTheme.bodySmall,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _importCsv,
                      icon: const Icon(Icons.upload_file,
                          color: AppTheme.warning),
                      label: const Text('Import CSV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _accounts = [];
                          _csvPath = null;
                        });
                        _addAccount();
                      },
                      icon: const Icon(Icons.add, color: AppTheme.success),
                      label: const Text('Start blank'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMain() {
    final accounts = _accounts!;
    final total = accounts.length;
    final ok = accounts.where((a) => a.lastResult == 'ok').length;
    final failed = accounts.where((a) => _isFailure(a.lastResult)).length;
    final pending = accounts.where((a) => a.lastResult == '—').length;

    var filtered = _filter.isEmpty
        ? List<Account>.from(accounts)
        : accounts
            .where((a) =>
                a.email.toLowerCase().contains(_filter.toLowerCase()) ||
                a.notes.toLowerCase().contains(_filter.toLowerCase()))
            .toList();
    if (_sortColumn != null) {
      filtered.sort((a, b) {
        final int c;
        if (_sortColumn == 'email') {
          c = a.email.toLowerCase().compareTo(b.email.toLowerCase());
        } else {
          c = _statusRank(a.lastResult).compareTo(_statusRank(b.lastResult));
        }
        return _sortAsc ? c : -c;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(children: [
            _statCard('Accounts', total, AppTheme.primary,
                Icons.people_alt_rounded),
            const SizedBox(width: 14),
            _statCard(
                'Logged in', ok, AppTheme.success, Icons.check_circle_rounded),
            const SizedBox(width: 14),
            _statCard('Failed', failed, AppTheme.error, Icons.cancel_rounded),
            const SizedBox(width: 14),
            _statCard('Not tested', pending, Colors.blueGrey,
                Icons.remove_circle_outline_rounded),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _running ? null : _runAll,
                      icon: const Icon(Icons.play_arrow_rounded,
                          color: Color(0xFF86EFAC)),
                      label: const Text('Test all logins'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _running ? null : _addAccount,
                      icon: const Icon(Icons.person_add_alt_1,
                          color: AppTheme.success),
                      label: const Text('Add account'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _running ? null : _importCsv,
                      icon: const Icon(Icons.upload_file,
                          color: AppTheme.warning),
                      label: const Text('Import'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _running ? null : _exportAs,
                      icon: const Icon(Icons.download, color: AppTheme.tertiary),
                      label: const Text('Export'),
                    ),
                    if (_running)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error),
                        onPressed: () =>
                            setState(() => _stopRequested = true),
                        icon: const Icon(Icons.stop_rounded,
                            color: Colors.white),
                        label: const Text('Stop'),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 240, child: _searchField()),
            ],
          ),
        ),
        if (_running)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: _runTotal > 0 ? _runDone / _runTotal : null,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Testing $_runDone of $_runTotal — ${_currentEmail ?? ''}',
                    style: AppTheme.bodySmall),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _headerRow(),
                  const Divider(height: 1, color: AppTheme.alternate),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                                _filter.isEmpty
                                    ? 'No accounts yet — “Add account” to begin.'
                                    : 'No accounts match "$_filter"',
                                style: AppTheme.bodySmall))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(
                                height: 1, color: AppTheme.alternate),
                            itemBuilder: (context, i) {
                              final a = filtered[i];
                              return EditableAccountRow(
                                key: ObjectKey(a),
                                account: a,
                                index: i,
                                showPassword: _showPasswords,
                                enabled: !_running,
                                onChanged: _scheduleSave,
                                onTest: () => _runOne(a),
                                onDelete: () => _confirmAndDelete(a),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(children: [
            const Icon(Icons.description_outlined,
                size: 14, color: AppTheme.secondaryText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_csvPath ?? 'unsaved — use Export to choose a file',
                  style: AppTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _revealInFinder,
              icon: const Icon(Icons.folder_open_rounded,
                  size: 15, color: AppTheme.tertiary),
              label: const Text('Reveal in Finder'),
              style: TextButton.styleFrom(
                textStyle: AppTheme.bodySmall,
                foregroundColor: AppTheme.secondaryText,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            Text('${filtered.length}/$total shown', style: AppTheme.bodySmall),
          ]),
        ),
      ],
    );
  }

  static const TextStyle _headerStyle = TextStyle(
      fontFamily: '.AppleSystemUIFont',
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.secondaryText,
      letterSpacing: 0.8);

  // A clickable, sortable column header (label + sort arrow).
  Widget _sortHeader(String label, String column) {
    final active = _sortColumn == column;
    final icon = !active
        ? Icons.unfold_more_rounded
        : (_sortAsc
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded);
    final color = active ? AppTheme.primary : AppTheme.secondaryText;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _cycleSort(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: _headerStyle.copyWith(color: color)),
          const SizedBox(width: 4),
          Icon(icon, size: 15, color: color),
        ]),
      ),
    );
  }

  Widget _headerRow() {
    Widget h(String t) => Text(t, style: _headerStyle);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppTheme.primary.withValues(alpha: 0.07),
          AppTheme.secondary.withValues(alpha: 0.05),
        ]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
            width: 150,
            child: Align(
                alignment: Alignment.centerLeft,
                child: _sortHeader('STATUS', 'status'))),
        Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerLeft,
                child: _sortHeader('EMAIL', 'email'))),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: h('PASSWORD')),
        const SizedBox(width: 12),
        Expanded(flex: 4, child: h('NOTES')),
        const SizedBox(width: 12),
        SizedBox(width: 96, child: h('ACTIONS')),
      ]),
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _filter = v),
      decoration: const InputDecoration(
        hintText: 'Search email / notes…',
        prefixIcon: Icon(Icons.search, size: 20),
      ),
    );
  }

  Widget _statCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1.0)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: AppTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One editable row: email / password / notes are live TextFields that update
/// the account and trigger an auto-save; plus a status chip, test, and delete.
class EditableAccountRow extends StatefulWidget {
  const EditableAccountRow({
    super.key,
    required this.account,
    required this.index,
    required this.showPassword,
    required this.enabled,
    required this.onChanged,
    required this.onTest,
    required this.onDelete,
  });

  final Account account;
  final int index;
  final bool showPassword;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  State<EditableAccountRow> createState() => _EditableAccountRowState();
}

class _EditableAccountRowState extends State<EditableAccountRow> {
  late final TextEditingController _email =
      TextEditingController(text: widget.account.email);
  late final TextEditingController _pass =
      TextEditingController(text: widget.account.password);
  late final TextEditingController _notes =
      TextEditingController(text: widget.account.notes);
  final FocusNode _emailF = FocusNode();
  final FocusNode _passF = FocusNode();
  final FocusNode _notesF = FocusNode();

  @override
  void didUpdateWidget(covariant EditableAccountRow old) {
    super.didUpdateWidget(old);
    // Sync fields changed externally (e.g. notes appended after a test run),
    // but never clobber a field the user is actively typing in.
    if (!_emailF.hasFocus && _email.text != widget.account.email) {
      _email.text = widget.account.email;
    }
    if (!_passF.hasFocus && _pass.text != widget.account.password) {
      _pass.text = widget.account.password;
    }
    if (!_notesF.hasFocus && _notes.text != widget.account.notes) {
      _notes.text = widget.account.notes;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _notes.dispose();
    _emailF.dispose();
    _passF.dispose();
    _notesF.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.index.isOdd
        ? AppTheme.primary.withValues(alpha: 0.02)
        : Colors.white;
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
              width: 150,
              child: Row(children: [
                _statusDot(widget.account.lastResult),
                const SizedBox(width: 8),
                Flexible(child: _resultChip(widget.account.lastResult)),
              ])),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _email,
              focusNode: _emailF,
              enabled: widget.enabled,
              style: AppTheme.bodyMedium,
              decoration: const InputDecoration(hintText: 'email@example.com'),
              onChanged: (v) {
                widget.account.email = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _pass,
              focusNode: _passF,
              enabled: widget.enabled,
              obscureText: !widget.showPassword,
              style: AppTheme.mono,
              decoration: const InputDecoration(hintText: 'password'),
              onChanged: (v) {
                widget.account.password = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: TextField(
              controller: _notes,
              focusNode: _notesF,
              enabled: widget.enabled,
              style: AppTheme.bodySmall,
              decoration: const InputDecoration(hintText: 'notes'),
              onChanged: (v) {
                widget.account.notes = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Row(children: [
              IconButton(
                tooltip: 'Test this account',
                onPressed: widget.enabled ? widget.onTest : null,
                icon: const Icon(Icons.play_arrow_rounded,
                    color: AppTheme.success, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                style: IconButton.styleFrom(
                    backgroundColor: AppTheme.success.withValues(alpha: 0.10)),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Delete row',
                onPressed: widget.enabled ? widget.onDelete : null,
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(String result) {
    Color c;
    if (result == 'ok') {
      c = AppTheme.success;
    } else if (result == 'running') {
      c = AppTheme.primary;
    } else if (result == '—') {
      c = Colors.grey.shade400;
    } else {
      c = AppTheme.error;
    }
    return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _resultChip(String result) {
    Color color;
    IconData icon;
    String label;
    switch (result) {
      case 'ok':
        color = AppTheme.success;
        icon = Icons.check_circle_rounded;
        label = 'OK';
        break;
      case 'running':
        color = AppTheme.primary;
        icon = Icons.hourglass_top_rounded;
        label = 'Testing';
        break;
      case '—':
        color = Colors.blueGrey;
        icon = Icons.remove_circle_outline_rounded;
        label = 'Untested';
        break;
      default:
        color = AppTheme.error;
        icon = Icons.cancel_rounded;
        label = 'Failed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
