import 'package:url_launcher/url_launcher.dart';

/// Opening web links (the MEGA upload folder URLs) in the default browser —
/// a new tab in the web build.
class Links {
  /// Turn what was pasted into an http(s) URL, or null if it isn't one.
  /// A missing scheme is assumed to be https (`mega.nz/…` works).
  static Uri? webUri(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        !uri.host.contains('.')) {
      return null;
    }
    return uri;
  }

  /// Test-only hook: when set, [open] calls this instead of the browser.
  static Future<bool> Function(Uri)? overrideOpen;

  static Future<bool> open(Uri uri) async {
    final override = overrideOpen;
    if (override != null) return override(uri);
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      return false;
    }
  }
}
