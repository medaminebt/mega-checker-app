import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/account_import.dart';
import 'package:mega_keepalive/models.dart';

void main() {
  group('parsePastedList', () {
    test('accepts colon, comma, semicolon, tab, space and pipe', () {
      final r = AccountImport.parsePastedList(
        'a@x.com:pw1\n'
        'b@x.com,pw2\n'
        'c@x.com;pw3\n'
        'd@x.com\tpw4\n'
        'e@x.com   pw5\n'
        'f@x.com | pw6\n',
      );
      expect(r.accounts.map((a) => a.email), [
        'a@x.com',
        'b@x.com',
        'c@x.com',
        'd@x.com',
        'e@x.com',
        'f@x.com',
      ]);
      expect(r.accounts.map((a) => a.password), [
        'pw1',
        'pw2',
        'pw3',
        'pw4',
        'pw5',
        'pw6',
      ]);
      expect(r.skippedLines, isEmpty);
    });

    test('password keeps separators after the first one', () {
      final r = AccountImport.parsePastedList('a@x.com:pa:ss,word with space');
      expect(r.accounts.single.password, 'pa:ss,word with space');
    });

    test('lower-cases + trims emails, de-duplicates (last wins)', () {
      final r = AccountImport.parsePastedList(
        '  Me@Gmail.com:old \n'
        'me@gmail.com:new\n',
      );
      expect(r.accounts.single.email, 'me@gmail.com');
      expect(r.accounts.single.password, 'new');
      expect(r.duplicates, 1);
    });

    test('blank / # lines ignored; junk lines reported by number', () {
      final r = AccountImport.parsePastedList(
        '# my accounts\n'
        '\n'
        'email,password\n' // header row: no @ → skipped
        'a@x.com:pw\n'
        'not an account\n'
        'b@x.com\n', // no password
      );
      expect(r.accounts.length, 1);
      expect(r.skippedLines, [3, 5, 6]);
    });
  });

  group('plan', () {
    final existing = [
      Account(id: '1', email: 'a@x.com', password: 'old', megaKey: 'K1'),
      Account(id: '2', email: 'b@x.com', password: 'same'),
    ];

    test('new emails inserted; known ones updated only when overwrite', () {
      final incoming = [
        Account(email: 'A@x.com', password: 'new'),
        Account(email: 'b@x.com', password: 'same'),
        Account(email: 'c@x.com', password: 'pc'),
      ];
      final p = AccountImport.plan(existing, incoming, overwrite: true);
      expect(p.toInsert.map((a) => a.email), ['c@x.com']);
      expect(p.toUpdate.length, 1);
      expect(p.toUpdate[existing[0]], {'password': 'new'});
      expect(p.unchanged, 1); // b: same password

      final keep = AccountImport.plan(existing, incoming, overwrite: false);
      expect(keep.toInsert.length, 1);
      expect(keep.toUpdate, isEmpty);
      expect(keep.unchanged, 2);
    });

    test('empty incoming key / notes never wipe stored values', () {
      final p = AccountImport.plan(existing, [
        Account(email: 'a@x.com', password: 'old', megaKey: '', notes: ''),
      ], overwrite: true);
      expect(p.toUpdate, isEmpty);
      expect(p.unchanged, 1);
    });
  });
}
