import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_crypto.dart';

/// Reads and writes the signed-in user's row of `public.mega_vault`.
abstract class VaultStore {
  /// Null when the user hasn't set a master password yet.
  Future<VaultRecord?> fetch();
  Future<void> insert(VaultRecord record);
  Future<void> update(VaultRecord record);
  Future<void> delete();
}

class SupabaseVaultStore implements VaultStore {
  SupabaseVaultStore(this.client);

  final SupabaseClient client;

  static const table = 'mega_vault';

  String get _uid => client.auth.currentUser!.id;

  @override
  Future<VaultRecord?> fetch() async {
    final row = await client.from(table).select().maybeSingle();
    return row == null ? null : VaultRecord.fromRow(row);
  }

  @override
  Future<void> insert(VaultRecord record) async {
    await client.from(table).insert(record.toRow());
  }

  @override
  Future<void> update(VaultRecord record) async {
    await client.from(table).update(record.toRow()).eq('user_id', _uid);
  }

  @override
  Future<void> delete() async {
    await client.from(table).delete().eq('user_id', _uid);
  }
}

/// In-memory vault store (widget tests and screenshots).
class MemoryVaultStore implements VaultStore {
  MemoryVaultStore([this.record]);

  VaultRecord? record;

  @override
  Future<VaultRecord?> fetch() async => record;

  @override
  Future<void> insert(VaultRecord r) async => record = r;

  @override
  Future<void> update(VaultRecord r) async => record = r;

  @override
  Future<void> delete() async => record = null;
}
