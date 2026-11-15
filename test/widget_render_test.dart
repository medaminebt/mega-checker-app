import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/app_theme.dart';
import 'package:mega_keepalive/links.dart';
import 'package:mega_keepalive/main.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/prefs.dart';
import 'package:mega_keepalive/screens/home_page.dart';
import 'package:mega_keepalive/widgets/account_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repository.dart';

Widget _app(MemoryAccountsRepository repo) => MaterialApp(
  theme: AppTheme.theme(),
  home: HomePage(repository: repo, userEmail: 'me@example.com'),
);

void main() {
  setUp(() async {
    final v = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    // The app's default window size.
    v.physicalSize = const Size(1440, 880);
    v.devicePixelRatio = 1.0;
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    kDelayMinSec = 0;
    kDelayMaxSec = 0;
  });
  tearDown(() {
    MegaService.overrideKeepAlive = null;
    Links.overrideOpen = null;
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!
        .resetPhysicalSize();
  });

  testWidgets('first launch (no Supabase config) shows the setup screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MegaKeepAliveApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Connect to Supabase'), findsOneWidget);
    expect(find.text('Save & connect'), findsOneWidget);
  });

  testWidgets('empty database shows the empty state', (tester) async {
    await tester.pumpWidget(_app(MemoryAccountsRepository()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No MEGA accounts yet'), findsOneWidget);
  });

  testWidgets('accounts table renders rows, last login and storage', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(
        email: 'a@gmail.com',
        password: 'x',
        megaKey: 'KEY',
        lastStatus: 'ok',
        lastLoginAt: DateTime.now().subtract(const Duration(days: 3)),
        storageUsedBytes: 1610612736,
        storageTotalBytes: 21474836480,
      ),
      Account(email: 'b@gmail.com', password: 'y'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AccountRow), findsNWidgets(2));
    expect(find.text('a@gmail.com'), findsOneWidget);
    expect(find.textContaining('3 d ago'), findsOneWidget);
    expect(find.textContaining('1.5 GB / 20 GB'), findsWidgets);
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('STATUS header cycles unsorted → asc → desc', (tester) async {
    await tester.pumpWidget(
      _app(
        MemoryAccountsRepository([
          Account(email: 'a@x.com', password: 'p'),
          Account(email: 'b@x.com', password: 'q'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // STATUS, EMAIL, LAST LOGIN and STORAGE are sortable → four "unsorted"
    // icons.
    expect(find.byIcon(Icons.unfold_more_rounded), findsNWidgets(4));
    await tester.tap(find.text('STATUS'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await tester.tap(find.text('STATUS'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(Prefs.sortColumn, 'status');
    expect(Prefs.sortAsc, isFalse);
  });

  testWidgets('delete asks for confirmation; Cancel keeps the row', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
      Account(email: 'b@x.com', password: 'q'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountRow), findsNWidgets(2));
    expect(repo.rows.length, 2);
  });

  testWidgets('Paste list saves new accounts and updates known passwords', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(email: 'known@x.com', password: 'old'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paste list'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'new1@x.com:pw1\nNEW2@x.com, pw2\nknown@x.com:fresh\ngarbage line\n',
    );
    await tester.pump();
    expect(find.text('2 new'), findsOneWidget);
    expect(find.textContaining('skipped line 4'), findsOneWidget);

    await tester.tap(find.text('Save 2 new · update 1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AccountRow), findsNWidgets(3));
    expect(repo.rows.length, 3);
    expect(repo.rowByEmail('new2@x.com')!['password'], 'pw2');
    expect(repo.rowByEmail('known@x.com')!['password'], 'fresh');
  });

  testWidgets(
    'Check all stores last login + storage, and failures, in the database',
    (tester) async {
      MegaService.overrideKeepAlive = (a) async => a.email == 'good@x.com'
          ? LoginResult(
              LoginOutcome.success,
              'ok',
              storage: const StorageInfo(5242880, 21474836480),
            )
          : LoginResult(LoginOutcome.wrongCredentials, 'nope');
      final repo = MemoryAccountsRepository([
        Account(email: 'good@x.com', password: 'p'),
        Account(email: 'bad@x.com', password: 'q'),
      ]);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check all accounts'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      final good = repo.rowByEmail('good@x.com')!;
      expect(good['last_status'], 'ok');
      expect(good['last_login_at'], isNotNull);
      expect(good['storage_used_bytes'], 5242880);
      expect(good['storage_total_bytes'], 21474836480);

      final bad = repo.rowByEmail('bad@x.com')!;
      expect(bad['last_status'], 'failed');
      expect(bad['last_error'], 'Wrong email or password');
      expect(bad['last_login_at'], isNull);

      expect(find.textContaining('5 MB / 20 GB'), findsWidgets);
      expect(find.text('All changes saved to Supabase'), findsOneWidget);
    },
  );

  testWidgets('editing the MEGA key saves it; a failed save offers Retry', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final keyField = find.widgetWithText(TextField, 'paste MEGA key…');
    repo.failNextUpdate = Exception('SocketException: offline');
    await tester.enterText(keyField, 'MY-RECOVERY-KEY');
    await tester.pump(const Duration(seconds: 1)); // debounce → flush fails
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(repo.rows.values.single['mega_key'], '');

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.rows.values.single['mega_key'], 'MY-RECOVERY-KEY');
    expect(find.text('All changes saved to Supabase'), findsOneWidget);
  });

  testWidgets('Sign out waits for a save that is still in flight', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ])..updateDelay = const Duration(seconds: 2);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme(),
        home: HomePage(
          repository: repo,
          onSignOut: () async => repo.log.add('signed out'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'paste MEGA key…'),
      'KEY',
    );
    await tester.pump(const Duration(milliseconds: 900)); // save starts
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump(const Duration(milliseconds: 300)); // dialog opens
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
    await tester.pump(const Duration(seconds: 3)); // slow save finishes
    await tester.pumpAndSettle();

    expect(repo.log, ['update mega_key', 'signed out']);
  });

  testWidgets('Sign out asks "are you sure?"; Cancel keeps you signed in', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme(),
        home: HomePage(
          repository: MemoryAccountsRepository(),
          userEmail: 'me@example.com',
          onSignOut: () async => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.textContaining('me@example.com'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsNothing);
    expect(signedOut, isFalse);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  List<String> shownEmails(WidgetTester tester) => tester
      .widgetList<AccountRow>(find.byType(AccountRow))
      .map((r) => r.account.email)
      .toList();

  testWidgets('STORAGE header sorts by used storage, unmeasured last', (
    tester,
  ) async {
    const gib = 1024 * 1024 * 1024;
    await tester.pumpWidget(
      _app(
        MemoryAccountsRepository([
          Account(
            email: 'big@x.com',
            password: 'p',
            storageUsedBytes: 5 * gib,
            storageTotalBytes: 20 * gib,
          ),
          Account(email: 'never@x.com', password: 'p'),
          Account(
            email: 'small@x.com',
            password: 'p',
            storageUsedBytes: gib,
            storageTotalBytes: 20 * gib,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('STORAGE'));
    await tester.pump();
    expect(shownEmails(tester), ['small@x.com', 'big@x.com', 'never@x.com']);
    expect(Prefs.sortColumn, 'storage');

    await tester.tap(find.text('STORAGE'));
    await tester.pump();
    expect(shownEmails(tester), ['big@x.com', 'small@x.com', 'never@x.com']);

    // Sorting by last login is still there.
    await tester.tap(find.text('LAST LOGIN'));
    await tester.pump();
    expect(Prefs.sortColumn, 'login');
  });

  testWidgets('Recheck failed checks only the accounts that failed', (
    tester,
  ) async {
    final checked = <String>[];
    MegaService.overrideKeepAlive = (a) async {
      checked.add(a.email);
      return LoginResult(LoginOutcome.success, 'ok');
    };
    final repo = MemoryAccountsRepository([
      Account(email: 'ok@x.com', password: 'p', lastStatus: 'ok'),
      Account(email: 'f1@x.com', password: 'p', lastStatus: 'failed'),
      Account(email: 'new@x.com', password: 'p'),
      Account(email: 'f2@x.com', password: 'p', lastStatus: 'failed'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recheck failed (2)'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(checked, ['f1@x.com', 'f2@x.com']);
    expect(repo.rowByEmail('f1@x.com')!['last_status'], 'ok');
    expect(repo.rowByEmail('new@x.com')!['last_status'], isNull);
    // Nothing failed any more → the button is disabled.
    final button = find.widgetWithText(OutlinedButton, 'Recheck failed');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
  });

  testWidgets('upload folder URL saves and opens in the browser', (
    tester,
  ) async {
    final opened = <Uri>[];
    Links.overrideOpen = (uri) async {
      opened.add(uri);
      return true;
    };
    final repo = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final open = find.byIcon(Icons.open_in_new_rounded);
    expect(tester.widget<IconButton>(_iconButton(open)).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'paste upload link…'),
      ' https://mega.nz/filerequest/AbC123 ',
    );
    await tester.pump(const Duration(seconds: 1)); // debounce → saved
    expect(
      repo.rows.values.single['upload_folder_url'],
      'https://mega.nz/filerequest/AbC123',
    );

    await tester.tap(open);
    await tester.pump();
    expect(opened.single.toString(), 'https://mega.nz/filerequest/AbC123');
  });

  testWidgets('notes open in a big editor and save to the database', (
    tester,
  ) async {
    final repo = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    final editor = tester.widget<TextField>(find.byType(TextField).last);
    expect(editor.minLines, 10);

    await tester.enterText(
      find.byType(TextField).last,
      'Photos backup\nRenew in March',
    );
    await tester.pump(); // enables "Save notes"
    await tester.tap(find.text('Save notes'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1)); // save debounce

    expect(find.text('Notes'), findsNothing);
    expect(repo.rows.values.single['notes'], 'Photos backup\nRenew in March');
    expect(find.text('Photos backup  ·  Renew in March'), findsOneWidget);
  });

  for (final size in const [Size(1024, 700), Size(390, 844)]) {
    testWidgets('renders without overflow at ${size.width.toInt()}×'
        '${size.height.toInt()} (small window / phone browser)', (
      tester,
    ) async {
      final v = tester.view;
      v.physicalSize = size;
      v.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        _app(
          MemoryAccountsRepository([
            for (var i = 0; i < 8; i++)
              Account(
                email: 'account$i@example.com',
                password: 'p',
                lastStatus: i.isEven ? 'ok' : 'failed',
                storageUsedBytes: i * 1073741824,
                storageTotalBytes: 21474836480,
              ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AccountRow), findsWidgets);
    });
  }
}

Finder _iconButton(Finder icon) =>
    find.ancestor(of: icon, matching: find.byType(IconButton));
