import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Storage for the MEGA accounts. The app talks to this interface only, so the
/// widget tests can swap in an in-memory version.
abstract class AccountsRepository {
  /// All accounts of the signed-in user, oldest first.
  Future<List<Account>> fetchAll();

  /// Insert new rows and return them with their database `id`s.
  Future<List<Account>> insertAll(List<Account> accounts);

  /// Patch some columns of one row (snake_case column names).
  Future<void> update(String id, Map<String, dynamic> patch);

  Future<void> delete(String id);
}

/// `public.mega_accounts` in Supabase (see `supabase/schema.sql`).
/// Row Level Security makes every query see only the signed-in user's rows.
class SupabaseAccountsRepository implements AccountsRepository {
  SupabaseAccountsRepository(this.client);

  final SupabaseClient client;

  static const table = 'mega_accounts';

  @override
  Future<List<Account>> fetchAll() async {
    final rows = await client
        .from(table)
        .select()
        .order('created_at', ascending: true);
    return rows.map(Account.fromRow).toList();
  }

  @override
  Future<List<Account>> insertAll(List<Account> accounts) async {
    if (accounts.isEmpty) return [];
    final rows = await client
        .from(table)
        .insert(accounts.map((a) => a.toInsertRow()).toList())
        .select();
    return rows.map(Account.fromRow).toList();
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    await client.from(table).update(patch).eq('id', id);
  }

  @override
  Future<void> delete(String id) async {
    await client.from(table).delete().eq('id', id);
  }
}

/// Turn Supabase / network errors into something actionable.
String describeError(Object e) {
  const offline =
      "Can't reach Supabase. Check your internet connection — and note that "
      'free projects pause after 7 days without activity (restore it from the '
      'Supabase dashboard).';
  bool looksOffline(String s) =>
      s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException') ||
      s.contains('Connection refused') ||
      s.contains('Connection reset') ||
      s.contains('TimeoutException');

  if (e is PostgrestException) {
    final msg = e.message;
    if (e.code == 'PGRST205' ||
        e.code == '42P01' ||
        msg.contains('Could not find the table')) {
      return 'Table "mega_accounts" not found — run supabase/schema.sql in the '
          'Supabase SQL Editor (see SUPABASE_SETUP.md).';
    }
    if (e.code == 'PGRST204' && msg.contains('upload_folder_url')) {
      return 'Your Supabase table has no "upload_folder_url" column yet — run '
          'supabase/schema.sql again in the SQL Editor (see '
          'SUPABASE_SETUP.md, "Updating").';
    }
    if (e.code == '23505') {
      return 'That email is already in your list.';
    }
    if (e.code == '42501') {
      return 'Blocked by Row Level Security — sign out and sign in again.';
    }
    if (e.code == '401' ||
        msg.toLowerCase().contains('invalid api key') ||
        msg.toLowerCase().contains('no api key')) {
      return 'Supabase rejected the publishable key — re-check it in Settings.';
    }
    return msg;
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (looksOffline(e.message)) return offline;
    if (m.contains('invalid login credentials')) {
      return 'Wrong email or password for your Supabase user.';
    }
    if (m.contains('email not confirmed')) {
      return 'This Supabase user is not confirmed yet — confirm it in the '
          'dashboard (Authentication › Users).';
    }
    return e.message;
  }
  final s = e.toString();
  if (looksOffline(s)) return offline;
  return s;
}
