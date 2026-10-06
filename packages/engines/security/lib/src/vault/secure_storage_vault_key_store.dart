import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// [VaultKeyStore] on a [SecretStore] (`flutter_secure_storage` in the app:
/// Android Keystore-backed, iOS Keychain `first_unlock_this_device`, never
/// synchronized or migrated to another phone).
///
/// The key is stored as `{"v":1,"id":1,"key":"<base64>"}` under [storageKey].
/// A present-but-unreadable entry is a failure, never "no key": creating a
/// new key over it would make the existing vault unreadable.
class SecureStorageVaultKeyStore implements VaultKeyStore {
  SecureStorageVaultKeyStore(this._secrets, {Random? random})
    : _random = random ?? Random.secure();

  static const storageKey = 'vault.master_key.v1';
  static const currentKeyId = 1;

  final SecretStore _secrets;
  final Random _random;

  static const _unavailable = AppFailure(
    FailureCode.secretUnavailable,
    message:
        "IDSnap can't read its encryption key on this phone, so your vault "
        "can't be opened.",
    action: FailureAction.none,
  );

  @override
  Future<VaultKey?> read() async {
    final String? raw;
    try {
      raw = await _secrets.read(storageKey);
    } on Object catch (e, st) {
      throw AppFailure(
        _unavailable.code,
        message: _unavailable.message,
        action: _unavailable.action,
        cause: e,
        stackTrace: st,
      );
    }
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final bytes = base64Decode(j['key'] as String);
      if (j['v'] != 1 || bytes.length != 32) throw const FormatException();
      return VaultKey(id: j['id'] as int, bytes: bytes);
    } on Object {
      throw _unavailable;
    }
  }

  @override
  Future<VaultKey> create() async {
    final key = VaultKey(
      id: currentKeyId,
      bytes: Uint8List.fromList(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      ),
    );
    await _secrets.write(
      storageKey,
      jsonEncode({'v': 1, 'id': key.id, 'key': base64Encode(key.bytes)}),
    );
    // Read back: a keystore that silently drops writes must fail here, not
    // after files were encrypted with a key that is gone.
    final stored = await read();
    if (stored == null || !_equal(stored.bytes, key.bytes)) {
      throw _unavailable;
    }
    return key;
  }

  @override
  Future<void> delete() => _secrets.delete(storageKey);

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
