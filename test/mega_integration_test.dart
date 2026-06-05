import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';

// Exercises the real MEGAcmd integration. Requires MEGAcmd installed.
// Makes one (intentionally failing) login attempt, so it touches the network.
void main() {
  test('MEGAcmd is installed and resolvable', () {
    expect(MegaService.isInstalled, isTrue,
        reason: 'install with: brew install --cask megacmd');
  });

  test('invalid email format is rejected before contacting MEGA', () async {
    final r = await MegaService.keepAlive(
        Account(email: 'not-an-email', password: 'x'));
    expect(r.outcome, LoginOutcome.invalidEmail);
    expect(r.noteText, contains('invalid email'));
  });

  test('bad credentials are classified', () async {
    final r = await MegaService.keepAlive(Account(
        email: 'definitely-not-real@example.invalid', password: 'wrongpass'));
    expect(r.ok, isFalse);
    expect(
        r.outcome,
        anyOf(LoginOutcome.wrongCredentials, LoginOutcome.error,
            LoginOutcome.needs2fa));
    stdout.writeln('  -> outcome=${r.outcome}  note="${r.noteText}"');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
