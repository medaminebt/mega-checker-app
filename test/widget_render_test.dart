import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/main.dart';
import 'package:mega_keepalive/models.dart';

void main() {
  // Render at the app's real window size (min window is 820px wide).
  setUp(() {
    final v = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .implicitView!;
    v.physicalSize = const Size(1200, 800);
    v.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher.implicitView!
        .resetPhysicalSize();
  });

  testWidgets('empty screen renders without exceptions', (tester) async {
    await tester.pumpWidget(const MegaKeepAliveApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('accounts table renders without exceptions', (tester) async {
    final accounts = [
      Account(email: 'a@gmail.com', password: 'x', notes: 'main'),
      Account(email: 'b@gmail.com', password: 'y', notes: ''),
    ];
    await tester.pumpWidget(MaterialApp(
      home: HomePage(debugAccounts: accounts),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Test all logins'), findsOneWidget);
    // Two editable rows → email cells show their values in TextFields.
    expect(find.byType(EditableAccountRow), findsNWidgets(2));
    expect(find.text('a@gmail.com'), findsOneWidget);
    // email + password + notes fields per row.
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('STATUS header cycles unsorted → asc → desc', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(debugAccounts: [
        Account(email: 'a@x.com', password: 'p'),
        Account(email: 'b@x.com', password: 'q'),
      ]),
    ));
    await tester.pump();
    // Both STATUS and EMAIL are sortable → two "unsorted" icons initially.
    expect(find.byIcon(Icons.unfold_more_rounded), findsNWidgets(2));
    await tester.tap(find.text('STATUS'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await tester.tap(find.text('STATUS'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('EMAIL header is sortable too', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(debugAccounts: [
        Account(email: 'b@x.com', password: 'p'),
        Account(email: 'a@x.com', password: 'q'),
      ]),
    ));
    await tester.pump();
    await tester.tap(find.text('EMAIL'));
    await tester.pump();
    // EMAIL now shows the ascending arrow; STATUS stays unsorted.
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
  });

  testWidgets('delete asks for confirmation; Cancel keeps the row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(debugAccounts: [
        Account(email: 'a@x.com', password: 'p'),
        Account(email: 'b@x.com', password: 'q'),
      ]),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableAccountRow), findsNWidgets(2)); // nothing deleted
  });
}
