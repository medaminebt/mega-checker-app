import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/security/vault_crypto.dart';

// Low iteration count keeps the tests fast; the app uses 600 000.
const _fast = 1000;

void main() {
  test('default PBKDF2 work factor is the OWASP figure', () {
    expect(VaultCrypto.defaultIterations, 600000);
  });

  group('vault', () {
    late CreatedVault v;
    setUpAll(() async {
      v = await VaultCrypto.create('correct horse battery', iterations: _fast);
    });

    test('the right master password returns the data key', () async {
      final key = await VaultCrypto.unlock(v.record, 'correct horse battery');
      expect(key, isNotNull);
      expect(await key!.extractBytes(), await v.dataKey.extractBytes());
    });

    test('a wrong master password returns null', () async {
      expect(
        await VaultCrypto.unlock(v.record, 'Correct horse battery'),
        isNull,
      );
      expect(await VaultCrypto.unlock(v.record, ''), isNull);
    });

    test('the record holds no secret in clear', () {
      final row = v.record.toRow().toString();
      expect(row, isNot(contains('correct horse')));
      expect(row, isNot(contains(v.recoveryKey.toString())));
      expect(v.record.kdfIterations, _fast);
      expect(
        VaultRecord.fromRow(v.record.toRow()).wrappedKey,
        v.record.wrappedKey,
      );
    });

    test('the recovery key unlocks too, typed loosely', () async {
      final typed = v.recoveryKey
          .toString()
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('o', '0'); // 0 for O is forgiven
      final key = await VaultCrypto.unlockWithRecoveryKey(v.record, typed);
      expect(await key!.extractBytes(), await v.dataKey.extractBytes());
      expect(
        await VaultCrypto.unlockWithRecoveryKey(
          v.record,
          RecoveryKey.generate().toString(),
        ),
        isNull,
      );
      expect(await VaultCrypto.unlockWithRecoveryKey(v.record, 'nope'), isNull);
    });

    test('checkKey accepts the data key only', () async {
      expect(await VaultCrypto.checkKey(v.record, v.dataKey), isTrue);
      expect(
        await VaultCrypto.checkKey(
          v.record,
          SecretKey(VaultCrypto.randomBytes(32)),
        ),
        isFalse,
      );
    });

    test(
      'changing the master password keeps the data key and recovery key',
      () async {
        final cipher = FieldCipher(v.dataKey);
        final stored = await cipher.encrypt('MegaPass!', 'password');

        final updated = await VaultCrypto.rewrap(
          v.record,
          v.dataKey,
          'a brand new passphrase',
          iterations: _fast,
        );
        expect(updated.kdfSalt, isNot(v.record.kdfSalt));
        expect(
          await VaultCrypto.unlock(updated, 'correct horse battery'),
          isNull,
        );
        final key = await VaultCrypto.unlock(updated, 'a brand new passphrase');
        expect(
          await FieldCipher(key!).decrypt(stored, 'password'),
          'MegaPass!',
        );
        expect(
          await VaultCrypto.unlockWithRecoveryKey(
            updated,
            v.recoveryKey.toString(),
          ),
          isNotNull,
        );
      },
    );

    test('a new recovery key replaces the old one', () async {
      final (updated, fresh) = await VaultCrypto.newRecoveryKey(
        v.record,
        v.dataKey,
      );
      expect(
        await VaultCrypto.unlockWithRecoveryKey(
          updated,
          v.recoveryKey.toString(),
        ),
        isNull,
      );
      expect(
        await VaultCrypto.unlockWithRecoveryKey(updated, fresh.toString()),
        isNotNull,
      );
      expect(
        await VaultCrypto.unlock(updated, 'correct horse battery'),
        isNotNull,
      );
    });
  });

  group('RecoveryKey', () {
    test('8 groups of 4 base32 characters, round-trips', () {
      final k = RecoveryKey.generate();
      final s = k.toString();
      expect(s, matches(RegExp(r'^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$')));
      expect(RecoveryKey.parse(s), k.bytes);
      expect(RecoveryKey.parse('${s}A'), isNull);
    });
  });

  group('FieldCipher', () {
    final cipher = FieldCipher(SecretKey(VaultCrypto.randomBytes(32)));

    test('round-trips text, including non-ASCII', () async {
      for (final p in ['a', 'p@ss:w0rd with spaces', 'Ünïcødé 密码 🔑']) {
        final e = await cipher.encrypt(p, 'password');
        expect(FieldCipher.isEncrypted(e), isTrue);
        if (p.length > 3) expect(e, isNot(contains(p)));
        expect(await cipher.decrypt(e, 'password'), p);
      }
    });

    test('empty stays empty; plain text passes through', () async {
      expect(await cipher.encrypt('', 'password'), '');
      expect(await cipher.decrypt('legacy-plain', 'password'), 'legacy-plain');
    });

    test('same text encrypts differently each time', () async {
      expect(
        await cipher.encrypt('same', 'password'),
        isNot(await cipher.encrypt('same', 'password')),
      );
    });

    test('padding hides the exact length', () async {
      final a = await cipher.encrypt('x', 'password');
      final b = await cipher.encrypt('x' * 15, 'password');
      final c = await cipher.encrypt('x' * 16, 'password');
      expect(a.length, b.length);
      expect(c.length, greaterThan(b.length));
    });

    test('bound to its column and key', () async {
      final e = await cipher.encrypt('secret', 'password');
      expect(
        () => cipher.decrypt(e, 'mega_key'),
        throwsA(isA<FieldDecryptException>()),
      );
      final other = FieldCipher(SecretKey(VaultCrypto.randomBytes(32)));
      expect(
        () => other.decrypt(e, 'password'),
        throwsA(isA<FieldDecryptException>()),
      );
      expect(
        () => cipher.decrypt('enc1:not-base64!', 'password'),
        throwsA(isA<FieldDecryptException>()),
      );
    });
  });
}
