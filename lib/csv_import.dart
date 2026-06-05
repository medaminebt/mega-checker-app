import 'dart:io';

import 'package:csv/csv.dart';

import 'models.dart';

/// CSV is the accounts database. No native plugin: the file dialogs are the
/// macOS native ones driven through `osascript`, parsing/writing uses the
/// pure-Dart `csv` package.
class CsvImport {
  // ---- pick / save dialogs ----------------------------------------------

  /// Native "open file" dialog. Returns the chosen path, or null if cancelled.
  static Future<String?> pickCsvFile() async {
    const script =
        'POSIX path of (choose file with prompt "Select your accounts CSV" '
        'of type {"csv", "public.comma-separated-values-text", "public.text"})';
    final res = await Process.run('osascript', ['-e', script]);
    if (res.exitCode != 0) return null;
    final path = res.stdout.toString().trim();
    return path.isEmpty ? null : path;
  }

  /// Native "save file" dialog for Export. Returns the chosen path, or null.
  static Future<String?> pickSaveCsvFile() async {
    const script =
        'POSIX path of (choose file name with prompt "Export accounts CSV" '
        'default name "accounts.csv")';
    final res = await Process.run('osascript', ['-e', script]);
    if (res.exitCode != 0) return null;
    final path = res.stdout.toString().trim();
    return path.isEmpty ? null : path;
  }

  // ---- read --------------------------------------------------------------

  static List<Account> parseFile(String path) =>
      parseString(File(path).readAsStringSync());

  /// Parse CSV text whose header row contains at least `email` and `password`
  /// (also recognises `notes`). Rows missing email or password are skipped.
  static List<Account> parseString(String text) {
    var normalised = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Strip a UTF-8 BOM (Excel / Numbers add one) so the first header matches.
    if (normalised.startsWith('﻿')) normalised = normalised.substring(1);

    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(normalised);
    if (rows.isEmpty) return [];

    final header =
        rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);
    final iEmail = col('email'), iPass = col('password'), iNotes = col('notes');
    if (iEmail < 0 || iPass < 0) {
      throw const FormatException(
          'CSV needs "email" and "password" columns in the header row.');
    }

    final out = <Account>[];
    for (final row in rows.skip(1)) {
      String cell(int i) =>
          (i >= 0 && i < row.length) ? row[i].toString().trim() : '';
      final email = cell(iEmail);
      final pass = cell(iPass);
      if (email.isEmpty || pass.isEmpty) continue;
      // Skip rows whose "email" isn't an email — guards against stray prose /
      // junk lines that happen to contain commas.
      if (!email.contains('@')) continue;
      out.add(Account(email: email, password: pass, notes: cell(iNotes)));
    }
    return out;
  }

  // ---- write -------------------------------------------------------------

  static String toCsvString(List<Account> rows) {
    final data = <List<String>>[
      ['email', 'password', 'notes'],
      for (final r in rows) [r.email, r.password, r.notes],
    ];
    return const ListToCsvConverter(eol: '\n').convert(data);
  }

  /// Write the current table (with updated notes) back to a CSV file.
  static void exportToFile(String path, List<Account> rows) {
    File(path).writeAsStringSync(toCsvString(rows), flush: true);
  }
}
