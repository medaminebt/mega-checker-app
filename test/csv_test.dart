import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/csv_import.dart';
import 'package:mega_keepalive/models.dart';

void main() {
  test('parse: headers, blank rows skipped, quoted commas, BOM tolerated', () {
    const csv =
        '﻿email,password,notes\n' // leading BOM
        'one@x.com,secret1,main\n'
        'two@x.com,"pa,ss",backup\n'
        ',blank-skipped,\n';
    final accounts = CsvImport.parseString(csv);
    expect(accounts.length, 2);
    expect(accounts[0].email, 'one@x.com');
    expect(accounts[1].password, 'pa,ss');
    expect(accounts[1].notes, 'backup');
    expect(accounts[1].megaKey, '');
  });

  test('mega_key column is recognised (several header spellings)', () {
    for (final h in ['mega_key', 'MEGA Key', 'recovery_key']) {
      final a = CsvImport.parseString('email,password,$h\na@x.com,pw,KEY123\n');
      expect(a.single.megaKey, 'KEY123', reason: 'header "$h"');
    }
  });

  test('prose/junk lines without an @ in the email are skipped', () {
    const csv =
        'email,password,notes\n'
        'real@x.com,pw,keep me\n'
        '* Will you use FlutterFlow , that is what I mean , buttons shape\n';
    final a = CsvImport.parseString(csv);
    expect(a.length, 1);
    expect(a[0].email, 'real@x.com');
  });

  test('upload_folder_url column is recognised', () {
    for (final h in [
      'upload_folder_url',
      'Upload Folder URL',
      'file_request',
    ]) {
      final a = CsvImport.parseString(
        'email,password,$h\na@x.com,pw,https://mega.nz/filerequest/q\n',
      );
      expect(
        a.single.uploadFolderUrl,
        'https://mega.nz/filerequest/q',
        reason: 'header "$h"',
      );
    }
  });

  test('parse without required columns throws', () {
    expect(
      () => CsvImport.parseString('foo,bar\n1,2\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('export round-trip keeps password, MEGA key and notes', () {
    final rows = [
      Account(
        email: 'a@x.com',
        password: 'p1',
        megaKey: 'abc-def',
        notes: 'main',
        lastLoginAt: DateTime.utc(2026, 11, 15, 10),
        lastStatus: 'ok',
        storageUsedBytes: 1024,
        storageTotalBytes: 21474836480,
      ),
      Account(email: 'b@x.com', password: 'p,2', notes: 'note, with comma'),
    ];
    final text = CsvImport.toCsvString(rows);
    expect(
      text.split('\n').first,
      'email,password,mega_key,notes,upload_folder_url,last_login_at,'
      'last_status,storage_used_bytes,storage_total_bytes,storage_used_gb,'
      'storage_unused_gb',
    );
    expect(text, contains('2026-11-15T10:00:00.000Z'));
    expect(text, contains('21474836480'));

    // The TOTAL row at the end is skipped on import.
    final back = CsvImport.parseString(text);
    expect(back.length, 2);
    expect(back[0].megaKey, 'abc-def');
    expect(back[1].password, 'p,2'); // comma survives the round-trip
    expect(back[1].notes, 'note, with comma');
  });

  test('export adds used / unused GB per account and a TOTAL row', () {
    const gib = 1024 * 1024 * 1024;
    final rows = [
      Account(
        email: 'a@x.com',
        password: 'p',
        uploadFolderUrl: 'https://mega.nz/filerequest/a',
        storageUsedBytes: 1610612736, // 1.5 GB
        storageTotalBytes: 20 * gib,
      ),
      Account(
        email: 'over@x.com',
        password: 'p',
        storageUsedBytes: 25 * gib, // over quota → 0 unused
        storageTotalBytes: 20 * gib,
      ),
      Account(email: 'never@x.com', password: 'p'), // never measured
    ];
    final lines = CsvImport.toCsvString(rows).split('\n');
    expect(lines.length, 5); // header + 3 accounts + TOTAL

    final header = lines.first.split(',');
    List<String> row(int i) => lines[i].split(',');
    String cell(int line, String column) => row(line)[header.indexOf(column)];

    expect(cell(1, 'storage_used_bytes'), '1610612736'); // unchanged
    expect(cell(1, 'storage_total_bytes'), '${20 * gib}'); // unchanged
    expect(cell(1, 'storage_used_gb'), '1.50');
    expect(cell(1, 'storage_unused_gb'), '18.50');
    expect(cell(1, 'upload_folder_url'), 'https://mega.nz/filerequest/a');
    expect(cell(2, 'storage_used_gb'), '25.00');
    expect(cell(2, 'storage_unused_gb'), '0.00');
    expect(cell(3, 'storage_used_gb'), '');
    expect(cell(3, 'storage_unused_gb'), '');

    expect(cell(4, 'email'), 'TOTAL');
    expect(cell(4, 'notes'), '2 of 3 accounts measured');
    expect(cell(4, 'storage_used_gb'), '26.50');
    expect(cell(4, 'storage_unused_gb'), '18.50');
    expect(cell(4, 'storage_total_bytes'), '${40 * gib}');
  });
}
