import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

/// Client-side encryption for MEGA passwords and keys ("the vault").
///
/// Design (envelope encryption):
///
/// * A random 256-bit **data key** encrypts every password / MEGA key with
///   AES-256-GCM. It never leaves the app unencrypted.
/// * The **master password** → PBKDF2-HMAC-SHA256 (600 000 iterations,
///   random salt) → a key that wraps (encrypts) the data key.
/// * A random **recovery key** (shown once) wraps the data key a second
///   time, so a forgotten master password isn't the end.
/// * Supabase stores only the wrapped keys, the salt and the ciphertexts
///   (`public.mega_vault` + the `password` / `mega_key` columns).
///
/// Changing the master password only re-wraps the data key; the account rows
/// aren't touched. The same code runs on macOS, Windows and the web (Web
/// Crypto in the browser), so data encrypted on one opens on the others.
class VaultCrypto {
  /// OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256. Stored per vault, so
  /// it can be raised later without breaking existing vaults.
  static const defaultIterations = 600000;

  static const _wrapAad = 'mega-checker:vault:v1:wrap';
  static const _recoveryAad = 'mega-checker:vault:v1:recovery';
  static const _checkAad = 'mega-checker:vault:v1:check';
  static const _checkPlain = 'mega-checker key check v1';

  static final _aes = AesGcm.with256bits();

  /// A new vault for [masterPassword]. Insert [CreatedVault.record] into
  /// Supabase, then show [CreatedVault.recoveryKey] to the user once.
  static Future<CreatedVault> create(
    String masterPassword, {
    int iterations = defaultIterations,
  }) async {
    final dek = randomBytes(32);
    final dataKey = SecretKey(dek);
    final salt = randomBytes(16);
    final kek = await deriveKey(masterPassword, salt, iterations);
    final recovery = RecoveryKey.generate();
    final record = VaultRecord(
      kdfIterations: iterations,
      kdfSalt: base64.encode(salt),
      wrappedKey: await _seal(kek, dek, _wrapAad),
      recoveryWrappedKey: await _seal(
        await _recoveryKek(recovery),
        dek,
        _recoveryAad,
      ),
      keyCheck: await _seal(dataKey, utf8.encode(_checkPlain), _checkAad),
    );
    return CreatedVault(record, dataKey, recovery);
  }

  /// The data key, or null when [password] is wrong.
  static Future<SecretKey?> unlock(VaultRecord r, String password) async {
    final kek = await deriveKey(
      password,
      base64.decode(r.kdfSalt),
      r.kdfIterations,
    );
    final dek = await _open(kek, r.wrappedKey, _wrapAad);
    return dek == null ? null : SecretKey(dek);
  }

  /// The data key, or null when [recoveryKey] is wrong (or the vault has
  /// none).
  static Future<SecretKey?> unlockWithRecoveryKey(
    VaultRecord r,
    String recoveryKey,
  ) async {
    final wrapped = r.recoveryWrappedKey;
    final bytes = RecoveryKey.parse(recoveryKey);
    if (wrapped == null || bytes == null) return null;
    final dek = await _open(
      await _recoveryKek(RecoveryKey._(bytes)),
      wrapped,
      _recoveryAad,
    );
    return dek == null ? null : SecretKey(dek);
  }

  /// Whether [key] is this vault's data key (used for a key remembered on
  /// this computer, which may be stale after a reset).
  static Future<bool> checkKey(VaultRecord r, SecretKey key) async {
    final plain = await _open(key, r.keyCheck, _checkAad);
    if (plain == null) return false;
    try {
      return utf8.decode(plain) == _checkPlain;
    } on FormatException {
      return false;
    }
  }

  /// New master password: fresh salt, same data key, so the account rows stay
  /// as they are.
  static Future<VaultRecord> rewrap(
    VaultRecord r,
    SecretKey dataKey,
    String newPassword, {
    int iterations = defaultIterations,
  }) async {
    final salt = randomBytes(16);
    final kek = await deriveKey(newPassword, salt, iterations);
    return r.copyWith(
      kdfIterations: iterations,
      kdfSalt: base64.encode(salt),
      wrappedKey: await _seal(kek, await dataKey.extractBytes(), _wrapAad),
    );
  }

  /// Replace the recovery key (the old one stops working).
  static Future<(VaultRecord, RecoveryKey)> newRecoveryKey(
    VaultRecord r,
    SecretKey dataKey,
  ) async {
    final recovery = RecoveryKey.generate();
    final wrapped = await _seal(
      await _recoveryKek(recovery),
      await dataKey.extractBytes(),
      _recoveryAad,
    );
    return (r.copyWith(recoveryWrappedKey: wrapped), recovery);
  }

  /// PBKDF2-HMAC-SHA256 → 256-bit key. Runs in a background isolate on
  /// desktop (≈ 2 s of CPU at 600 000 iterations); in a browser it's Web
  /// Crypto, which doesn't block the page.
  static Future<SecretKey> deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final bytes = await compute(
      _pbkdf2,
      _KdfJob(password, Uint8List.fromList(salt), iterations),
    );
    return SecretKey(bytes);
  }

  // The recovery key already carries 160 random bits, so a fast KDF is
  // enough. A constant salt keeps it independent of the master password's
  // salt (which changes with every new master password).
  static Future<SecretKey> _recoveryKek(RecoveryKey key) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final out = await hkdf.deriveKey(
      secretKey: SecretKey(key.bytes),
      nonce: utf8.encode('mega-checker recovery salt v1'),
      info: utf8.encode('mega-checker recovery key v1'),
    );
    return SecretKey(await out.extractBytes());
  }

  static Future<String> _seal(
    SecretKey key,
    List<int> plain,
    String aad,
  ) async {
    final box = await _aes.encrypt(
      plain,
      secretKey: key,
      nonce: _aes.newNonce(),
      aad: utf8.encode(aad),
    );
    return base64.encode(box.concatenation());
  }

  /// Decrypts, or returns null when the key is wrong / data was altered.
  static Future<List<int>?> _open(
    SecretKey key,
    String sealed,
    String aad,
  ) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(sealed),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return await _aes.decrypt(box, secretKey: key, aad: utf8.encode(aad));
    } on SecretBoxAuthenticationError {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static final _rng = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));
}

class _KdfJob {
  const _KdfJob(this.password, this.salt, this.iterations);
  final String password;
  final Uint8List salt;
  final int iterations;
}

Future<List<int>> _pbkdf2(_KdfJob job) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: job.iterations,
    bits: 256,
  );
  final key = await kdf.deriveKeyFromPassword(
    password: job.password,
    nonce: job.salt,
  );
  return key.extractBytes();
}

/// Result of [VaultCrypto.create].
class CreatedVault {
  CreatedVault(this.record, this.dataKey, this.recoveryKey);

  final VaultRecord record;
  final SecretKey dataKey;
  final RecoveryKey recoveryKey;
}

/// One row of `public.mega_vault`: everything needed to unlock, nothing that
/// unlocks by itself.
class VaultRecord {
  const VaultRecord({
    required this.kdfIterations,
    required this.kdfSalt,
    required this.wrappedKey,
    required this.keyCheck,
    this.recoveryWrappedKey,
    this.kdf = 'pbkdf2-sha256',
  });

  final String kdf;
  final int kdfIterations;

  /// base64
  final String kdfSalt;

  /// Data key encrypted with the master-password key: base64(nonce‖ct‖tag).
  final String wrappedKey;

  /// Data key encrypted with the recovery key, same format.
  final String? recoveryWrappedKey;

  /// A known text encrypted with the data key, to validate a remembered key.
  final String keyCheck;

  factory VaultRecord.fromRow(Map<String, dynamic> r) => VaultRecord(
    kdf: (r['kdf'] ?? 'pbkdf2-sha256') as String,
    kdfIterations: (r['kdf_iterations'] as num).toInt(),
    kdfSalt: r['kdf_salt'] as String,
    wrappedKey: r['wrapped_key'] as String,
    recoveryWrappedKey: r['recovery_wrapped_key'] as String?,
    keyCheck: r['key_check'] as String,
  );

  Map<String, dynamic> toRow() => {
    'kdf': kdf,
    'kdf_iterations': kdfIterations,
    'kdf_salt': kdfSalt,
    'wrapped_key': wrappedKey,
    'recovery_wrapped_key': recoveryWrappedKey,
    'key_check': keyCheck,
  };

  VaultRecord copyWith({
    int? kdfIterations,
    String? kdfSalt,
    String? wrappedKey,
    String? recoveryWrappedKey,
  }) => VaultRecord(
    kdf: kdf,
    kdfIterations: kdfIterations ?? this.kdfIterations,
    kdfSalt: kdfSalt ?? this.kdfSalt,
    wrappedKey: wrappedKey ?? this.wrappedKey,
    recoveryWrappedKey: recoveryWrappedKey ?? this.recoveryWrappedKey,
    keyCheck: keyCheck,
  );
}

/// 160 random bits written as 8 groups of 4 base32 characters, e.g.
/// `K7QM-2XRA-…`. Easy to write down; typing 0/1/8 for O/I/B is forgiven.
class RecoveryKey {
  RecoveryKey._(this.bytes);

  factory RecoveryKey.generate() => RecoveryKey._(VaultCrypto.randomBytes(20));

  final Uint8List bytes;

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  @override
  String toString() {
    final b32 = _encode(bytes);
    return [
      for (var i = 0; i < b32.length; i += 4) b32.substring(i, i + 4),
    ].join('-');
  }

  /// Bytes of a typed-in recovery key, or null if it can't be one.
  static Uint8List? parse(String text) {
    final s = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('8', 'B');
    if (s.length != 32) return null;
    var buffer = 0, bits = 0;
    final out = <int>[];
    for (final ch in s.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out.length == 20 ? Uint8List.fromList(out) : null;
  }

  static String _encode(List<int> data) {
    final sb = StringBuffer();
    var buffer = 0, bits = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(_alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) sb.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return sb.toString();
  }
}

/// Encrypts / decrypts single column values with the data key.
///
/// Stored format: `enc1:` + base64(nonce‖ciphertext‖tag). The plaintext is
/// padded to a multiple of 16 bytes so the ciphertext doesn't give away a
/// password's exact length, and the column name is bound in as associated
/// data so a password can't be swapped into the MEGA key column unnoticed.
/// Empty values stay empty.
class FieldCipher {
  FieldCipher(this.dataKey);

  final SecretKey dataKey;

  static const prefix = 'enc1:';
  static final _aes = AesGcm.with256bits();

  static bool isEncrypted(String value) => value.startsWith(prefix);

  Future<String> encrypt(String plain, String column) async {
    if (plain.isEmpty) return '';
    final box = await _aes.encrypt(
      _pad(utf8.encode(plain)),
      secretKey: dataKey,
      nonce: _aes.newNonce(),
      aad: utf8.encode('mega_accounts.$column'),
    );
    return '$prefix${base64.encode(box.concatenation())}';
  }

  /// Throws [FieldDecryptException] when [stored] can't be opened with this
  /// key. Values without the `enc1:` prefix are returned as they are (rows
  /// saved before encryption was turned on).
  Future<String> decrypt(String stored, String column) async {
    if (!isEncrypted(stored)) return stored;
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(stored.substring(prefix.length)),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final padded = await _aes.decrypt(
        box,
        secretKey: dataKey,
        aad: utf8.encode('mega_accounts.$column'),
      );
      return utf8.decode(_unpad(padded));
    } catch (_) {
      throw FieldDecryptException(column);
    }
  }

  static List<int> _pad(List<int> data) {
    final n = 16 - data.length % 16;
    return [...data, ...List<int>.filled(n, n)];
  }

  static List<int> _unpad(List<int> data) {
    if (data.isEmpty) throw const FormatException('empty');
    final n = data.last;
    if (n < 1 || n > 16 || n > data.length) {
      throw const FormatException('bad padding');
    }
    for (var i = data.length - n; i < data.length; i++) {
      if (data[i] != n) throw const FormatException('bad padding');
    }
    return data.sublist(0, data.length - n);
  }
}

class FieldDecryptException implements Exception {
  FieldDecryptException(this.column);
  final String column;

  @override
  String toString() => "Couldn't decrypt $column";
}
