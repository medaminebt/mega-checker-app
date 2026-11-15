import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/format.dart';
import 'package:mega_keepalive/links.dart';
import 'package:mega_keepalive/mega_service.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/screens/setup_screen.dart';

void main() {
  group('MegaService.parseDfOutput (mega-df, bytes)', () {
    // Layout copied from MEGAcmd's `df` implementation (megacmdexecuter.cpp).
    const sample = '''
Cloud drive:            5242880 in       3 file(s) and       1 folder(s)
Inbox:                        0 in       0 file(s) and       0 folder(s)
Rubbish bin:                  0 in       0 file(s) and       0 folder(s)
---------------------------------------------------------------------------
USED STORAGE:              5242880                           0.02% of 21474836480
---------------------------------------------------------------------------
Total size taken up by file versions:            0
''';

    test('reads used / total bytes', () {
      expect(
        MegaService.parseDfOutput(sample),
        const StorageInfo(5242880, 21474836480),
      );
    });

    test('used ≥ 1 TB is truncated by MEGAcmd → falls back to percent', () {
      const out =
          'USED STORAGE:         10...776                          50.00% of 2199023255552\n';
      expect(
        MegaService.parseDfOutput(out),
        const StorageInfo(1099511627776, 2199023255552),
      );
    });

    test('not logged in / unexpected output → null', () {
      expect(MegaService.parseDfOutput('[API:err] Not logged in.'), isNull);
      expect(MegaService.parseDfOutput(''), isNull);
    });

    test('Windows line endings (MEGAclient.exe) parse the same', () {
      const out =
          'Cloud drive:  5242880 in  3 file(s)\r\n'
          'USED STORAGE:  5242880   0.02% of 21474836480\r\n';
      expect(
        MegaService.parseDfOutput(out),
        const StorageInfo(5242880, 21474836480),
      );
    });

    test('free space is total − used, never negative (over quota)', () {
      expect(const StorageInfo(5, 20).freeBytes, 15);
      expect(const StorageInfo(25, 20).freeBytes, 0);
    });

    test('empty account with NaN percent still parses', () {
      const out = 'USED STORAGE:                    0         ----% of 0\n';
      expect(MegaService.parseDfOutput(out), const StorageInfo(0, 0));
    });
  });

  group('Fmt', () {
    test('bytes uses binary units like MEGA', () {
      expect(Fmt.bytes(512), '512 B');
      expect(Fmt.bytes(5242880), '5 MB');
      expect(Fmt.bytes(21474836480), '20 GB');
      expect(Fmt.bytes(1610612736), '1.5 GB');
      expect(Fmt.bytes(2199023255552), '2 TB');
    });

    test('ago', () {
      final now = DateTime(2026, 11, 15, 12);
      expect(Fmt.ago(now, now: now), 'just now');
      expect(
        Fmt.ago(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
      expect(
        Fmt.ago(now.subtract(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
      expect(
        Fmt.ago(now.subtract(const Duration(days: 12)), now: now),
        '12 d ago',
      );
      expect(
        Fmt.ago(now.subtract(const Duration(days: 95)), now: now),
        '3 mo ago',
      );
    });
  });

  group('Links.webUri (upload folder URLs)', () {
    test('accepts http(s) links, keeps the #key fragment', () {
      expect(
        Links.webUri(' https://mega.nz/folder/AbC#KeY ').toString(),
        'https://mega.nz/folder/AbC#KeY',
      );
      expect(
        Links.webUri('mega.nz/filerequest/xyz').toString(),
        'https://mega.nz/filerequest/xyz',
      );
    });

    test('rejects empty text, other schemes and non-hosts', () {
      expect(Links.webUri(''), isNull);
      expect(Links.webUri('   '), isNull);
      expect(Links.webUri('javascript:alert(1)'), isNull);
      expect(Links.webUri('file:///etc/passwd'), isNull);
      expect(Links.webUri('just some words'), isNull);
    });
  });

  group('SetupScreen validation', () {
    test('normaliseUrl strips paths and requires https', () {
      expect(
        SetupScreen.normaliseUrl(' https://abc.supabase.co/rest/v1/ '),
        'https://abc.supabase.co',
      );
      expect(SetupScreen.normaliseUrl('http://abc.supabase.co'), isNull);
      expect(SetupScreen.normaliseUrl('abc.supabase.co'), isNull);
    });

    test('rejects secret / service_role keys', () {
      expect(SetupScreen.rejectKey('sb_publishable_abc'), isNull);
      expect(SetupScreen.rejectKey('sb_secret_abc'), contains('SECRET'));
      expect(SetupScreen.rejectKey(''), isNotNull);
      // header.payload.sig with {"role":"service_role"}
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x';
      expect(SetupScreen.rejectKey(jwt), contains('service_role'));
    });
  });
}
