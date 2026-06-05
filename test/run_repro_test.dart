import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/app_theme.dart';
import 'package:mega_keepalive/csv_import.dart';
import 'package:mega_keepalive/main.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/paths.dart';

void main() {
  setUp(() {
    final v = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher.implicitView!;
    v.physicalSize = const Size(1200, 800);
    v.devicePixelRatio = 1.0;
    kDelayMinSec = 0;
    kDelayMaxSec = 0;
    MegaService.overrideKeepAlive =
        (a) async => LoginResult(LoginOutcome.success, 'ok');
  });
  tearDown(() {
    MegaService.overrideKeepAlive = null;
    // The run writes to the real database path; don't leave test data behind.
    final db = File(AppPaths.dbPath);
    if (db.existsSync()) db.deleteSync();
    AppPaths.lastCsvPath = null;
  });

  testWidgets('Test all logins on the (corrupted) CSV does not crash',
      (tester) async {
    // The exact content the user reported, including the chat-text junk lines.
    const csv = 'email,password,notes\n'
        'example1@example.com,fakepass1,[2026-06-04] login OK\n'
        'example2@example.com,fakepass2,backup account\n'
        '\n\n\n'
        '* Will you use FlutterFlow Similar UI  (similar to the UIs provided by flutter flow , that is what I mean : for example they have primary color , buttons shape...etc ) , also onces the csv uploaded\n'
        '* Will you push this project to my Github repository (private)? exclude the .csv files\n';
    final accounts = CsvImport.parseString(csv);

    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme(),
        home: HomePage(debugAccounts: accounts)));
    await tester.pump();

    await tester.tap(find.text('Test all logins'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}
