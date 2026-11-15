/// One MEGA account — one row of the `public.mega_accounts` table in Supabase.
///
/// Fields are mutable because the table rows are edited inline and the app
/// writes login results back into them.
class Account {
  /// Supabase row id (uuid). `null` until the row has been inserted.
  String? id;

  String email;
  String password;

  /// MEGA recovery key — typed in by hand, the app never derives it.
  String megaKey;

  /// Free-text notes (may span several lines).
  String notes;

  /// Link to a MEGA upload folder ("file request" / folder link) — opened in
  /// the browser to upload straight into this account without logging in.
  String uploadFolderUrl;

  /// Last **successful** login.
  DateTime? lastLoginAt;

  /// Last login attempt (successful or not).
  DateTime? lastCheckedAt;

  /// `'ok'`, `'failed'` or `null` (never checked).
  String? lastStatus;

  /// Human-readable reason of the last failure.
  String? lastError;

  /// Storage figures read with `mega-df` on the last successful login.
  int? storageUsedBytes;
  int? storageTotalBytes;

  /// Transient UI state: a check is in progress for this account.
  bool running = false;

  Account({
    this.id,
    required this.email,
    required this.password,
    this.megaKey = '',
    this.notes = '',
    this.uploadFolderUrl = '',
    this.lastLoginAt,
    this.lastCheckedAt,
    this.lastStatus,
    this.lastError,
    this.storageUsedBytes,
    this.storageTotalBytes,
  });

  AccountStatus get status {
    if (running) return AccountStatus.running;
    switch (lastStatus) {
      case 'ok':
        return AccountStatus.ok;
      case 'failed':
        return AccountStatus.failed;
      default:
        return AccountStatus.untested;
    }
  }

  StorageInfo? get storage =>
      (storageUsedBytes != null && storageTotalBytes != null)
      ? StorageInfo(storageUsedBytes!, storageTotalBytes!)
      : null;

  /// MEGA addresses are case-insensitive; store them trimmed + lower-cased so
  /// the `(user_id, email)` unique constraint catches duplicates.
  static String normaliseEmail(String email) => email.trim().toLowerCase();

  // ---- Supabase row mapping ----------------------------------------------

  factory Account.fromRow(Map<String, dynamic> r) {
    DateTime? ts(String k) {
      final v = r[k];
      return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    }

    int? big(String k) {
      final v = r[k];
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return Account(
      id: r['id'] as String?,
      email: (r['email'] ?? '') as String,
      password: (r['password'] ?? '') as String,
      megaKey: (r['mega_key'] ?? '') as String,
      notes: (r['notes'] ?? '') as String,
      uploadFolderUrl: (r['upload_folder_url'] ?? '') as String,
      lastLoginAt: ts('last_login_at'),
      lastCheckedAt: ts('last_checked_at'),
      lastStatus: r['last_status'] as String?,
      lastError: r['last_error'] as String?,
      storageUsedBytes: big('storage_used_bytes'),
      storageTotalBytes: big('storage_total_bytes'),
    );
  }

  /// Columns sent when inserting a new row (`user_id` defaults to the
  /// signed-in user on the database side). `upload_folder_url` is only sent
  /// when set, so adding accounts keeps working on a database that hasn't
  /// run the column migration yet (see supabase/schema.sql).
  Map<String, dynamic> toInsertRow() => {
    'email': normaliseEmail(email),
    'password': password,
    'mega_key': megaKey,
    'notes': notes,
    if (uploadFolderUrl.isNotEmpty) 'upload_folder_url': uploadFolderUrl,
  };
}

enum AccountStatus { untested, running, ok, failed }

/// Used / total storage of a MEGA account, in bytes.
class StorageInfo {
  final int usedBytes;
  final int totalBytes;

  const StorageInfo(this.usedBytes, this.totalBytes);

  double get fraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  /// Free space; 0 when the account is over its quota.
  int get freeBytes => usedBytes >= totalBytes ? 0 : totalBytes - usedBytes;

  @override
  bool operator ==(Object other) =>
      other is StorageInfo &&
      other.usedBytes == usedBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(usedBytes, totalBytes);

  @override
  String toString() => 'StorageInfo($usedBytes / $totalBytes)';
}

/// Outcome of a single login attempt.
enum LoginOutcome {
  success,
  wrongCredentials, // MEGA: "invalid email or password"
  invalidEmail, // malformed address, rejected before contacting MEGA
  needs2fa, // account has 2FA (this app doesn't handle codes)
  megacmdMissing, // MEGAcmd not installed / not found
  unsupported, // web build: MEGAcmd can't run in a browser
  error, // anything else (timeout, network, unexpected output)
}

class LoginResult {
  final LoginOutcome outcome;
  final String message; // human-readable detail

  /// Storage read after a successful login (null if `mega-df` failed).
  final StorageInfo? storage;

  LoginResult(this.outcome, this.message, {this.storage});

  bool get ok => outcome == LoginOutcome.success;

  /// Short reason stored in `last_error` and shown in the status tooltip.
  String get errorText {
    switch (outcome) {
      case LoginOutcome.success:
        return '';
      case LoginOutcome.wrongCredentials:
        return 'Wrong email or password';
      case LoginOutcome.invalidEmail:
        return 'Invalid email address';
      case LoginOutcome.needs2fa:
        return 'Account needs 2FA';
      case LoginOutcome.megacmdMissing:
        return 'MEGAcmd not installed';
      case LoginOutcome.unsupported:
        return 'Checks need the desktop app';
      case LoginOutcome.error:
        return message;
    }
  }
}
