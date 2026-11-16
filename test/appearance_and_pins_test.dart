import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/app_theme.dart';
import 'package:mega_keepalive/appearance.dart';
import 'package:mega_keepalive/main.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/prefs.dart';
import 'package:mega_keepalive/screens/home_page.dart';
import 'package:mega_keepalive/widgets/account_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repository.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.theme(), home: child);

/// Emails of the table rows, top to bottom.
List<String> _rowOrder(WidgetTester tester) => tester
    .widgetList<AccountRow>(find.byType(AccountRow))
    .map((r) => r.account.email)
    .toList();

/// The pin / unpin button of the row for [email].
Finder _pinOf(String email) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is AccountRow && w.account.email == email,
  ),
  matching: find.byWidgetPredicate(
    (w) => w is Tooltip && (w.message == 'Pin to top' || w.message == 'Unpin'),
  ),
);

Color? _scaffoldColor(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ??
    Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).scaffoldBackgroundColor;

Future<void> _pickAppearance(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message ?? '').startsWith('Appearance:'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
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
    Appearance.load();
    kDelayMinSec = 0;
    kDelayMaxSec = 0;
  });
  tearDown(() {
    AppTheme.use(Brightness.dark);
    Appearance.mode.value = ThemeMode.dark;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    binding.platformDispatcher.implicitView!
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  group('appearance', () {
    test('dark by default; the choice is saved', () async {
      expect(Prefs.themeMode, ThemeMode.dark);
      expect(AppTheme.isDark, isTrue);
      await Appearance.set(ThemeMode.light);
      expect(Prefs.themeMode, ThemeMode.light);
      await Appearance.set(ThemeMode.system);
      expect(Prefs.themeMode, ThemeMode.system);
    });

    test('a saved choice is applied at start-up', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      await Prefs.init();
      Appearance.load();
      expect(Appearance.mode.value, ThemeMode.light);
      expect(AppTheme.isDark, isFalse);
      expect(AppTheme.bgBase, AppPalette.light.bgBase);
      expect(AppTheme.body.color, AppPalette.light.textPrimary);
    });

    testWidgets('switcher changes the whole app and keeps what you typed', (
      tester,
    ) async {
      await tester.pumpWidget(const MegaKeepAliveApp());
      await tester.pumpAndSettle();
      // No Supabase config saved → the Connect screen.
      final url = find.byType(TextField).first;
      await tester.enterText(url, 'https://abc.supabase.co');
      expect(_scaffoldColor(tester), AppPalette.dark.bgBase);

      await _pickAppearance(tester, 'Light');
      expect(tester.takeException(), isNull);
      expect(AppTheme.isDark, isFalse);
      expect(_scaffoldColor(tester), AppPalette.light.bgBase);
      expect(Prefs.themeMode, ThemeMode.light);
      // Rebuilt in place: the text field kept its value.
      expect(find.text('https://abc.supabase.co'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Connect to Supabase'));
      expect(title.style?.color, AppPalette.light.textPrimary);

      await _pickAppearance(tester, 'Dark');
      expect(_scaffoldColor(tester), AppPalette.dark.bgBase);
      expect(find.text('https://abc.supabase.co'), findsOneWidget);
    });

    testWidgets('"Match system" follows the OS while the app is open', (
      tester,
    ) async {
      final dispatcher = tester.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(const MegaKeepAliveApp());
      await tester.pumpAndSettle();
      expect(AppTheme.isDark, isTrue); // still the saved "Dark"

      await _pickAppearance(tester, 'Match system');
      expect(AppTheme.isDark, isFalse);
      expect(_scaffoldColor(tester), AppPalette.light.bgBase);

      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(AppTheme.isDark, isTrue);
      expect(_scaffoldColor(tester), AppPalette.dark.bgBase);
    });

    testWidgets('home page header has the switcher', (tester) async {
      await tester.pumpWidget(
        _wrap(HomePage(repository: MemoryAccountsRepository())),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Appearance: Dark'), findsOneWidget);
    });
  });

  group('pinned accounts', () {
    List<Account> sample() => [
      for (final e in ['c@x.com', 'a@x.com', 'd@x.com', 'b@x.com'])
        Account(email: e, password: 'pw'),
    ];

    testWidgets('pin moves a row to the top and saves pinned_at', (
      tester,
    ) async {
      final repo = MemoryAccountsRepository(sample());
      await tester.pumpWidget(_wrap(HomePage(repository: repo)));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['c@x.com', 'a@x.com', 'd@x.com', 'b@x.com']);

      // Pin d, then b: pinned rows come first, in the order they were pinned.
      await tester.tap(_pinOf('d@x.com'));
      await tester.pumpAndSettle();
      await tester.tap(_pinOf('b@x.com'));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['d@x.com', 'b@x.com', 'c@x.com', 'a@x.com']);
      expect(repo.rowByEmail('d@x.com')!['pinned_at'], isNotNull);
      expect(repo.rowByEmail('c@x.com')!['pinned_at'], isNull);
      expect(find.byTooltip('Unpin'), findsNWidgets(2));
      expect(find.textContaining('2 / 10 pinned'), findsOneWidget);

      // Sorting by a column keeps pinned rows on top, sorted among themselves.
      await tester.tap(find.text('EMAIL'));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['b@x.com', 'd@x.com', 'a@x.com', 'c@x.com']);

      // Unpin d: back among the others.
      await tester.tap(_pinOf('d@x.com'));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['b@x.com', 'a@x.com', 'c@x.com', 'd@x.com']);
      expect(repo.rowByEmail('d@x.com')!['pinned_at'], isNull);
      expect(find.textContaining('1 / 10 pinned'), findsOneWidget);
    });

    testWidgets('no more than 10 pinned', (tester) async {
      tester.view.physicalSize = const Size(1440, 1600); // all 11 rows built
      final t0 = DateTime(2026, 11, 1);
      final repo = MemoryAccountsRepository([
        for (var i = 0; i < 10; i++)
          Account(
            email: 'p$i@x.com',
            password: 'pw',
            pinnedAt: t0.add(Duration(minutes: i)),
          ),
        Account(email: 'free@x.com', password: 'pw'),
      ]);
      await tester.pumpWidget(_wrap(HomePage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 / 10 pinned'), findsOneWidget);

      await tester.tap(_pinOf('free@x.com'));
      await tester.pump();
      expect(
        find.text('You can pin up to 10 accounts. Unpin one first.'),
        findsOneWidget,
      );
      expect(repo.rowByEmail('free@x.com')!['pinned_at'], isNull);
      expect(repo.updateCalls, 0);
    });

    testWidgets('a failed save puts the row back', (tester) async {
      final repo = MemoryAccountsRepository(sample());
      await tester.pumpWidget(_wrap(HomePage(repository: repo)));
      await tester.pumpAndSettle();
      repo.failNextUpdate = Exception('column "pinned_at" does not exist');
      await tester.tap(_pinOf('d@x.com'));
      await tester.pumpAndSettle();
      expect(_rowOrder(tester), ['c@x.com', 'a@x.com', 'd@x.com', 'b@x.com']);
      expect(find.byTooltip('Unpin'), findsNothing);
      expect(find.textContaining("Couldn't pin d@x.com"), findsOneWidget);
    });

    test('pinned_at is read from the row', () {
      final a = Account.fromRow({
        'email': 'a@x.com',
        'pinned_at': '2026-11-16T09:30:00Z',
      });
      expect(a.pinned, isTrue);
      expect(a.pinnedAt!.toUtc(), DateTime.utc(2026, 11, 16, 9, 30));
      expect(Account.fromRow({'email': 'b@x.com'}).pinned, isFalse);
    });
  });
}
