import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'models.dart';

/// A CSV file chosen in the open dialog.
class PickedCsv {
  const PickedCsv(this.name, this.text);

  /// File name only (no folder), for messages.
  final String name;
  final String text;
}

/// CSV import (to bring accounts into Supabase) and export (a local backup).
///
/// The dialogs come from `file_selector`: native Finder / Explorer panels on
/// desktop, the browser's file picker on the web. On the web, Export starts a
/// download instead of asking where to save.
class CsvImport {
  static const _csvTypes = XTypeGroup(
    label: 'CSV',
    extensions: ['csv', 'txt'],
    mimeTypes: ['text/csv', 'text/plain'],
    uniformTypeIdentifiers: [
      'public.comma-separated-values-text',
      'public.plain-text',
    ],
  );

  static const defaultExportName = 'mega_accounts.csv';

  // ---- pick / save dialogs ----------------------------------------------

  /// Open dialog. Returns the chosen file's name and text, or null if
  /// cancelled.
  static Future<PickedCsv?> pickCsv() async {
    final file = await openFile(
      acceptedTypeGroups: const [_csvTypes],
      confirmButtonText: 'Import',
    );
    if (file == null) return null;
    return PickedCsv(file.name, await file.readAsString());
  }

  /// Save dialog + write. Returns the saved file's path (desktop) or the
  /// downloaded file's name (web), or null if cancelled.
  static Future<String?> saveCsv(List<Account> rows) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_csvTypes],
      suggestedName: defaultExportName,
      confirmButtonText: 'Export',
    );
    if (location == null) return null;
    var path = location.path;
    if (!kIsWeb && !path.toLowerCase().endsWith('.csv')) path = '$path.csv';
    final file = XFile.fromData(
      utf8.encode(toCsvString(rows)),
      mimeType: 'text/csv',
      name: defaultExportName,
    );
    await file.saveTo(path); // web: ignores the path and downloads the file
    return kIsWeb ? defaultExportName : path;
  }

  // ---- read --------------------------------------------------------------

  static const _keyHeaders = [
    'mega_key',
    'mega key',
    'megakey',
    'recovery_key',
    'recovery key',
  ];

  static const _uploadHeaders = [
    'upload_folder_url',
    'upload folder url',
    'upload_folder',
    'upload folder',
    'upload_url',
    'upload url',
    'upload_link',
    'upload link',
    'file_request',
    'file request',
  ];

  /// Parse CSV text whose header row contains at least `email` and `password`
  /// (also recognises `notes`, `mega_key` and `upload_folder_url`). Rows
  /// missing email or password are skipped.
  static List<Account> parseString(String text) {
    var normalised = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Strip a UTF-8 BOM (Excel / Numbers add one) so the first header matches.
    if (normalised.startsWith('﻿')) normalised = normalised.substring(1);

    final rows = Csv(fieldDelimiter: ',', autoDetect: false).decode(normalised);
    if (rows.isEmpty) return [];

    final header = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();
    int col(String name) => header.indexOf(name);
    int firstCol(List<String> names) =>
        names.map(col).firstWhere((i) => i >= 0, orElse: () => -1);
    final iEmail = col('email'), iPass = col('password'), iNotes = col('notes');
    final iKey = firstCol(_keyHeaders);
    final iUpload = firstCol(_uploadHeaders);
    if (iEmail < 0 || iPass < 0) {
      throw const FormatException(
        'CSV needs "email" and "password" columns in the header row.',
      );
    }

    final out = <Account>[];
    for (final row in rows.skip(1)) {
      String cell(int i) =>
          (i >= 0 && i < row.length) ? row[i].toString().trim() : '';
      final email = cell(iEmail);
      final pass = cell(iPass);
      if (email.isEmpty || pass.isEmpty) continue;
      // Skip rows whose "email" isn't an email — guards against stray prose /
      // junk lines that happen to contain commas (and the export's TOTAL row).
      if (!email.contains('@')) continue;
      out.add(
        Account(
          email: email,
          password: pass,
          megaKey: cell(iKey),
          notes: cell(iNotes),
          uploadFolderUrl: cell(iUpload),
        ),
      );
    }
    return out;
  }

  // ---- write -------------------------------------------------------------

  static const _bytesPerGb = 1024 * 1024 * 1024;

  /// Bytes → GB with 2 decimals, binary units (1 GB = 1024³ bytes) like MEGA,
  /// so a free account's quota reads 20.00. Plain number (no unit, `.`
  /// decimal point) so spreadsheets can add the column up.
  static String gb(int bytes) => (bytes / _bytesPerGb).toStringAsFixed(2);

  static const exportHeader = [
    'email',
    'password',
    'mega_key',
    'notes',
    'upload_folder_url',
    'last_login_at',
    'last_status',
    'storage_used_bytes',
    'storage_total_bytes',
    'storage_used_gb',
    'storage_unused_gb',
    'storage_rubbish_bytes',
    'storage_versions_bytes',
  ];

  /// One row per account, then a TOTAL row adding up storage across the
  /// accounts that have been measured. (Import skips the TOTAL row.)
  static String toCsvString(List<Account> rows) {
    String ts(DateTime? d) => d == null ? '' : d.toUtc().toIso8601String();
    var used = 0, total = 0, free = 0, measured = 0, bin = 0, versions = 0;
    final data = <List<String>>[exportHeader];
    for (final r in rows) {
      bin += r.storageRubbishBytes ?? 0;
      versions += r.storageVersionsBytes ?? 0;
      final s = r.storage;
      if (s != null) {
        used += s.usedBytes;
        total += s.totalBytes;
        free += s.freeBytes;
        measured++;
      }
      data.add([
        r.email,
        r.password,
        r.megaKey,
        r.notes,
        r.uploadFolderUrl,
        ts(r.lastLoginAt),
        r.lastStatus ?? '',
        r.storageUsedBytes?.toString() ?? '',
        r.storageTotalBytes?.toString() ?? '',
        s == null ? '' : gb(s.usedBytes),
        s == null ? '' : gb(s.freeBytes),
        r.storageRubbishBytes?.toString() ?? '',
        r.storageVersionsBytes?.toString() ?? '',
      ]);
    }
    data.add([
      'TOTAL',
      '',
      '',
      '$measured of ${rows.length} accounts measured',
      '',
      '',
      '',
      '$used',
      '$total',
      gb(used),
      gb(free),
      '$bin',
      '$versions',
    ]);
    return Csv(lineDelimiter: '\n').encode(data);
  }
}
