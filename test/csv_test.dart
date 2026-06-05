import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/csv_import.dart';
import 'package:mega_keepalive/models.dart';

void main() {
  test('parse: headers, blank rows skipped, quoted commas, BOM tolerated', () {
    const csv = '﻿email,password,notes\n' // leading BOM
        'one@x.com,secret1,main\n'
        'two@x.com,"pa,ss",backup\n'
        ',blank-skipped,\n';
    final accounts = CsvImport.parseString(csv);
    expect(accounts.length, 2);
    expect(accounts[0].email, 'one@x.com');
    expect(accounts[1].password, 'pa,ss');
    expect(accounts[1].notes, 'backup');
  });

  test('prose/junk lines without an @ in the email are skipped', () {
    const csv = 'email,password,notes\n'
        'real@x.com,pw,keep me\n'
        '* Will you use FlutterFlow , that is what I mean , buttons shape\n'
        '* Will you push this project to my Github repo\n';
    final a = CsvImport.parseString(csv);
    expect(a.length, 1);
    expect(a[0].email, 'real@x.com');
  });

  test('parse without required columns throws', () {
    expect(() => CsvImport.parseString('foo,bar\n1,2\n'),
        throwsA(isA<FormatException>()));
  });

  test('export round-trip preserves notes (incl. ones with separators)', () {
    final rows = [
      Account(email: 'a@x.com', password: 'p1', notes: '[2026-06-04 10:00:00] login OK'),
      Account(email: 'b@x.com', password: 'p,2', notes: 'note | [2026-06-04 10:05:00] login FAILED: wrong email or password'),
    ];
    final text = CsvImport.toCsvString(rows);
    final back = CsvImport.parseString(text);
    expect(back.length, 2);
    expect(back[0].notes, '[2026-06-04 10:00:00] login OK');
    expect(back[1].password, 'p,2'); // comma survives the round-trip
    expect(back[1].notes, contains('login FAILED'));
  });
}
