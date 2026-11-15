import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account_import.dart';
import '../app_theme.dart';
import '../links.dart';
import '../models.dart';
import 'form_bits.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Dialog chrome shared by the app's dialogs: title row with an icon,
/// content, and right-aligned actions.
class MegaDialog extends StatelessWidget {
  const MegaDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 480,
    this.iconColor = AppTheme.megaRed,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: AppTheme.h2)),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add one account
// ---------------------------------------------------------------------------

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key, required this.existingEmails});

  /// Normalised emails already in the list (to flag duplicates).
  final Set<String> existingEmails;

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _upload = TextEditingController();
  final _notes = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _key.dispose();
    _upload.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final email = Account.normaliseEmail(_email.text);
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (widget.existingEmails.contains(email)) {
      setState(() => _error = '$email is already in your list.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter the MEGA password.');
      return;
    }
    final upload = _upload.text.trim();
    if (upload.isNotEmpty && Links.webUri(upload) == null) {
      setState(
        () => _error =
            'The upload folder URL should be a web link, e.g. '
            'https://mega.nz/filerequest/…',
      );
      return;
    }
    Navigator.pop(
      context,
      Account(
        email: email,
        password: _password.text,
        megaKey: _key.text.trim(),
        uploadFolderUrl: upload,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MegaDialog(
      icon: Icons.person_add_alt_1_rounded,
      title: 'Add MEGA account',
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add account'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Email'),
          TextField(
            controller: _email,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'account@example.com'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Password'),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: AppTheme.mono,
            decoration: InputDecoration(
              hintText: 'MEGA password',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show' : 'Hide',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const FieldLabel('MEGA key (optional)'),
          TextField(
            controller: _key,
            style: AppTheme.mono,
            decoration: const InputDecoration(
              hintText: 'Recovery key — paste it here',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Upload folder URL (optional)'),
          TextField(
            controller: _upload,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://mega.nz/filerequest/…',
              prefixIcon: Icon(Icons.drive_folder_upload_rounded, size: 18),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Notes (optional)'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            style: AppTheme.body.copyWith(fontSize: 13.5),
            decoration: const InputDecoration(
              hintText: 'e.g. backup account',
              contentPadding: EdgeInsets.all(12),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            InlineMessage(_error!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paste a list of email / password lines
// ---------------------------------------------------------------------------

class PasteListResult {
  PasteListResult(this.accounts, this.overwrite);

  final List<Account> accounts;

  /// Update the password of emails that are already in the list.
  final bool overwrite;
}

class PasteListDialog extends StatefulWidget {
  const PasteListDialog({super.key, required this.existing});

  final List<Account> existing;

  @override
  State<PasteListDialog> createState() => _PasteListDialogState();
}

class _PasteListDialogState extends State<PasteListDialog> {
  final _text = TextEditingController();
  bool _overwrite = true;
  PastedList _parsed = PastedList(const [], const [], 0);

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      setState(() => _parsed = AccountImport.parsePastedList(_text.text));
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = AccountImport.plan(
      widget.existing,
      _parsed.accounts,
      overwrite: _overwrite,
    );
    final known = _parsed.accounts.length - plan.toInsert.length;
    final work = plan.toInsert.length + plan.toUpdate.length;
    final skipped = _parsed.skippedLines;

    return MegaDialog(
      icon: Icons.playlist_add_rounded,
      title: 'Paste a list of accounts',
      width: 620,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: work == 0
              ? null
              : () => Navigator.pop(
                  context,
                  PasteListResult(_parsed.accounts, _overwrite),
                ),
          icon: const Icon(Icons.cloud_upload_rounded, size: 18),
          label: Text(
            work == 0
                ? 'Nothing to save'
                : 'Save ${plan.toInsert.length} new'
                      '${plan.toUpdate.isEmpty ? '' : ' · update ${plan.toUpdate.length}'}',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'One account per line. Email first, then the password, separated by '
            'a colon, comma, semicolon, tab or space.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 10,
            maxLines: 14,
            style: AppTheme.mono.copyWith(height: 1.5),
            decoration: const InputDecoration(
              hintText:
                  'first@gmail.com:Password1\n'
                  'second@gmail.com,Password2\n'
                  'third@outlook.com Password3',
              contentPadding: EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                '${_parsed.accounts.length} detected',
                AppTheme.textSecondary,
                AppTheme.textMuted,
              ),
              _pill(
                '${plan.toInsert.length} new',
                AppTheme.successSoft,
                AppTheme.success,
              ),
              if (known > 0)
                _pill(
                  '$known already in list',
                  AppTheme.megaBlueSoft,
                  AppTheme.megaBlue,
                ),
              if (_parsed.duplicates > 0)
                _pill(
                  '${_parsed.duplicates} repeated',
                  AppTheme.textSecondary,
                  AppTheme.textMuted,
                ),
              if (skipped.isNotEmpty)
                _pill(
                  'skipped line${skipped.length == 1 ? '' : 's'} '
                  '${skipped.take(8).join(', ')}${skipped.length > 8 ? '…' : ''}',
                  AppTheme.dangerSoft,
                  AppTheme.megaRed,
                ),
            ],
          ),
          if (known > 0) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => setState(() => _overwrite = !_overwrite),
              child: Row(
                children: [
                  Checkbox(
                    value: _overwrite,
                    onChanged: (v) => setState(() => _overwrite = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'Update the password of accounts already in the list',
                      style: AppTheme.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, Color fg, Color tint) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tint.withValues(alpha: 0.4)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.font,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Edit the notes of one account
// ---------------------------------------------------------------------------

/// Big multi-line editor for an account's notes. Returns the new text, or
/// null when cancelled.
Future<String?> showNotesDialog(
  BuildContext context, {
  required String email,
  required String notes,
}) => showDialog<String>(
  context: context,
  builder: (_) => NotesDialog(email: email, initial: notes),
);

class NotesDialog extends StatefulWidget {
  const NotesDialog({super.key, required this.email, required this.initial});

  final String email;
  final String initial;

  @override
  State<NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<NotesDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _text.text.trim());

  @override
  Widget build(BuildContext context) {
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final changed = _text.text.trim() != widget.initial.trim();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: MegaDialog(
        icon: Icons.edit_note_rounded,
        title: 'Notes',
        width: 620,
        actions: [
          OutlinedButton(
            style: AppTheme.ghostButton,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: changed ? _save : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save notes'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.email,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySecondary,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 10,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: AppTheme.body.copyWith(height: 1.5),
              decoration: const InputDecoration(
                hintText:
                    'Anything worth remembering about this account — what '
                    'you store there, recovery hints, renewal dates…',
                contentPadding: EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_text.text.length} characters  ·  '
              '${apple ? '⌘' : 'Ctrl'}+Enter to save',
              textAlign: TextAlign.right,
              style: AppTheme.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm delete
// ---------------------------------------------------------------------------

Future<bool> confirmDelete(BuildContext context, Account a) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => MegaDialog(
      icon: Icons.delete_outline_rounded,
      title: 'Delete this account?',
      width: 440,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Delete'),
        ),
      ],
      child: Text(
        '“${a.email}” will be removed from your Supabase database, including '
        'its password, MEGA key, upload folder URL, notes and login history.',
        style: AppTheme.bodySecondary,
      ),
    ),
  );
  return ok == true;
}
