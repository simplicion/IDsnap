import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [SecretStore] on `flutter_secure_storage`: Android Keystore-backed
/// encrypted storage, iOS Keychain. Values never leave the device:
/// - iOS items are `first_unlock_this_device` and not synchronizable, so they
///   are excluded from iCloud Keychain and don't migrate to another phone.
/// - Android does not silently wipe storage on a decryption error
///   (`resetOnError: false`); the error surfaces as a typed failure instead,
///   so the user is told rather than finding their accounts gone.
class SecureStorageSecretStore implements SecretStore {
  SecureStorageSecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: android, iOptions: ios);

  static const android = AndroidOptions(resetOnError: false);
  static const ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Set<String>> keys() async => (await _storage.readAll()).keys.toSet();
}
