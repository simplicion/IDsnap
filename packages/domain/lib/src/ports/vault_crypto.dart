import 'dart:typed_data';

import 'package:meta/meta.dart';

// Encryption at rest (ADR-0010). Kept in their own file so no existing
// FileStore implementation or fake has to change.

/// The vault master key. [bytes] are 32 random bytes; [id] is written into
/// every file header so keys can be rotated later.
@immutable
class VaultKey {
  const VaultKey({required this.id, required this.bytes});

  final int id;
  final Uint8List bytes;

  /// Never print key material.
  @override
  String toString() => 'VaultKey(id: $id)';
}

/// Where the master key lives (the platform keystore in the app).
abstract interface class VaultKeyStore {
  /// The stored key, or null when none exists. Throws an `AppFailure`
  /// (`secretUnavailable`) when the keystore can't be read.
  Future<VaultKey?> read();

  /// Generates, stores and returns a new key, replacing any old one.
  Future<VaultKey> create();

  /// Deletes the key ("erase vault and start fresh").
  Future<void> delete();
}

/// Authenticated, streaming file encryption bound to one [VaultKey].
abstract interface class FileCipher {
  /// Bytes needed by [isEncrypted].
  int get headerLength;

  /// True when [head] (the first bytes of a file) starts a vault file.
  bool isEncrypted(List<int> head);

  /// Plaintext size of an encrypted file of [encryptedLength] bytes.
  int plaintextLength(int encryptedLength);

  /// Encrypts [source] into [target] (written atomically).
  Future<void> encryptFile(String source, String target);

  /// Decrypts [source] into [target] (written atomically; nothing is left
  /// behind when authentication fails).
  Future<void> decryptFile(String source, String target);

  Future<Uint8List> encryptBytes(List<int> plaintext);
  Future<Uint8List> decryptBytes(Uint8List encrypted);

  /// Reads and decrypts the whole file at [source].
  Future<Uint8List> decryptFileToBytes(String source);
}

/// Thrown by a [FileCipher] when data fails authentication (tampered,
/// truncated, reordered or encrypted with another key).
class VaultIntegrityException implements Exception {
  const VaultIntegrityException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultIntegrityException: $reason';
}

/// Crypto primitives built on a [VaultKey].
abstract interface class VaultCrypto {
  FileCipher fileCipher(VaultKey key);

  /// A 32-byte subkey for [purpose] (HKDF-SHA256).
  Future<Uint8List> deriveKey(VaultKey key, String purpose);

  /// A short, non-secret fingerprint of [key] used to detect a key that
  /// doesn't match the stored data.
  Future<String> keyCheck(VaultKey key);
}

/// Plaintext access for APIs that need a real file path (PDF renderer,
/// ML Kit, platform viewers). Bytes-oriented readers use `FileStore.read`,
/// which decrypts transparently.
abstract interface class PlainFileAccess {
  /// A private plaintext copy of [path] in the app cache, or [path] itself
  /// when it isn't encrypted. Pass [fileName] for a friendly name. Call
  /// [releaseTemp] when done; leftovers are shredded at the next launch.
  Future<String> decryptToTemp(String path, {String? fileName});

  /// Shreds a copy made by [decryptToTemp] (or `exportCopy`) after [grace].
  /// Anything else is left alone.
  Future<void> releaseTemp(String path, {Duration grace = Duration.zero});
}

/// [PlainFileAccess] for stores that don't encrypt (tests, previews).
class PassThroughFileAccess implements PlainFileAccess {
  const PassThroughFileAccess();

  @override
  Future<String> decryptToTemp(String path, {String? fileName}) async => path;

  @override
  Future<void> releaseTemp(
    String path, {
    Duration grace = Duration.zero,
  }) async {}
}
