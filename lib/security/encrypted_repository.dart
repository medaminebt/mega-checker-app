import '../accounts_repository.dart';
import '../models.dart';
import 'vault_crypto.dart';

/// Wraps the real repository so passwords and MEGA keys are encrypted before
/// they leave the app and decrypted when they come back. Everything above
/// this layer (the table, checks, CSV export) sees plain text in memory;
/// Supabase only ever stores `enc1:…` ciphertext for those two columns.
class EncryptedAccountsRepository implements AccountsRepository {
  EncryptedAccountsRepository(this.inner, this.cipher);

  final AccountsRepository inner;
  final FieldCipher cipher;

  static const secretColumns = {'password', 'mega_key'};

  /// Emails whose stored password or key couldn't be decrypted on the last
  /// [fetchAll] (encrypted with another key). They show up empty.
  List<String> unreadable = const [];

  /// Rows that still had plain-text secrets and were encrypted by the last
  /// [fetchAll] (first unlock after turning encryption on, or rows saved by
  /// an older copy of the app).
  int migrated = 0;

  /// Set when encrypting old plain-text rows failed (they're retried on the
  /// next load).
  String? migrationError;

  @override
  Future<List<Account>> fetchAll() async {
    final list = await inner.fetchAll();
    final bad = <String>[];
    migrated = 0;
    migrationError = null;
    for (final a in list) {
      final patch = <String, dynamic>{};
      var unreadableRow = false;

      Future<String> open(String stored, String column) async {
        if (FieldCipher.isEncrypted(stored)) {
          try {
            return await cipher.decrypt(stored, column);
          } on FieldDecryptException {
            unreadableRow = true;
            return '';
          }
        }
        if (stored.isNotEmpty) {
          patch[column] = await cipher.encrypt(stored, column);
        }
        return stored;
      }

      a.password = await open(a.password, 'password');
      a.megaKey = await open(a.megaKey, 'mega_key');
      if (unreadableRow) bad.add(a.email);

      final id = a.id;
      if (patch.isNotEmpty && id != null) {
        try {
          await inner.update(id, patch);
          migrated++;
        } catch (e) {
          migrationError = describeError(e);
        }
      }
    }
    unreadable = bad;
    return list;
  }

  @override
  Future<List<Account>> insertAll(List<Account> accounts) async {
    if (accounts.isEmpty) return [];
    final sealed = <Account>[
      for (final a in accounts)
        Account(
          email: a.email,
          password: await cipher.encrypt(a.password, 'password'),
          megaKey: await cipher.encrypt(a.megaKey, 'mega_key'),
          notes: a.notes,
          uploadFolderUrl: a.uploadFolderUrl,
        ),
    ];
    final saved = await inner.insertAll(sealed);
    final plain = {
      for (final a in accounts) Account.normaliseEmail(a.email): a,
    };
    for (final s in saved) {
      final src = plain[Account.normaliseEmail(s.email)];
      if (src != null) {
        s
          ..password = src.password
          ..megaKey = src.megaKey;
      } else {
        s
          ..password = await cipher.decrypt(s.password, 'password')
          ..megaKey = await cipher.decrypt(s.megaKey, 'mega_key');
      }
    }
    return saved;
  }

  /// Encrypts `password` / `mega_key` in a copy of [patch] (the caller's map
  /// keeps the plain text it applies locally).
  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final sealed = <String, dynamic>{};
    for (final e in patch.entries) {
      sealed[e.key] = secretColumns.contains(e.key) && e.value is String
          ? await cipher.encrypt(e.value as String, e.key)
          : e.value;
    }
    await inner.update(id, sealed);
  }

  @override
  Future<void> delete(String id) => inner.delete(id);
}
