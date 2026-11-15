import 'package:mega_keepalive/accounts_repository.dart';
import 'package:mega_keepalive/models.dart';

/// In-memory stand-in for Supabase, keyed by row id. Stores the raw column
/// maps so tests can assert exactly what would have been written.
class MemoryAccountsRepository implements AccountsRepository {
  MemoryAccountsRepository([List<Account> seed = const []]) {
    for (final a in seed) {
      final id = 'id-${++_seq}';
      rows[id] = {
        'id': id,
        ...a.toInsertRow(),
        if (a.lastStatus != null) 'last_status': a.lastStatus,
        if (a.lastLoginAt != null)
          'last_login_at': a.lastLoginAt!.toUtc().toIso8601String(),
        if (a.storageUsedBytes != null)
          'storage_used_bytes': a.storageUsedBytes,
        if (a.storageTotalBytes != null)
          'storage_total_bytes': a.storageTotalBytes,
        if (a.storageRubbishBytes != null)
          'storage_rubbish_bytes': a.storageRubbishBytes,
        if (a.storageVersionsBytes != null)
          'storage_versions_bytes': a.storageVersionsBytes,
      };
    }
  }

  final Map<String, Map<String, dynamic>> rows = {};
  int _seq = 0;
  int updateCalls = 0;

  /// When set, the next update() throws this once.
  Object? failNextUpdate;

  /// Simulated network latency for update().
  Duration updateDelay = Duration.zero;

  /// Ordered record of what happened (tests append their own events too).
  final List<String> log = [];

  Map<String, dynamic>? rowByEmail(String email) =>
      rows.values.where((r) => r['email'] == email).firstOrNull;

  @override
  Future<List<Account>> fetchAll() async =>
      rows.values.map(Account.fromRow).toList();

  @override
  Future<List<Account>> insertAll(List<Account> accounts) async {
    final out = <Account>[];
    for (final a in accounts) {
      final row = a.toInsertRow();
      if (rowByEmail(row['email'] as String) != null) {
        throw StateError('duplicate ${row['email']}');
      }
      final id = 'id-${++_seq}';
      rows[id] = {'id': id, ...row};
      out.add(Account.fromRow(rows[id]!));
    }
    return out;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    updateCalls++;
    if (updateDelay > Duration.zero) await Future.delayed(updateDelay);
    final f = failNextUpdate;
    if (f != null) {
      failNextUpdate = null;
      throw f;
    }
    rows[id]!.addAll(patch);
    log.add('update ${patch.keys.join(',')}');
  }

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
  }
}
