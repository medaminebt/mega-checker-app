import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../screens/mfa_screens.dart';
import '../screens/vault_screens.dart';
import '../security/security_controller.dart';
import 'dialogs.dart';
import 'form_bits.dart';

Future<void> showSecurityDialog(BuildContext context, SecurityController c) =>
    showDialog<void>(
      context: context,
      builder: (_) => SecurityDialog(controller: c),
    );

/// Header shield button: 2FA on / off, master password, recovery key,
/// remember-on-this-computer (desktop), sign out on browser close (web).
class SecurityDialog extends StatefulWidget {
  const SecurityDialog({super.key, required this.controller});

  final SecurityController controller;

  @override
  State<SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<SecurityDialog> {
  SecurityController get c => widget.controller;
  bool? _remembered;
  bool _sessionOnly = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _sessionOnly = c.signOutOnBrowserClose;
    if (c.canRemember) {
      c.isRemembered().then((v) {
        if (mounted) setState(() => _remembered = v);
      });
    }
  }

  void _say(String? text, {bool error = false}) => setState(() {
    _message = text;
    _messageIsError = error;
  });

  Future<void> _toggleRemember(bool on) async {
    setState(() => _busy = true);
    final err = await c.setRemembered(on);
    final now = await c.isRemembered();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _remembered = now;
    });
    _say(
      err ??
          (on
              ? 'Remembered in ${c.rememberStoreName}.'
              : 'Forgotten. You will type the master password next time.'),
      error: err != null,
    );
  }

  Future<void> _turnOnTwoFactor() async {
    final on = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MfaEnrolDialog(
        onStart: c.startTwoFactor,
        onVerify: c.confirmTwoFactor,
        onCancel: c.cancelTwoFactor,
      ),
    );
    if (!mounted) return;
    setState(() {}); // status line
    if (on == true) {
      _say(
        '2FA is on. From now on, signing in asks for a code from your '
        'authenticator app after your password.',
      );
    }
  }

  Future<void> _turnOffTwoFactor() async {
    final off = await showDialog<bool>(
      context: context,
      builder: (_) => MfaTurnOffDialog(onTurnOff: c.turnOffTwoFactor),
    );
    if (!mounted) return;
    setState(() {});
    if (off == true) {
      _say('2FA is off. Signing in needs only your password.');
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeMasterPasswordDialog(controller: c),
    );
    if (changed == true) _say('Master password changed.');
  }

  Future<void> _newRecoveryKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => MegaDialog(
        icon: Icons.vpn_key_rounded,
        iconColor: AppTheme.megaBlue,
        title: 'Make a new recovery key?',
        width: 460,
        actions: [
          OutlinedButton(
            style: AppTheme.ghostButton,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Make a new key'),
          ),
        ],
        child: Text(
          'Your current recovery key stops working. Do this if you lost it '
          'or think someone else has seen it.',
          style: AppTheme.bodySecondary,
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final (key, err) = await c.newRecoveryKey();
    if (!mounted) return;
    setState(() => _busy = false);
    if (key == null) {
      _say(err ?? 'Something went wrong.', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MegaDialog(
        icon: Icons.vpn_key_rounded,
        iconColor: AppTheme.megaBlue,
        title: 'Your new recovery key',
        width: 520,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("I've saved it"),
          ),
        ],
        child: RecoveryKeyPanel(key),
      ),
    );
    _say('New recovery key saved. The old one no longer works.');
  }

  Future<void> _toggleSessionOnly(bool on) async {
    await c.setSignOutOnBrowserClose(on);
    if (!mounted) return;
    setState(() => _sessionOnly = on);
    _say(
      on
          ? 'Closing this tab or the browser now signs you out.'
          : 'This browser keeps you signed in until you sign out.',
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: AppTheme.megaRed),
                const SizedBox(width: 8),
                Text(title, style: AppTheme.h3.copyWith(fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MegaDialog(
      icon: Icons.shield_rounded,
      title: 'Security',
      width: 560,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('Two-step sign-in (2FA)', Icons.verified_user_rounded, [
            Text(c.twoFactorSummary, style: AppTheme.body),
            const SizedBox(height: 4),
            Text(
              c.twoFactorOn
                  ? 'Signing in asks for a 6-digit code from your '
                        'authenticator app after your password. Lost your '
                        'phone? In Supabase open Authentication › Users › your '
                        'user and delete the MFA factor.'
                  : 'Optional. Turn it on and signing in also asks for a '
                        '6-digit code from an authenticator app on your '
                        'phone, so a stolen password alone opens nothing.',
              style: AppTheme.caption,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: c.twoFactorOn
                  ? OutlinedButton.icon(
                      onPressed: _busy ? null : _turnOffTwoFactor,
                      icon: const Icon(
                        Icons.remove_moderator_rounded,
                        size: 18,
                      ),
                      label: const Text('Turn off 2FA'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _busy ? null : _turnOnTwoFactor,
                      icon: const Icon(Icons.verified_user_rounded, size: 18),
                      label: const Text('Turn on 2FA'),
                    ),
            ),
          ]),
          _section('Master password', Icons.lock_rounded, [
            Text(
              'Encrypts your MEGA passwords and keys before they reach '
              'Supabase (AES-256-GCM; key from PBKDF2-SHA256).',
              style: AppTheme.caption,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _changePassword,
                  icon: const Icon(Icons.password_rounded, size: 18),
                  label: const Text('Change master password'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _newRecoveryKey,
                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                  label: const Text('New recovery key'),
                ),
              ],
            ),
            if (c.canRemember) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _remembered ?? false,
                onChanged: _busy || _remembered == null
                    ? null
                    : _toggleRemember,
                title: Text(
                  'Remember on ${c.deviceName}',
                  style: AppTheme.body,
                ),
                subtitle: Text(
                  'Opens without the master password; needed for scheduled '
                  'checks. Kept in ${c.rememberStoreName}. Signing out '
                  'forgets it.',
                  style: AppTheme.caption,
                ),
              ),
            ],
          ]),
          if (c.canSignOutOnBrowserClose)
            _section('This browser', Icons.public_rounded, [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sessionOnly,
                onChanged: _toggleSessionOnly,
                title: Text(
                  'Sign out when I close the browser',
                  style: AppTheme.body,
                ),
                subtitle: Text(
                  'Keeps the sign-in only for this tab (sessionStorage). '
                  'Use it on computers that aren\'t yours. The master '
                  'password is never stored in the browser either way.',
                  style: AppTheme.caption,
                ),
              ),
            ]),
          if (_message != null)
            InlineMessage(_message!, error: _messageIsError),
        ],
      ),
    );
  }
}

class _ChangeMasterPasswordDialog extends StatefulWidget {
  const _ChangeMasterPasswordDialog({required this.controller});

  final SecurityController controller;

  @override
  State<_ChangeMasterPasswordDialog> createState() =>
      _ChangeMasterPasswordDialogState();
}

class _ChangeMasterPasswordDialogState
    extends State<_ChangeMasterPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current master password.');
      return;
    }
    final problem = checkNewMasterPassword(_next.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.controller.changeMasterPassword(
      _current.text,
      _next.text,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MegaDialog(
      icon: Icons.password_rounded,
      title: 'Change master password',
      width: 480,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Change password'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Current master password'),
          SecretField(
            controller: _current,
            enabled: !_busy,
            autofocus: true,
            onSubmitted: _save,
          ),
          const SizedBox(height: 14),
          const FieldLabel('New master password'),
          SecretField(
            controller: _next,
            enabled: !_busy,
            hint: 'at least $kMinMasterPasswordLength characters',
            onSubmitted: _save,
          ),
          const SizedBox(height: 14),
          const FieldLabel('Type it again'),
          SecretField(
            controller: _confirm,
            enabled: !_busy,
            onSubmitted: _save,
          ),
          const SizedBox(height: 10),
          Text(
            'Your recovery key keeps working, and so do computers where the '
            'key is remembered. Everywhere else, use the new password next '
            'time.',
            style: AppTheme.caption,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineMessage(_error!),
          ],
        ],
      ),
    );
  }
}
