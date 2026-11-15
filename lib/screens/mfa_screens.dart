import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../security/security_controller.dart';
import '../widgets/dialogs.dart';
import '../widgets/form_bits.dart';

export '../security/security_controller.dart' show TotpSetup;

/// Six-digit code input; submits by itself once six digits are in.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.onComplete,
    this.autoSubmit = true,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onComplete;

  /// Off where a stray sixth digit shouldn't act at once (turning 2FA off).
  final bool autoSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: AppTheme.mono.copyWith(fontSize: 26, letterSpacing: 10),
      decoration: const InputDecoration(hintText: '000000'),
      onChanged: (v) {
        if (autoSubmit && v.length == 6) onComplete(v);
      },
      onSubmitted: onComplete,
    );
  }
}

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

Widget _signOutFooter(String? email, VoidCallback? onSignOut) => Wrap(
  alignment: WrapAlignment.center,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 6,
  children: [
    const Icon(Icons.person_rounded, size: 14, color: AppTheme.textMuted),
    Text(email ?? 'Signed in', style: AppTheme.caption),
    TextButton(onPressed: onSignOut, child: const Text('Sign out')),
  ],
);

const _lostPhoneHelp =
    'Lost your phone? In Supabase open Authentication › Users › your user, '
    'delete the MFA factor, then sign in with just your password.';

const _smallMuted = TextStyle(
  fontFamily: AppTheme.font,
  fontSize: 11.5,
  color: AppTheme.textMuted,
);

// ---------------------------------------------------------------------------
// Security › Turn on 2FA: add an authenticator app (optional)
// ---------------------------------------------------------------------------

/// Opened from the Security dialog. Pops `true` once 2FA is on.
class MfaEnrolDialog extends StatefulWidget {
  const MfaEnrolDialog({
    super.key,
    required this.onStart,
    required this.onVerify,
    this.onCancel,
  });

  /// Creates a new (unverified) TOTP factor in Supabase.
  final Future<TotpSetup> Function() onStart;

  /// Verifies the first code. Returns an error message, or null on success.
  final Future<String?> Function(String factorId, String code) onVerify;

  /// Closed before the first code: drop the unfinished factor.
  final Future<void> Function(String factorId)? onCancel;

  @override
  State<MfaEnrolDialog> createState() => _MfaEnrolDialogState();
}

class _MfaEnrolDialogState extends State<MfaEnrolDialog> {
  final _code = TextEditingController();
  TotpSetup? _setup;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _setup = null;
    });
    try {
      final s = await widget.onStart();
      if (mounted) setState(() => _setup = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _verify([String? value]) async {
    final setup = _setup;
    final code = (value ?? _code.text).trim();
    if (setup == null || _busy) return;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onVerify(setup.factorId, code);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
      _code.clear();
    });
  }

  void _cancel() {
    final setup = _setup;
    if (setup != null) widget.onCancel?.call(setup.factorId);
    Navigator.pop(context, false);
  }

  static String _grouped(String s) => [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, i + 4 > s.length ? s.length : i + 4),
  ].join(' ');

  Widget _steps(TotpSetup setup) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '1. In your authenticator app, add an account and scan this code:',
        style: AppTheme.body,
      ),
      const SizedBox(height: 14),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: QrImageView(
            data: setup.uri,
            size: 184,
            padding: const EdgeInsets.all(12),
            backgroundColor: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        "Can't scan? Choose \"enter a setup key\" and type:",
        style: AppTheme.caption,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: SelectableText(
              _grouped(setup.secret),
              textAlign: TextAlign.center,
              style: AppTheme.mono.copyWith(fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Copy setup key',
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: setup.secret)),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const Text('2. Type the 6-digit code it shows:', style: AppTheme.body),
      const SizedBox(height: 10),
      _CodeField(controller: _code, enabled: !_busy, onComplete: _verify),
      if (_error != null) ...[
        const SizedBox(height: 14),
        InlineMessage(_error!),
      ],
      const SizedBox(height: 12),
      const Text(
        'Other computers and browsers ask for the code the next time they '
        'open. $_lostPhoneHelp',
        style: _smallMuted,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    return MegaDialog(
      icon: Icons.verified_user_rounded,
      iconColor: AppTheme.megaBlue,
      title: 'Turn on two-step sign-in',
      width: 500,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: _busy ? null : _cancel,
          child: const Text('Cancel'),
        ),
        if (setup == null && _error != null)
          ElevatedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          )
        else
          ElevatedButton.icon(
            onPressed: _busy || setup == null ? null : _verify,
            icon: _busyIcon(_busy, Icons.verified_user_rounded),
            label: Text(_busy ? 'Checking…' : 'Turn on 2FA'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Optional. With it on, signing in needs your password and then a '
            '6-digit code from an authenticator app on your phone (Google '
            'Authenticator, Microsoft Authenticator, 1Password, Bitwarden, '
            '…). A stolen password alone then opens nothing.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: 18),
          if (setup != null)
            _steps(setup)
          else if (_error != null)
            InlineMessage(_error!)
          else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Security › Turn off 2FA
// ---------------------------------------------------------------------------

/// Asks for a current code before 2FA goes off. Pops `true` once it is off.
class MfaTurnOffDialog extends StatefulWidget {
  const MfaTurnOffDialog({super.key, required this.onTurnOff});

  /// Returns an error message, or null once 2FA is off.
  final Future<String?> Function(String code) onTurnOff;

  @override
  State<MfaTurnOffDialog> createState() => _MfaTurnOffDialogState();
}

class _MfaTurnOffDialogState extends State<MfaTurnOffDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _turnOff([String? value]) async {
    final code = (value ?? _code.text).trim();
    if (_busy) return;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onTurnOff(code);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MegaDialog(
      icon: Icons.gpp_maybe_rounded,
      title: 'Turn off two-step sign-in?',
      width: 460,
      actions: [
        OutlinedButton(
          style: AppTheme.ghostButton,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _turnOff,
          icon: _busyIcon(_busy, Icons.remove_moderator_rounded),
          label: Text(_busy ? 'Checking…' : 'Turn off 2FA'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Signing in then needs only your Supabase password. Your MEGA '
            'passwords stay encrypted with your master password either way.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'To confirm, type the 6-digit code from your authenticator app:',
            style: AppTheme.body,
          ),
          const SizedBox(height: 10),
          _CodeField(
            controller: _code,
            enabled: !_busy,
            onComplete: _turnOff,
            autoSubmit: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineMessage(_error!),
          ],
          const SizedBox(height: 12),
          const Text(
            'You can delete the authenticator-app entry afterwards. Turning '
            '2FA on again makes a new one.',
            style: _smallMuted,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Every sign-in: the 6-digit code
// ---------------------------------------------------------------------------

class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({
    super.key,
    required this.onVerify,
    required this.onSignOut,
    this.email,
    this.waitingForScheduledCheck = false,
  });

  /// Returns an error message, or null on success.
  final Future<String?> Function(String code) onVerify;
  final VoidCallback onSignOut;
  final String? email;

  /// Opened by a scheduled check that needs you to sign in.
  final bool waitingForScheduledCheck;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify([String? value]) async {
    final code = (value ?? _code.text).trim();
    if (_busy) return;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onVerify(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Two-step sign-in',
      subtitle: widget.waitingForScheduledCheck
          ? 'A scheduled check is waiting. Enter the 6-digit code from your '
                'authenticator app to let it run.'
          : '2FA is on for this account. Enter the 6-digit code from your '
                'authenticator app.',
      footer: _signOutFooter(widget.email, _busy ? null : widget.onSignOut),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CodeField(controller: _code, enabled: !_busy, onComplete: _verify),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineMessage(_error!),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _busy ? null : _verify,
            icon: _busyIcon(_busy, Icons.verified_user_rounded),
            label: Text(_busy ? 'Checking…' : 'Verify'),
          ),
          const SizedBox(height: 12),
          const Text(_lostPhoneHelp, style: _smallMuted),
        ],
      ),
    );
  }
}
