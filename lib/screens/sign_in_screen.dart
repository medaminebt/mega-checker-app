import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../prefs.dart';
import '../widgets/form_bits.dart';

/// Sign in with the Supabase user created in the dashboard. Row Level
/// Security only lets that user read / write their MEGA accounts.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.onSignIn,
    required this.onChangeProject,
    this.projectHost,
  });

  /// Returns an error message, or null on success.
  final Future<String?> Function(String email, String password) onSignIn;
  final VoidCallback onChangeProject;
  final String? projectHost;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController(text: Prefs.lastSignInEmail);
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Enter the email and password of your Supabase user.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSignIn(email, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Sign in',
      subtitle:
          'Use the user you created in Supabase → Authentication → '
          'Users. Only this user can read your MEGA accounts.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          const Icon(
            Icons.storage_rounded,
            size: 14,
            color: AppTheme.textMuted,
          ),
          Text(widget.projectHost ?? 'Supabase', style: AppTheme.caption),
          TextButton(
            onPressed: _busy ? null : widget.onChangeProject,
            child: const Text('Change project'),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Email'),
            TextField(
              controller: _email,
              enabled: !_busy,
              autofocus: _email.text.isEmpty,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            const FieldLabel('Password'),
            TextField(
              controller: _password,
              enabled: !_busy,
              autofocus: _email.text.isNotEmpty,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
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
            if (_error != null) ...[
              const SizedBox(height: 16),
              InlineMessage(_error!),
            ],
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  : const Icon(Icons.login_rounded, size: 18),
              label: Text(_busy ? 'Signing in…' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
