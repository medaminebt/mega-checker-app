import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mega_keepalive/models.dart';
import 'package:mega_keepalive/security/encrypted_repository.dart';
import 'package:mega_keepalive/security/vault_crypto.dart';

import 'support/memory_repository.dart';

void main() {
  late FieldCipher cipher;
  setUp(() => cipher = FieldCipher(SecretKey(VaultCrypto.randomBytes(32))));

  test('insert stores ciphertext; the app gets plain text back', () async {
    final mem = MemoryAccountsRepository();
    final repo = EncryptedAccountsRepository(mem, cipher);
    final saved = await repo.insertAll([
      Account(email: 'A@x.com', password: 'pw1', megaKey: 'KEY1', notes: 'n'),
      Account(email: 'b@x.com', password: 'pw2'),
    ]);
    expect(saved.map((a) => a.password), ['pw1', 'pw2']);
    expect(saved.first.megaKey, 'KEY1');

    final row = mem.rowByEmail('a@x.com')!;
    expect(row['password'], startsWith('enc1:'));
    expect(row['mega_key'], startsWith('enc1:'));
    expect(row['notes'], 'n', reason: 'only password and key are encrypted');
    expect(mem.rowByEmail('b@x.com')!['mega_key'], '');

    final loaded = await repo.fetchAll();
    expect(loaded.map((a) => a.password).toSet(), {'pw1', 'pw2'});
    expect(repo.migrated, 0);
  });

  test('old plain-text rows are encrypted on load', () async {
    final mem = MemoryAccountsRepository([
      Account(email: 'old@x.com', password: 'plain', megaKey: 'K'),
    ]);
    final repo = EncryptedAccountsRepository(mem, cipher);
    final loaded = await repo.fetchAll();
    expect(loaded.single.password, 'plain');
    expect(repo.migrated, 1);
    final row = mem.rowByEmail('old@x.com')!;
    expect(row['password'], startsWith('enc1:'));
    expect(await cipher.decrypt(row['mega_key'] as String, 'mega_key'), 'K');

    await repo.fetchAll();
    expect(repo.migrated, 0, reason: 'nothing left to migrate');
  });

  test('update encrypts secrets in a copy of the patch', () async {
    final mem = MemoryAccountsRepository([
      Account(email: 'a@x.com', password: 'p'),
    ]);
    final repo = EncryptedAccountsRepository(mem, cipher);
    final a = (await repo.fetchAll()).single;
    final patch = {'password': 'new', 'notes': 'hello', 'last_status': 'ok'};
    await repo.update(a.id!, patch);
    expect(patch['password'], 'new', reason: "caller's map is untouched");
    final row = mem.rows[a.id]!;
    expect(row['password'], startsWith('enc1:'));
    expect(row['notes'], 'hello');
    expect(row['last_status'], 'ok');
  });

  test(
    'a value encrypted with another key shows empty and is reported',
    () async {
      final other = FieldCipher(SecretKey(VaultCrypto.randomBytes(32)));
      final mem = MemoryAccountsRepository([
        Account(email: 'a@x.com', password: 'x'),
      ]);
      final id = mem.rows.keys.single;
      mem.rows[id]!['password'] = await other.encrypt('theirs', 'password');
      final repo = EncryptedAccountsRepository(mem, cipher);
      final loaded = await repo.fetchAll();
      expect(loaded.single.password, '');
      expect(repo.unreadable, ['a@x.com']);
    },
  );
}
