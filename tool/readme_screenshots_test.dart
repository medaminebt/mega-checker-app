// Renders the README screenshots (docs/screenshots/*.png) from the real app
// widgets, with made-up sample accounts, the bundled Lexend font and a
// macOS-style window / phone frame. Nothing touches Supabase or MEGA.
//
//   flutter test tool/readme_screenshots_test.dart
//
// Re-run it after UI changes and commit the updated PNGs.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/app_theme.dart';
import 'package:mega_keepalive/appearance.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/prefs.dart';
import 'package:mega_keepalive/screens/home_page.dart';
import 'package:mega_keepalive/platform/desktop.dart';
import 'package:mega_keepalive/screens/mfa_screens.dart';
import 'package:mega_keepalive/screens/sign_in_screen.dart';
import 'package:mega_keepalive/screens/vault_screens.dart';
import 'package:mega_keepalive/security/security_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/memory_repository.dart';

const _outDir = 'docs/screenshots';
const _pixelRatio = 2.0; // retina-sharp
const _margin = 40.0; // room for the window shadow
const _gib = 1024 * 1024 * 1024;
const _mib = 1024 * 1024;

// ---- fonts -------------------------------------------------------------------

String get _flutterRoot {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent; // …/bin/cache/artifacts/…
  while (dir.parent.path != dir.path) {
    if (Directory(
      '${dir.path}/bin/cache/artifacts/material_fonts',
    ).existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  throw StateError('Set FLUTTER_ROOT to your Flutter SDK folder.');
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final lexend = [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/Lexend-$w.ttf',
  ];
  await _loadFont('Lexend', lexend);
  // Menlo isn't bundled; passwords / keys are hidden as dots anyway.
  await _loadFont('Menlo', lexend);
  await _loadFont('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

// ---- sample data ---------------------------------------------------------------

List<Account> _sampleAccounts() {
  final now = DateTime.now();
  DateTime ago({int days = 0, int hours = 0}) =>
      now.subtract(Duration(days: days, hours: hours));
  return [
    Account(
      email: 'photo.vault@example.com',
      password: 'Sample-Passw0rd',
      megaKey: 'aB3dE5fG7hJ9kL1mN3pQ5r',
      lastStatus: 'ok',
      lastLoginAt: ago(days: 2, hours: 3),
      storageUsedBytes: (16.4 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: (1.8 * _gib).round(),
      storageVersionsBytes: 340 * _mib,
      uploadFolderUrl: 'https://mega.nz/filerequest/Xq7Lp2Ab',
      notes: 'Family photos 2019–2024\nRenew Pro in March',
      pinnedAt: ago(days: 30),
    ),
    Account(
      email: 'work.backup@example.com',
      password: 'Sample-Passw0rd',
      megaKey: 'aB3dE5fG7hJ9kL1mN3pQ5r',
      lastStatus: 'ok',
      lastLoginAt: ago(hours: 5),
      storageUsedBytes: (7.2 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: 0,
      storageVersionsBytes: 96 * _mib,
      uploadFolderUrl: 'https://mega.nz/filerequest/Rk3Tz9Qw',
      notes: 'Client projects',
      pinnedAt: ago(days: 20),
    ),
    Account(
      email: 'music.library@example.org',
      password: 'Sample-Passw0rd',
      lastStatus: 'failed',
      lastLoginAt: ago(days: 41),
      storageUsedBytes: (19.1 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: (4.2 * _gib).round(),
      storageVersionsBytes: (1.1 * _gib).round(),
      notes: 'Password changed?',
    ),
    Account(
      email: 'family.videos@example.net',
      password: 'Sample-Passw0rd',
      megaKey: 'aB3dE5fG7hJ9kL1mN3pQ5r',
      lastStatus: 'ok',
      lastLoginAt: ago(days: 6),
      storageUsedBytes: (2.6 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: 0,
      storageVersionsBytes: 0,
      uploadFolderUrl: 'https://mega.nz/filerequest/Mv8Hc4Ls',
    ),
    Account(
      email: 'projects.2025@example.com',
      password: 'Sample-Passw0rd',
      lastStatus: 'ok',
      lastLoginAt: ago(days: 12),
      storageUsedBytes: (11.8 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: 512 * _mib,
      storageVersionsBytes: 12 * _mib,
      notes: 'Design files',
    ),
    Account(
      email: 'old.phone@example.org',
      password: 'Sample-Passw0rd',
      megaKey: 'aB3dE5fG7hJ9kL1mN3pQ5r',
      lastStatus: 'ok',
      lastLoginAt: ago(days: 1),
      storageUsedBytes: (0.4 * _gib).round(),
      storageTotalBytes: 20 * _gib,
      storageRubbishBytes: 0,
      storageVersionsBytes: 0,
      uploadFolderUrl: 'https://mega.nz/filerequest/Pw2Yn6Dg',
    ),
    Account(email: 'documents@example.net', password: 'x'),
    Account(email: 'spare.01@example.com', password: 'x'),
  ];
}

Future<void> _prefs([Map<String, Object> values = const {}]) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(values);
  await Prefs.init();
}

// ---- frames --------------------------------------------------------------------

Widget _materialApp(Widget home, Size size) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.theme(),
  // The app lays itself out for the frame's content size, not the canvas.
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(size: size),
    child: child!,
  ),
  home: home,
);

const _titleBarHeight = 30.0;

/// macOS-style window: title bar with traffic lights, rounded corners, shadow.
class _MacWindow extends StatelessWidget {
  const _MacWindow({required this.size, required this.child});

  final Size size;
  final Widget child;

  static Size outer(Size content) => Size(
    content.width + 2 * _margin,
    content.height + _titleBarHeight + 2 * _margin,
  );

  @override
  Widget build(BuildContext context) {
    Widget light(Color c) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    const radius = BorderRadius.all(Radius.circular(12));
    return Padding(
      padding: const EdgeInsets.all(_margin),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: AppTheme.isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size.width,
                  height: _titleBarHeight,
                  color: AppTheme.isDark
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFFE7E7EA),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 13,
                        child: Row(
                          children: [
                            light(const Color(0xFFFF5F57)),
                            const SizedBox(width: 8),
                            light(const Color(0xFFFEBC2E)),
                            const SizedBox(width: 8),
                            light(const Color(0xFF28C840)),
                          ],
                        ),
                      ),
                      Text(
                        'mega-checker-app',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.isDark
                              ? const Color(0xFF9A9AA0)
                              : const Color(0xFF6E6E73),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.fromSize(size: size, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _statusBar = 44.0, _urlBar = 48.0, _homeBar = 26.0, _bezel = 12.0;
const _rim = 2.0; // phone outline width

/// Phone with a browser address bar — the web version on a phone.
class _Phone extends StatelessWidget {
  const _Phone({required this.size, required this.child});

  final Size size;
  final Widget child;

  static Size outer(Size content) => Size(
    content.width + 2 * (_bezel + _rim + _margin),
    content.height +
        _statusBar +
        _urlBar +
        _homeBar +
        2 * (_bezel + _rim + _margin),
  );

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFF2F2F2);
    const grey = Color(0xFF9A9AA0);
    return Padding(
      padding: const EdgeInsets.all(_margin),
      child: Container(
        padding: const EdgeInsets.all(_bezel),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0B0C),
          borderRadius: BorderRadius.circular(56),
          border: Border.all(color: const Color(0xFF3A3A3C), width: _rim),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size.width,
                height: _statusBar,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '9:41',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.signal_cellular_alt, size: 16, color: white),
                        SizedBox(width: 5),
                        Icon(Icons.wifi, size: 16, color: white),
                        SizedBox(width: 5),
                        Icon(Icons.battery_full, size: 18, color: white),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: size.width,
                height: _urlBar,
                color: const Color(0xFF121212),
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF262628),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded, size: 13, color: grey),
                      SizedBox(width: 6),
                      Text(
                        'mega.example.com',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.5,
                          color: white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox.fromSize(size: size, child: child),
              Container(
                width: size.width,
                height: _homeBar,
                color: Colors.black,
                alignment: Alignment.center,
                child: Container(
                  width: 134,
                  height: 5,
                  decoration: BoxDecoration(
                    color: white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- capture -------------------------------------------------------------------

final _boundary = GlobalKey();

/// Pump [frame] (whose outer size is [outer]) as the whole test view.
Future<void> _show(WidgetTester tester, Size outer, Widget frame) async {
  tester.view.physicalSize = outer * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(key: _boundary, child: frame),
      ),
    ),
  );
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir/$name.png').writeAsBytesSync(bytes!);
  // ignore: avoid_print
  print('wrote $_outDir/$name.png');
}

/// Desktop shots show the Scheduled checks and Security header buttons.
Widget _home(MemoryAccountsRepository repo, {bool desktop = true}) => HomePage(
  repository: repo,
  userEmail: 'me@example.com',
  projectHost: 'abcdefghijkl.supabase.co',
  onSignOut: () async {},
  onChangeProject: () async {},
  security: desktop ? _SampleSecurity() : null,
);

/// Made-up secret (RFC 4648 example text), not a real account.
const _sampleTotp = TotpSetup(
  factorId: 'sample',
  uri:
      'otpauth://totp/mega-checker-app:me%40example.com'
      '?secret=JBSWY3DPEHPK3PXP&issuer=mega-checker-app',
  secret: 'JBSWY3DPEHPK3PXP',
);

/// Stand-in for the app gate's security settings (nothing is stored).
class _SampleSecurity implements SecurityController {
  @override
  bool get twoFactorOn => true;
  @override
  String get twoFactorSummary => 'On · authenticator app';
  @override
  Future<TotpSetup> startTwoFactor() async => _sampleTotp;
  @override
  Future<String?> confirmTwoFactor(String factorId, String code) async => null;
  @override
  Future<void> cancelTwoFactor(String factorId) async {}
  @override
  Future<String?> turnOffTwoFactor(String code) async => null;
  @override
  Future<String?> changeMasterPassword(String current, String next) async =>
      null;
  @override
  Future<(String?, String?)> newRecoveryKey() async => (null, null);
  @override
  bool get canRemember => true;
  @override
  String get deviceName => 'this Mac';
  @override
  String get rememberStoreName => 'your macOS login Keychain';
  @override
  Future<bool> isRemembered() async => true;
  @override
  Future<String?> setRemembered(bool on) async => null;
  @override
  bool get canSignOutOnBrowserClose => false;
  @override
  bool get signOutOnBrowserClose => false;
  @override
  Future<void> setSignOutOnBrowserClose(bool on) async {}
}

// ---- screenshots -----------------------------------------------------------------

/// A screenshot test. flutter_test draws shadows without blur by default; the
/// window shadow and the logo's glow need the real thing, and the flag must
/// be restored before the test ends.
void _shot(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  const desktop = Size(1440, 880);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  tearDown(() {
    MegaService.overrideKeepAlive = null;
    MegaService.debugSupported = null;
  });

  _shot('home', (tester) async {
    await _prefs({'sort_column': 'storage', 'sort_asc': false});
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _MacWindow.outer(desktop),
      _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'home');
  });

  _shot('home-light', (tester) async {
    await _prefs({'sort_column': 'storage', 'sort_asc': false});
    AppTheme.use(Brightness.light);
    Appearance.mode.value = ThemeMode.light;
    try {
      final repo = MemoryAccountsRepository(_sampleAccounts());
      await _show(
        tester,
        _MacWindow.outer(desktop),
        _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
      );
      await tester.pumpAndSettle();
      await _save(tester, 'home-light');
    } finally {
      AppTheme.use(Brightness.dark);
      Appearance.mode.value = ThemeMode.dark;
    }
  });

  _shot('checking', (tester) async {
    await _prefs();
    final hang = Completer<LoginResult>();
    var calls = 0;
    MegaService.overrideKeepAlive = (a) {
      calls++;
      if (calls <= 2) {
        return Future.value(
          LoginResult(
            LoginOutcome.success,
            'ok',
            storage: a.storage ?? StorageInfo(3 * _gib, 20 * _gib),
          ),
        );
      }
      return hang.future; // third account stays "Checking…"
    };
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _MacWindow.outer(desktop),
      _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check all accounts'));
    for (var i = 0; i < 2; i++) {
      await tester.pump();
      await tester.pump(const Duration(seconds: 30)); // skip the pause
    }
    await tester.pump(const Duration(milliseconds: 400));
    await _save(tester, 'checking');

    // Wind the run down so no timers are left behind.
    await tester.tap(find.text('Stop'));
    hang.complete(LoginResult(LoginOutcome.success, 'ok'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 10));
  });

  _shot('notes', (tester) async {
    await _prefs();
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _MacWindow.outer(desktop),
      _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Family photos 2019–2024  ·  Renew Pro in March'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Family photos 2019–2024\n'
      'Renew Pro in March\n'
      'Recovery key is also in the password manager\n'
      '\n'
      'Upload new albums through the upload folder link.',
    );
    await tester.pumpAndSettle();
    await _save(tester, 'notes');
  });

  _shot('paste-list', (tester) async {
    await _prefs();
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _MacWindow.outer(desktop),
      _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste list'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'photo.vault@example.com:N3w-Passw0rd!\n'
      'new.account1@example.org:Gx7#kq2LmP\n'
      'new.account2@example.org,Vb9\$wr4TzQ\n'
      'new.account3@example.net Hp2!sd8KjN\n'
      'this line is not an account\n'
      'new.account4@example.com;Rt5&nm3XcV',
    );
    await tester.pumpAndSettle();
    await _save(tester, 'paste-list');
  });

  _shot('schedule', (tester) async {
    await _prefs({
      'check_schedule':
          '{"kind":"weekly","weekday":1,"day_of_month":1,"hour":10,"minute":0}',
    });
    AppInstance.debugExecutable =
        '/Applications/mega-checker-app.app/Contents/MacOS/mega-checker-app';
    try {
      final repo = MemoryAccountsRepository(_sampleAccounts());
      await _show(
        tester,
        _MacWindow.outer(desktop),
        _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scheduled checks'));
      await tester.pump();
      // The dialog asks the OS whether a schedule is installed and reads the
      // run log (real file I/O, one step after another).
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await _save(tester, 'schedule');
    } finally {
      AppInstance.debugExecutable = null;
    }
  });
  _shot('two-factor', (tester) async {
    await _prefs();
    // Security › Turn on 2FA, over the account list.
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _MacWindow.outer(desktop),
      _MacWindow(size: desktop, child: _materialApp(_home(repo), desktop)),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(HomePage));
    unawaited(
      showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => MfaEnrolDialog(
          onStart: () async => _sampleTotp,
          onVerify: (_, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'two-factor');
  });
  _shot('unlock', (tester) async {
    await _prefs();
    const size = Size(1100, 760);
    await _show(
      tester,
      _MacWindow.outer(size),
      _MacWindow(
        size: size,
        child: _materialApp(
          UnlockScreen(
            onUnlock: (_, _) async => null,
            onRecover: (_, _, _) async => null,
            onReset: () async => null,
            onSignOut: () {},
            email: 'me@example.com',
            canRemember: true,
            deviceName: 'this Mac',
          ),
          size,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'unlock');
  });
  _shot('sign-in', (tester) async {
    await _prefs({'last_sign_in_email': 'me@example.com'});
    const size = Size(1100, 760);
    await _show(
      tester,
      _MacWindow.outer(size),
      _MacWindow(
        size: size,
        child: _materialApp(
          SignInScreen(
            projectHost: 'abcdefghijkl.supabase.co',
            onSignIn: (_, _) async => null,
            onChangeProject: () {},
          ),
          size,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'sign-in');
  });

  _shot('phone (web version)', (tester) async {
    await _prefs();
    MegaService.debugSupported = false; // the browser build can't run checks
    const size = Size(390, 760);
    final repo = MemoryAccountsRepository(_sampleAccounts());
    await _show(
      tester,
      _Phone.outer(size),
      _Phone(
        size: size,
        child: _materialApp(_home(repo, desktop: false), size),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -340),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'phone');
  });
}
