// Exercises the real MEGAcmd integration (requires MEGAcmd installed). Makes
// one intentionally failing login, so it touches the network.
// Skip it with: flutter test --exclude-tags live
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';

void main() {
  test('MEGAcmd is installed and resolvable', () {
    expect(
      MegaService.isInstalled,
      isTrue,
      reason: 'install with: brew install --cask megacmd',
    );
  });

  test('invalid email format is rejected before contacting MEGA', () async {
    final r = await MegaService.keepAlive(
      Account(email: 'not-an-email', password: 'x'),
    );
    expect(r.outcome, LoginOutcome.invalidEmail);
    expect(r.errorText, contains('Invalid email'));
  });

  test('bad credentials are classified', () async {
    final r = await MegaService.keepAlive(
      Account(
        email: 'definitely-not-real@example.invalid',
        password: 'wrongpass',
      ),
    );
    expect(r.ok, isFalse);
    expect(
      r.outcome,
      anyOf(
        LoginOutcome.wrongCredentials,
        LoginOutcome.error,
        LoginOutcome.needs2fa,
      ),
    );
    stdout.writeln('  -> outcome=${r.outcome}  note="${r.errorText}"');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
