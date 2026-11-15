import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_bits.dart';

/// Minimum master-password length the app accepts.
const kMinMasterPasswordLength = 10;

/// Reason [password] / [confirm] can't be used, or null.
String? checkNewMasterPassword(String password, String confirm) {
  if (password.length < kMinMasterPasswordLength) {
    return 'Use at least $kMinMasterPasswordLength characters. A few random '
        'words ("lamp river cactus orbit") are long and easy to remember.';
  }
  if (password != confirm) return "The two passwords don't match.";
  return null;
}

/// Password input with a show / hide button.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    this.hint = '',
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
    this.mono = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final bool mono;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      style: widget.mono ? AppTheme.mono : null,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.key_rounded, size: 18),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show' : 'Hide',
          icon: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 18,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onSubmitted: (_) => widget.onSubmitted?.call(),
    );
  }
}

/// The recovery key, big and copyable, with what to do with it.
class RecoveryKeyPanel extends StatelessWidget {
  const RecoveryKeyPanel(this.recoveryKey, {super.key});

  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: AppTheme.bgBase,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.megaBlue.withValues(alpha: .6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  recoveryKey,
                  style: AppTheme.mono.copyWith(
                    fontSize: 16,
                    letterSpacing: 1.2,
                    height: 1.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy recovery key',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: recoveryKey));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Recovery key copied.')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Store it in your password manager or write it down and keep it '
          'somewhere safe. It opens your passwords if you forget the master '
          'password. It is shown only now; you can make a new one later in '
          'Security settings.',
          style: AppTheme.caption,
        ),
      ],
    );
  }
}

Widget _rememberBox({
  required bool value,
  required ValueChanged<bool> onChanged,
  required bool enabled,
  required String deviceName,
}) => InkWell(
  borderRadius: BorderRadius.circular(AppTheme.radius),
  onTap: enabled ? () => onChanged(!value) : null,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Checkbox(
        value: value,
        onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text.rich(
            TextSpan(
              text: 'Remember on $deviceName',
              style: AppTheme.body,
              children: const [
                TextSpan(
                  text:
                      '\nOpens without the master password next time. Needed '
                      'for scheduled checks.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget _busyIcon(bool busy, IconData icon) => busy
    ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.textSecondary,
        ),
      )
    : Icon(icon, size: 18);

Widget _footer(String? email, VoidCallback? onSignOut) => Wrap(
  alignment: WrapAlignment.center,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 6,
  children: [
    const Icon(Icons.person_rounded, size: 14, color: AppTheme.textMuted),
    Text(email ?? 'Signed in', style: AppTheme.caption),
    TextButton(onPressed: onSignOut, child: const Text('Sign out')),
  ],
);

// ---------------------------------------------------------------------------
// First time: choose a master password
// ---------------------------------------------------------------------------

class VaultSetupScreen extends StatefulWidget {
  const VaultSetupScreen({
    super.key,
    required this.onCreate,
    required this.onDone,
    required this.onSignOut,
    this.email,
    this.canRemember = false,
    this.deviceName = 'this computer',
  });

  /// Creates the vault in Supabase. Returns the recovery key to show, or
  /// throws with a readable message.
  final Future<String> Function(String password, bool remember) onCreate;

  /// Called after the user confirmed they saved the recovery key.
  final VoidCallback onDone;

  final VoidCallback onSignOut;
  final String? email;
  final bool canRemember;
  final String deviceName;

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _understood = false;
  bool _remember = false;
  bool _busy = false;
  bool _saved = false;
  String? _error;
  String? _recoveryKey;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final problem = checkNewMasterPassword(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (!_understood) {
      setState(() => _error = 'Tick the box to confirm you understand.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await widget.onCreate(_password.text, _remember);
      if (mounted) setState(() => _recoveryKey = key);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _recoveryKey;
    if (key != null) {
      return AuthShell(
        title: 'Save your recovery key',
        subtitle:
            'Your passwords are now encrypted with your master password. If '
            'you ever forget it, this key is the only other way in.',
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryKeyPanel(key),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => setState(() => _saved = !_saved),
              child: Row(
                children: [
                  Checkbox(
                    value: _saved,
                    onChanged: (v) => setState(() => _saved = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      "I've saved my recovery key",
                      style: AppTheme.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _saved ? widget.onDone : null,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Continue'),
            ),
          ],
        ),
      );
    }

    return AuthShell(
      title: 'Set a master password',
      subtitle:
          'Your MEGA passwords and keys will be encrypted on this device '
          'before they are saved. Supabase only stores scrambled text it '
          "can't read, and so would anyone who got into your database.",
      width: 520,
      footer: _footer(widget.email, _busy ? null : widget.onSignOut),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Master password'),
          SecretField(
            controller: _password,
            enabled: !_busy,
            autofocus: true,
            hint: 'at least $kMinMasterPasswordLength characters',
            onSubmitted: _create,
          ),
          const SizedBox(height: 14),
          const FieldLabel('Type it again'),
          SecretField(
            controller: _confirm,
            enabled: !_busy,
            hint: 'same password',
            onSubmitted: _create,
          ),
          const SizedBox(height: 10),
          const Text(
            "Pick one you don't use anywhere else, and not your Supabase "
            'password. You type it each time the app opens (unless you tick '
            'Remember).',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 10),
          if (widget.canRemember)
            _rememberBox(
              value: _remember,
              enabled: !_busy,
              deviceName: widget.deviceName,
              onChanged: (v) => setState(() => _remember = v),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: _busy
                ? null
                : () => setState(() => _understood = !_understood),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _understood,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _understood = v ?? false),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'I understand: if I lose both the master password and '
                      'the recovery key shown next, my stored MEGA passwords '
                      'and keys are gone for good. Nobody can recover them, '
                      'not even with access to Supabase.',
                      style: AppTheme.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineMessage(_error!),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busyIcon(_busy, Icons.lock_rounded),
            label: Text(_busy ? 'Encrypting…' : 'Encrypt my passwords'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Every launch: unlock
// ---------------------------------------------------------------------------

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.onUnlock,
    required this.onRecover,
    required this.onReset,
    required this.onSignOut,
    this.email,
    this.canRemember = false,
    this.deviceName = 'this computer',
    this.waitingForScheduledCheck = false,
  });

  /// Returns an error message, or null on success.
  final Future<String?> Function(String password, bool remember) onUnlock;

  /// Unlock with the recovery key and set a new master password. Returns an
  /// error message, or null on success.
  final Future<String?> Function(
    String recoveryKey,
    String newPassword,
    bool remember,
  )
  onRecover;

  /// Wipe the vault and the stored secrets. Returns an error message, or
  /// null on success.
  final Future<String?> Function() onReset;

  final VoidCallback onSignOut;
  final String? email;
  final bool canRemember;
  final String deviceName;
  final bool waitingForScheduledCheck;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  final _recovery = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _recoveryMode = false;
  bool _remember = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_password, _recovery, _newPassword, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  void _unlock() {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your master password.');
      return;
    }
    _run(() => widget.onUnlock(_password.text, _remember));
  }

  void _recover() {
    if (_recovery.text.trim().isEmpty) {
      setState(() => _error = 'Enter your recovery key.');
      return;
    }
    final problem = checkNewMasterPassword(_newPassword.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    _run(() => widget.onRecover(_recovery.text, _newPassword.text, _remember));
  }

  Future<void> _reset() async {
    final ok = await confirmVaultReset(context);
    if (!ok || !mounted) return;
    await _run(widget.onReset);
  }

  @override
  Widget build(BuildContext context) {
    final remember = widget.canRemember
        ? _rememberBox(
            value: _remember,
            enabled: !_busy,
            deviceName: widget.deviceName,
            onChanged: (v) => setState(() => _remember = v),
          )
        : const SizedBox.shrink();

    final body = _recoveryMode
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Recovery key'),
              TextField(
                controller: _recovery,
                enabled: !_busy,
                autofocus: true,
                style: AppTheme.mono,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                  prefixIcon: Icon(Icons.vpn_key_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('New master password'),
              SecretField(
                controller: _newPassword,
                enabled: !_busy,
                hint: 'at least $kMinMasterPasswordLength characters',
                onSubmitted: _recover,
              ),
              const SizedBox(height: 14),
              const FieldLabel('Type it again'),
              SecretField(
                controller: _confirm,
                enabled: !_busy,
                hint: 'same password',
                onSubmitted: _recover,
              ),
              const SizedBox(height: 6),
              remember,
              if (_error != null) ...[
                const SizedBox(height: 14),
                InlineMessage(_error!),
              ],
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _busy ? null : _recover,
                icon: _busyIcon(_busy, Icons.lock_open_rounded),
                label: Text(_busy ? 'Unlocking…' : 'Unlock & set new password'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _recoveryMode = false;
                        _error = null;
                      }),
                child: const Text('Back to master password'),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Master password'),
              SecretField(
                controller: _password,
                enabled: !_busy,
                autofocus: true,
                hint: '••••••••••',
                onSubmitted: _unlock,
              ),
              const SizedBox(height: 6),
              remember,
              if (_error != null) ...[
                const SizedBox(height: 14),
                InlineMessage(_error!),
              ],
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: _busyIcon(_busy, Icons.lock_open_rounded),
                label: Text(_busy ? 'Unlocking…' : 'Unlock'),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _recoveryMode = true;
                            _error = null;
                          }),
                    child: const Text('Forgot it? Use the recovery key'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _reset,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textMuted,
                    ),
                    child: const Text('Lost both?'),
                  ),
                ],
              ),
            ],
          );

    return AuthShell(
      title: _recoveryMode ? 'Use your recovery key' : 'Unlock your passwords',
      subtitle: widget.waitingForScheduledCheck
          ? 'A scheduled check is waiting. Enter your master password to let '
                'it run (tick Remember so next time it runs by itself).'
          : _recoveryMode
          ? 'Enter the recovery key you saved, then choose a new master '
                'password.'
          : 'Your MEGA passwords and keys are encrypted. Enter your master '
                'password to open them.',
      width: 500,
      footer: _footer(widget.email, _busy ? null : widget.onSignOut),
      child: body,
    );
  }
}

/// "Lost both?" — the last resort, confirmed by typing RESET.
Future<bool> confirmVaultReset(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ResetDialog(),
  );
  return ok == true;
}

class _ResetDialog extends StatefulWidget {
  const _ResetDialog();

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  final _text = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    final ready = _text.text.trim().toUpperCase() == 'RESET';
    return MegaDialog(
      icon: Icons.warning_amber_rounded,
      title: 'Start over without your passwords?',
      width: 500,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          icon: const Icon(Icons.delete_forever_rounded, size: 18),
          label: const Text('Erase passwords & keys'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Without the master password or the recovery key, nobody can '
            'decrypt your stored MEGA passwords and keys. This erases them '
            'from Supabase and lets you choose a new master password.\n\n'
            'Kept: emails, notes, upload folder links, login history and '
            'storage. Afterwards, add the passwords again with Paste list '
            '(email:password lines, with "Update the password of accounts '
            'already in the list" ticked).',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: 16),
          const FieldLabel('Type RESET to confirm'),
          TextField(
            controller: _text,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'RESET'),
          ),
        ],
      ),
    );
  }
}
