import 'models.dart';

/// Result of parsing a pasted list of accounts.
class PastedList {
  PastedList(this.accounts, this.skippedLines, this.duplicates);

  /// Valid, de-duplicated accounts (last occurrence of an email wins).
  final List<Account> accounts;

  /// 1-based line numbers that didn't look like `email <sep> password`.
  final List<int> skippedLines;

  /// How many lines repeated an email already seen earlier in the paste.
  final int duplicates;
}

/// What an import will do against the accounts already in the database.
class ImportPlan {
  ImportPlan(this.toInsert, this.toUpdate, this.unchanged);

  final List<Account> toInsert;

  /// Existing account → columns to patch.
  final Map<Account, Map<String, dynamic>> toUpdate;

  /// Incoming rows that match an existing account and change nothing.
  final int unchanged;
}

class AccountImport {
  // email, then ONE separator (tab, space, comma, semicolon, colon or pipe),
  // then the password = everything else on the line. Emails can't contain
  // those characters, so passwords may (e.g. "a@b.com:pa:ss" → "pa:ss").
  static final _lineRe = RegExp(
    r'^([^\s,;:|]+@[^\s,;:|]+\.[^\s,;:|]+)\s*[\s,;:|]\s*(.+)$',
  );

  /// Parse one account per line. Accepted forms:
  ///
  ///     email:password
  ///     email,password
  ///     email;password
  ///     email password      (space or tab)
  ///     email | password
  ///
  /// Blank lines and lines starting with `#` are ignored.
  static PastedList parsePastedList(String text) {
    final byEmail = <String, Account>{};
    final skipped = <int>[];
    var dupes = 0;

    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = _lineRe.firstMatch(line);
      if (m == null) {
        skipped.add(i + 1);
        continue;
      }
      final email = Account.normaliseEmail(m.group(1)!);
      final password = m.group(2)!.trim();
      if (password.isEmpty) {
        skipped.add(i + 1);
        continue;
      }
      if (byEmail.containsKey(email)) dupes++;
      byEmail[email] = Account(email: email, password: password);
    }
    return PastedList(byEmail.values.toList(), skipped, dupes);
  }

  /// Compare [incoming] rows with [existing] ones (matched by email).
  ///
  /// New emails are inserted. For known emails, when [overwrite] is true the
  /// non-empty incoming password / MEGA key / notes / upload folder URL
  /// replace the stored ones;
  /// otherwise they're left alone.
  static ImportPlan plan(
    List<Account> existing,
    List<Account> incoming, {
    required bool overwrite,
  }) {
    final byEmail = <String, Account>{
      for (final a in existing) Account.normaliseEmail(a.email): a,
    };
    final toInsert = <Account>[];
    final toUpdate = <Account, Map<String, dynamic>>{};
    final newEmails = <String>{};
    var unchanged = 0;

    for (final inc in incoming) {
      final key = Account.normaliseEmail(inc.email);
      if (key.isEmpty) continue;
      final ex = byEmail[key];
      if (ex == null) {
        if (newEmails.add(key)) {
          toInsert.add(
            Account(
              email: key,
              password: inc.password,
              megaKey: inc.megaKey,
              notes: inc.notes,
              uploadFolderUrl: inc.uploadFolderUrl,
            ),
          );
        }
        continue;
      }
      if (!overwrite) {
        unchanged++;
        continue;
      }
      final patch = <String, dynamic>{};
      if (inc.password.isNotEmpty && inc.password != ex.password) {
        patch['password'] = inc.password;
      }
      if (inc.megaKey.isNotEmpty && inc.megaKey != ex.megaKey) {
        patch['mega_key'] = inc.megaKey;
      }
      if (inc.notes.isNotEmpty && inc.notes != ex.notes) {
        patch['notes'] = inc.notes;
      }
      if (inc.uploadFolderUrl.isNotEmpty &&
          inc.uploadFolderUrl != ex.uploadFolderUrl) {
        patch['upload_folder_url'] = inc.uploadFolderUrl;
      }
      if (patch.isEmpty) {
        unchanged++;
      } else {
        toUpdate[ex] = patch;
      }
    }
    return ImportPlan(toInsert, toUpdate, unchanged);
  }
}
