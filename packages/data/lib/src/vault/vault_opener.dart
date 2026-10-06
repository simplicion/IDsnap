import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/src/json_stores.dart';
import 'package:docscan_data/src/vault/encrypted_database.dart';
import 'package:docscan_data/src/vault/shred.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// What the data layer needs to encrypt the vault (ADR-0010).
class VaultSecurity {
  const VaultSecurity({required this.keys, required this.crypto});

  final VaultKeyStore keys;
  final VaultCrypto crypto;
}

/// Why the vault can't be opened on this phone.
enum VaultUnavailableReason {
  /// Encrypted data exists but the key is gone (restored backup, new phone,
  /// reset keystore).
  keyMissing,

  /// A key exists but it isn't the one the data was encrypted with.
  keyMismatch,

  /// The keystore couldn't be read (locked, broken).
  keystoreError,
}

/// Thrown by `openDataLayer` instead of silently creating a new key over
/// existing encrypted data. The app shows a recovery screen.
class VaultUnavailableException implements Exception {
  const VaultUnavailableException(this.reason, [this.cause]);

  final VaultUnavailableReason reason;
  final Object? cause;

  @override
  String toString() => 'VaultUnavailableException(${reason.name})';
}

/// The unlocked vault: key, file cipher and SQLCipher key.
class OpenedVault {
  const OpenedVault({
    required this.key,
    required this.cipher,
    required this.databaseKey,
    required this.created,
  });

  final VaultKey key;
  final FileCipher cipher;
  final Uint8List databaseKey;

  /// True when a new key was generated on this launch.
  final bool created;
}

/// `<root>/vault.json`: the key check value (not secret) that proves which
/// key the data belongs to.
abstract final class VaultStateFile {
  static const name = 'vault.json';

  /// Every directory whose files are encrypted.
  static const encryptedDirectories = [
    'documents',
    'originals',
    'thumbs',
    'signatures',
  ];

  static String path(String root) => p.join(root, name);

  static Future<String?> readKeyCheck(String root) async {
    final f = File(path(root));
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return j['keyCheck'] as String?;
    } on Object {
      // Unreadable state: treat as "encrypted data may exist" (fail closed).
      return '';
    }
  }

  static Future<void> write(String root, String keyCheck) => writeAtomically(
    path(root),
    jsonEncode({'version': 1, 'keyCheck': keyCheck}),
  );
}

/// Loads (or, for a vault without encrypted data, creates) the master key.
/// Never creates a new key over existing encrypted data.
Future<OpenedVault> openVault(String root, VaultSecurity security) async {
  final stored = await VaultStateFile.readKeyCheck(root);
  VaultKey? key;
  try {
    key = await security.keys.read();
  } on Object catch (e) {
    throw VaultUnavailableException(VaultUnavailableReason.keystoreError, e);
  }
  var created = false;
  if (key == null) {
    if (stored != null || await hasEncryptedContent(root)) {
      throw const VaultUnavailableException(VaultUnavailableReason.keyMissing);
    }
    try {
      key = await security.keys.create();
    } on Object catch (e) {
      throw VaultUnavailableException(VaultUnavailableReason.keystoreError, e);
    }
    created = true;
  }
  final check = await security.crypto.keyCheck(key);
  if (stored != null && stored != check) {
    throw const VaultUnavailableException(VaultUnavailableReason.keyMismatch);
  }
  // Recorded before anything is encrypted with this key.
  if (stored == null) await VaultStateFile.write(root, check);
  return OpenedVault(
    key: key,
    cipher: security.crypto.fileCipher(key),
    databaseKey: await security.crypto.deriveKey(key, 'sqlcipher/v1'),
    created: created,
  );
}

const _magicLength = 8;

/// True when any vault file or the database is already encrypted.
Future<bool> hasEncryptedContent(String root) async {
  final db = File(p.join(root, 'library.sqlite'));
  if (db.existsSync() &&
      db.lengthSync() > 0 &&
      !EncryptedDatabase.isPlaintext(db.path)) {
    return true;
  }
  for (final d in VaultStateFile.encryptedDirectories) {
    final dir = Directory(p.join(root, d));
    if (!dir.existsSync()) continue;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final raf = await e.open();
      try {
        final head = await raf.read(_magicLength);
        if (head.length == _magicLength && head[0] == 0x89 && head[1] == 0x49) {
          if (String.fromCharCodes(head.sublist(1, 7)) == 'IDSVLT') return true;
        }
      } finally {
        await raf.close();
      }
    }
  }
  return false;
}

/// "Erase vault and start fresh": shreds every file under [root] and
/// [cacheRoot], and deletes the key. Irreversible.
Future<void> eraseVault({
  required String root,
  required VaultKeyStore keys,
  String? cacheRoot,
}) async {
  await shredDirectory(root);
  if (cacheRoot != null && cacheRoot != root) await shredDirectory(cacheRoot);
  try {
    await keys.delete();
  } on Object catch (e) {
    RedactedLogger(
      'vault',
    ).warn('key_delete_failed', {'type': e.runtimeType.toString()});
  }
}
