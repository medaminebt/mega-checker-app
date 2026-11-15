import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/app_theme.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/prefs.dart';
import 'package:mega_keepalive/screens/home_page.dart';
import 'package:mega_keepalive/screens/mfa_screens.dart';
import 'package:mega_keepalive/screens/sign_in_screen.dart';
import 'package:mega_keepalive/screens/vault_screens.dart';
import 'package:mega_keepalive/security/encrypted_repository.dart';
import 'package:mega_keepalive/security/security_controller.dart';
import 'package:mega_keepalive/security/vault_crypto.dart';
import 'package:mega_keepalive/widgets/schedule_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repository.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.theme(), home: child);

class _FakeSecurity implements SecurityController {
  _FakeSecurity({this.twoFactorOn = true});

  bool remembered = false;
  String? changed;
  String? cancelled;

  @override
  bool twoFactorOn;
  @override
  String get twoFactorSummary =>
      twoFactorOn ? 'On · authenticator app, added 2026-11-15' : 'Off';
  @override
  Future<TotpSetup> startTwoFactor() async => const TotpSetup(
    factorId: 'f1',
    uri: 'otpauth://totp/mega-checker-app:me?secret=JBSWY3DPEHPK3PXP',
    secret: 'JBSWY3DPEHPK3PXP',
  );
  @override
  Future<String?> confirmTwoFactor(String factorId, String code) async {
    if (code != '123456') return "That code didn't work.";
    twoFactorOn = true;
    return null;
  }

  @override
  Future<void> cancelTwoFactor(String factorId) async => cancelled = factorId;
  @override
  Future<String?> turnOffTwoFactor(String code) async {
    if (code != '123456') return "That code didn't work.";
    twoFactorOn = false;
    return null;
  }

  @override
  Future<String?> changeMasterPassword(String current, String next) async {
    if (current != 'old password!') {
      return 'Your current master password is wrong.';
    }
    changed = next;
    return null;
  }

  @override
  Future<(String?, String?)> newRecoveryKey() async =>
      ('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH', null);
  @override
  bool get canRemember => true;
  @override
  String get deviceName => 'this Mac';
  @override
  String get rememberStoreName => 'your macOS login Keychain';
  @override
  Future<bool> isRemembered() async => remembered;
  @override
  Future<String?> setRemembered(bool on) async {
    remembered = on;
    return null;
  }

  @override
  bool get canSignOutOnBrowserClose => false;
  @override
  bool get signOutOnBrowserClose => false;
  @override
  Future<void> setSignOutOnBrowserClose(bool on) async {}
}

void main() {
  setUp(() async {
    final v = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    v.physicalSize = const Size(1440, 900);
    v.devicePixelRatio = 1.0;
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    kDelayMinSec = 0;
    kDelayMaxSec = 0;
  });
  tearDown(() {
    MegaService.overrideKeepAlive = null;
    MegaService.overrideFreeUp = null;
    MegaService.debugSupported = null;
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!
        .resetPhysicalSize();
  });

  group('Rubbish Bin and versions (B2)', () {
    MemoryAccountsRepository repo() => MemoryAccountsRepository([
      Account(
        email: 'a@x.com',
        password: 'p',
        lastStatus: 'ok',
        storageUsedBytes: 2147483648,
        storageTotalBytes: 21474836480,
        storageRubbishBytes: 1073741824,
        storageVersionsBytes: 52428800,
      ),
    ]);

    testWidgets('sizes show in the column and the storage card', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(HomePage(repository: repo())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('BIN · VERSIONS'), findsOneWidget);
      expect(find.text('1 GB'), findsOneWidget);
      expect(find.text('50 MB'), findsOneWidget);
      expect(find.textContaining('bin 1 GB · versions 50 MB'), findsOneWidget);
    });

    testWidgets('emptying the bin asks "Are you sure?"; Cancel does nothing', (
      tester,
    ) async {
      MegaService.debugSupported = true;
      var calls = 0;
      MegaService.overrideFreeUp = (a, action) async {
        calls++;
        return LoginResult(LoginOutcome.success, 'ok');
      };
      await tester.pumpWidget(_wrap(HomePage(repository: repo())));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cleaning_services_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty Rubbish Bin (1 GB)'));
      await tester.pumpAndSettle();
      expect(find.text('Empty the Rubbish Bin?'), findsOneWidget);
      expect(find.textContaining('Are you sure?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('confirming empties it and saves the new sizes', (
      tester,
    ) async {
      MegaService.debugSupported = true;
      FreeUpAction? ran;
      MegaService.overrideFreeUp = (a, action) async {
        ran = action;
        return LoginResult(
          LoginOutcome.success,
          'ok',
          storage: const StorageInfo(1073741824, 21474836480),
          rubbishBytes: 0,
          versionsBytes: 52428800,
        );
      };
      final r = repo();
      await tester.pumpWidget(_wrap(HomePage(repository: r)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.cleaning_services_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty Rubbish Bin (1 GB)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete permanently'));
      await tester.pumpAndSettle();

      expect(ran, FreeUpAction.emptyRubbishBin);
      final row = r.rowByEmail('a@x.com')!;
      expect(row['storage_rubbish_bytes'], 0);
      expect(row['storage_used_bytes'], 1073741824);
      expect(row['last_login_at'], isNotNull);
      expect(find.textContaining('Rubbish Bin emptied'), findsOneWidget);
      expect(find.textContaining('Freed 1 GB'), findsOneWidget);
    });

    testWidgets('web build: the free-up button is disabled', (tester) async {
      MegaService.debugSupported = false;
      await tester.pumpWidget(_wrap(HomePage(repository: repo())));
      await tester.pumpAndSettle();
      final button = tester.widget<PopupMenuButton<FreeUpAction>>(
        find.byType(PopupMenuButton<FreeUpAction>),
      );
      expect(button.enabled, isFalse);
    });
  });

  testWidgets('a check stores bin and versions sizes too', (tester) async {
    MegaService.debugSupported = true;
    MegaService.overrideKeepAlive = (a) async => LoginResult(
      LoginOutcome.success,
      'ok',
      storage: const StorageInfo(5242880, 21474836480),
      rubbishBytes: 1024,
      versionsBytes: 2048,
    );
    final r = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ]);
    await tester.pumpWidget(_wrap(HomePage(repository: r)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check all accounts'));
    await tester.pumpAndSettle();
    final row = r.rowByEmail('a@x.com')!;
    expect(row['storage_rubbish_bytes'], 1024);
    expect(row['storage_versions_bytes'], 2048);
  });

  testWidgets('scheduled run checks everything, then quits after 15 s', (
    tester,
  ) async {
    MegaService.debugSupported = true;
    MegaService.overrideKeepAlive = (a) async =>
        LoginResult(LoginOutcome.success, 'ok');
    var quit = false;
    final r = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
      Account(email: 'b@x.com', password: 'q'),
    ]);
    await tester.pumpWidget(
      _wrap(
        HomePage(repository: r, scheduledRun: true, onQuit: () => quit = true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(r.rowByEmail('a@x.com')!['last_status'], 'ok');
    expect(r.rowByEmail('b@x.com')!['last_status'], 'ok');
    expect(find.textContaining('Closing in'), findsOneWidget);
    expect(find.text('Keep open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(quit, isTrue);
  });

  testWidgets('"Keep open" cancels the automatic quit', (tester) async {
    MegaService.debugSupported = true;
    MegaService.overrideKeepAlive = (a) async =>
        LoginResult(LoginOutcome.success, 'ok');
    var quit = false;
    await tester.pumpWidget(
      _wrap(
        HomePage(
          repository: MemoryAccountsRepository([
            Account(email: 'a@x.com', password: 'p'),
          ]),
          scheduledRun: true,
          onQuit: () => quit = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Keep open'));
    await tester.pump(const Duration(seconds: 20));
    expect(quit, isFalse);
  });

  testWidgets('encrypted repository: the table shows plain text', (
    tester,
  ) async {
    final cipher = FieldCipher(SecretKey(List<int>.filled(32, 7)));
    final mem = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'Secret-1', megaKey: 'KEY'),
    ]);
    await tester.pumpWidget(
      _wrap(HomePage(repository: EncryptedAccountsRepository(mem, cipher))),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Encrypted the stored passwords'),
      findsOneWidget,
    );
    expect(mem.rowByEmail('a@x.com')!['password'], startsWith('enc1:'));
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Secret-1'),
    );
    expect(field.controller!.text, 'Secret-1');
  });

  group('header dialogs', () {
    testWidgets('Security dialog: 2FA status, change master password', (
      tester,
    ) async {
      final sec = _FakeSecurity();
      await tester.pumpWidget(
        _wrap(HomePage(repository: MemoryAccountsRepository(), security: sec)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Security: 2FA, master password'));
      await tester.pumpAndSettle();
      expect(
        find.text('On · authenticator app, added 2026-11-15'),
        findsOneWidget,
      );
      expect(find.text('Remember on this Mac'), findsOneWidget);

      await tester.tap(find.text('Change master password'));
      await tester.pumpAndSettle();
      final fields = find.byType(SecretField);
      await tester.enterText(fields.at(0), 'old password!');
      await tester.enterText(fields.at(1), 'new password 123');
      await tester.enterText(fields.at(2), 'new password 123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(sec.changed, 'new password 123');
      expect(find.text('Master password changed.'), findsOneWidget);
    });

    testWidgets('Scheduled checks dialog renders its form and instructions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const Scaffold(body: ScheduleDialog(security: null))),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('On a date'), findsOneWidget);
      expect(find.text('Every Monday at 10:00'), findsOneWidget);

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('On the 1st of every month at 10:00'), findsOneWidget);

      await tester.tap(find.text('On a date'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a date'), findsOneWidget);

      await tester.ensureVisible(
        find.text('How it works, and doing it by hand'),
      );
      await tester.tap(find.text('How it works, and doing it by hand'));
      await tester.pumpAndSettle();
      expect(find.textContaining('--scheduled-check'), findsWidgets);
    });
  });

  group('master password screens', () {
    testWidgets('setup: validates, then shows the recovery key once', (
      tester,
    ) async {
      String? created;
      var done = false;
      await tester.pumpWidget(
        _wrap(
          VaultSetupScreen(
            onCreate: (pw, remember) async {
              created = pw;
              return 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH';
            },
            onDone: () => done = true,
            onSignOut: () {},
          ),
        ),
      );
      final fields = find.byType(SecretField);
      await tester.enterText(fields.at(0), 'short');
      await tester.enterText(fields.at(1), 'short');
      await tester.tap(find.text('Encrypt my passwords'));
      await tester.pump();
      expect(find.textContaining('at least 10 characters'), findsWidgets);

      await tester.enterText(fields.at(0), 'lamp river cactus');
      await tester.enterText(fields.at(1), 'lamp river cactus');
      await tester.ensureVisible(find.text('Encrypt my passwords'));
      await tester.tap(find.text('Encrypt my passwords'));
      await tester.pump();
      expect(find.textContaining('Tick the box'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('I understand'));
      await tester.tap(find.textContaining('I understand'));
      await tester.ensureVisible(find.text('Encrypt my passwords'));
      await tester.tap(find.text('Encrypt my passwords'));
      await tester.pumpAndSettle();
      expect(created, 'lamp river cactus');
      expect(find.text('Save your recovery key'), findsOneWidget);
      expect(
        find.text('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH'),
        findsOneWidget,
      );

      final cont = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(cont).onPressed, isNull);
      await tester.tap(find.text("I've saved my recovery key"));
      await tester.pump();
      await tester.ensureVisible(cont);
      await tester.tap(cont);
      expect(done, isTrue);
    });

    testWidgets('unlock: shows errors; "Lost both?" needs RESET typed', (
      tester,
    ) async {
      var resets = 0;
      await tester.pumpWidget(
        _wrap(
          UnlockScreen(
            onUnlock: (pw, r) async => 'Wrong master password.',
            onRecover: (k, pw, r) async => null,
            onReset: () async {
              resets++;
              return null;
            },
            onSignOut: () {},
          ),
        ),
      );
      await tester.enterText(find.byType(SecretField), 'nope');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong master password.'), findsOneWidget);

      await tester.tap(find.text('Lost both?'));
      await tester.pumpAndSettle();
      final erase = find.widgetWithText(
        ElevatedButton,
        'Erase passwords & keys',
      );
      expect(tester.widget<ElevatedButton>(erase).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'RESET'), 'reset');
      await tester.pump();
      await tester.tap(erase);
      await tester.pumpAndSettle();
      expect(resets, 1);
    });

    testWidgets('unlock with the recovery key sets a new master password', (
      tester,
    ) async {
      String? got;
      await tester.pumpWidget(
        _wrap(
          UnlockScreen(
            onUnlock: (pw, r) async => null,
            onRecover: (k, pw, r) async {
              got = '$k|$pw';
              return null;
            },
            onReset: () async => null,
            onSignOut: () {},
          ),
        ),
      );
      await tester.tap(find.text('Forgot it? Use the recovery key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH',
      );
      final fields = find.byType(SecretField);
      await tester.enterText(fields.at(0), 'a new long password');
      await tester.enterText(fields.at(1), 'a new long password');
      await tester.ensureVisible(find.text('Unlock & set new password'));
      await tester.tap(find.text('Unlock & set new password'));
      await tester.pumpAndSettle();
      expect(
        got,
        'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH|a new long password',
      );
    });
  });

  group('2FA screens', () {
    testWidgets('challenge submits by itself at 6 digits', (tester) async {
      String? code;
      await tester.pumpWidget(
        _wrap(
          MfaChallengeScreen(
            onVerify: (c) async {
              code = c;
              return "That code didn't work.";
            },
            onSignOut: () {},
            email: 'me@example.com',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(code, isNull);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(code, '123456');
      expect(find.text("That code didn't work."), findsOneWidget);
    });

    testWidgets('2FA is optional: Security dialog turns it on with a code', (
      tester,
    ) async {
      final sec = _FakeSecurity(twoFactorOn: false);
      await tester.pumpWidget(
        _wrap(HomePage(repository: MemoryAccountsRepository(), security: sec)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Security: 2FA, master password'));
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Turn off 2FA'), findsNothing);

      await tester.tap(find.text('Turn on 2FA'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Turn on two-step sign-in'), findsOneWidget);
      expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);

      // A wrong code keeps the dialog open; six digits submit by themselves.
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.pumpAndSettle();
      expect(find.text("That code didn't work."), findsOneWidget);
      expect(sec.twoFactorOn, isFalse);

      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.pumpAndSettle();
      expect(sec.twoFactorOn, isTrue);
      expect(find.text('Turn on two-step sign-in'), findsNothing);
      expect(find.textContaining('2FA is on.'), findsOneWidget);
      expect(
        find.text('On · authenticator app, added 2026-11-15'),
        findsOneWidget,
      );
      expect(find.text('Turn off 2FA'), findsOneWidget);
    });

    testWidgets('closing the 2FA setup drops the unfinished factor', (
      tester,
    ) async {
      final sec = _FakeSecurity(twoFactorOn: false);
      await tester.pumpWidget(
        _wrap(HomePage(repository: MemoryAccountsRepository(), security: sec)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Security: 2FA, master password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on 2FA'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(sec.cancelled, 'f1');
      expect(sec.twoFactorOn, isFalse);
      expect(find.text('Turn on 2FA'), findsOneWidget);
    });

    testWidgets('turning 2FA off asks for a code first', (tester) async {
      final sec = _FakeSecurity();
      await tester.pumpWidget(
        _wrap(HomePage(repository: MemoryAccountsRepository(), security: sec)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Security: 2FA, master password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off 2FA'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off two-step sign-in?'), findsOneWidget);

      // No auto-submit here: six digits alone do nothing.
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.pumpAndSettle();
      expect(sec.twoFactorOn, isTrue);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Turn off 2FA'));
      await tester.pumpAndSettle();
      expect(sec.twoFactorOn, isFalse);
      expect(find.text('Turn off two-step sign-in?'), findsNothing);
      expect(find.textContaining('2FA is off.'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Turn on 2FA'), findsOneWidget);
    });
  });

  testWidgets('sign-in shows a waiting notice for a scheduled check', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SignInScreen(
          onSignIn: (e, p) async => null,
          onChangeProject: () {},
          notice: 'A scheduled check is waiting. Sign in to let it run.',
        ),
      ),
    );
    expect(
      find.text('A scheduled check is waiting. Sign in to let it run.'),
      findsOneWidget,
    );
    // Desktop test host: no browser-session checkbox.
    expect(find.text('Sign me out when I close the browser'), findsNothing);
  });
}
