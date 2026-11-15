import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/form_bits.dart';

/// First-run screen: paste the Supabase Project URL + publishable key. They
/// are tested, then saved with shared_preferences so this only happens once.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.onConnect,
    this.initialUrl,
    this.initialKey,
    this.initialError,
  });

  /// Initialise Supabase with these values and test them. Returns an error
  /// message, or null on success.
  final Future<String?> Function(String url, String key) onConnect;

  final String? initialUrl;
  final String? initialKey;
  final String? initialError;

  /// Normalise what people paste: trims, drops a trailing `/rest/v1/` etc.
  /// Returns null if it isn't an https URL.
  static String? normaliseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  /// Returns a reason the key must not be used in the app, or null if it's OK.
  static String? rejectKey(String key) {
    final k = key.trim();
    if (k.isEmpty) return 'Paste the publishable key.';
    if (k.startsWith('sb_secret_')) {
      return 'That is a SECRET key — never put it in an app. Use the '
          '"Publishable key" (starts with sb_publishable_).';
    }
    // Legacy JWT keys: refuse the service_role one.
    final parts = k.split('.');
    if (parts.length == 3) {
      try {
        final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        if (payload.contains('"service_role"')) {
          return 'That is the service_role key — it bypasses all security. '
              'Use the publishable (or legacy "anon") key instead.';
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  late final _key = TextEditingController(text: widget.initialKey ?? '');
  late String? _error = widget.initialError;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = SetupScreen.normaliseUrl(_url.text);
    if (url == null) {
      setState(
        () => _error =
            'The Project URL should look like https://abcdefgh.supabase.co',
      );
      return;
    }
    final keyProblem = SetupScreen.rejectKey(_key.text);
    if (keyProblem != null) {
      setState(() => _error = keyProblem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onConnect(url, _key.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Connect to Supabase',
      subtitle:
          'Your MEGA accounts are stored in your own Supabase database. '
          'Paste your project\'s details once — they\'re saved '
          '${kIsWeb ? 'in this browser' : 'on this computer'}.',
      footer: const Text(
        'Where to find these: Supabase dashboard → your project → '
        'Project Settings → Data API (URL) and API Keys (publishable key).\n'
        'Step-by-step guide: SUPABASE_SETUP.md in the project folder.',
        style: AppTheme.caption,
        textAlign: TextAlign.center,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Project URL'),
          TextField(
            controller: _url,
            enabled: !_busy,
            autofocus: _url.text.isEmpty,
            decoration: const InputDecoration(
              hintText: 'https://abcdefghijkl.supabase.co',
              prefixIcon: Icon(Icons.link_rounded, size: 18),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Publishable key'),
          TextField(
            controller: _key,
            enabled: !_busy,
            style: AppTheme.mono,
            decoration: const InputDecoration(
              hintText: 'sb_publishable_…',
              prefixIcon: Icon(Icons.key_rounded, size: 18),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          const Text(
            'Never paste the database password or a secret / service_role key '
            'here — the app only needs the publishable key.',
            style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 11.5,
              color: AppTheme.textMuted,
            ),
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
                : const Icon(Icons.power_rounded, size: 18),
            label: Text(_busy ? 'Testing connection…' : 'Save & connect'),
          ),
        ],
      ),
    );
  }
}
