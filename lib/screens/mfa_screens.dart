import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../widgets/form_bits.dart';

/// What the authenticator app needs (from Supabase's TOTP enrolment).
class TotpSetup {
  const TotpSetup({
    required this.factorId,
    required this.uri,
    required this.secret,
  });

  final String factorId;

  /// `otpauth://totp/…` — shown as a QR code.
  final String uri;

  /// The same secret as text, for typing in by hand.
  final String secret;
}

/// Six-digit code input; submits by itself once six digits are in.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.onComplete,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onComplete;

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
        if (v.length == 6) onComplete(v);
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

// ---------------------------------------------------------------------------
// First sign-in: add an authenticator app
// ---------------------------------------------------------------------------

class MfaEnrolScreen extends StatefulWidget {
  const MfaEnrolScreen({
    super.key,
    required this.onStart,
    required this.onVerify,
    required this.onSignOut,
    this.email,
  });

  /// Creates a new (unverified) TOTP factor in Supabase.
  final Future<TotpSetup> Function() onStart;

  /// Verifies the first code. Returns an error message, or null on success.
  final Future<String?> Function(String factorId, String code) onVerify;

  final VoidCallback onSignOut;
  final String? email;

  @override
  State<MfaEnrolScreen> createState() => _MfaEnrolScreenState();
}

class _MfaEnrolScreenState extends State<MfaEnrolScreen> {
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
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _code.clear();
    });
  }

  static String _grouped(String s) => [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, i + 4 > s.length ? s.length : i + 4),
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    return AuthShell(
      title: 'Turn on two-step sign-in',
      subtitle:
          'From now on, signing in needs your password and a 6-digit code '
          'from an authenticator app on your phone (Google Authenticator, '
          'Microsoft Authenticator, 1Password, Bitwarden, …). A stolen '
          'password alone then opens nothing.',
      width: 500,
      footer: _signOutFooter(widget.email, _busy ? null : widget.onSignOut),
      child: setup == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  InlineMessage(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. In your authenticator app, add an account and scan '
                  'this code:',
                  style: AppTheme.body,
                ),
                const SizedBox(height: 14),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    child: QrImageView(
                      data: setup.uri,
                      size: 196,
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
                const Text(
                  '2. Type the 6-digit code it shows:',
                  style: AppTheme.body,
                ),
                const SizedBox(height: 10),
                _CodeField(
                  controller: _code,
                  enabled: !_busy,
                  onComplete: _verify,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  InlineMessage(_error!),
                ],
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _verify,
                  icon: _busyIcon(_busy, Icons.verified_user_rounded),
                  label: Text(_busy ? 'Checking…' : 'Turn on 2FA'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Lost your phone later? In Supabase open Authentication › '
                  'Users › your user and delete the MFA factor, then sign in '
                  'again to set up a new one.',
                  style: TextStyle(
                    fontFamily: AppTheme.font,
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
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
          : 'Enter the 6-digit code from your authenticator app.',
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
          const Text(
            'Lost your phone? In Supabase open Authentication › Users › your '
            'user and delete the MFA factor, then sign in again.',
            style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 11.5,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
