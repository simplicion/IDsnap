import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tiny key-value store for the trial record and the cached entitlement.
abstract interface class BillingStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [BillingStorage] on flutter_secure_storage, in its own container so a
/// problem with other secrets never touches billing state (and vice versa):
/// - Android: its own storage namespace, encrypted with a Keystore key.
///   Android Auto Backup may copy the file, but the Keystore key never
///   leaves the device, so a restored copy can't be decrypted: reads then
///   fail, the engine deletes the unreadable keys and the install starts a
///   fresh trial (same as a reinstall; see ADR-0009).
/// - iOS: Keychain items, `first_unlock_this_device`, not synchronized.
///   Keychain items survive an uninstall, so reinstalling on iOS does not
///   reset the trial.
class SecureBillingStorage implements BillingStorage {
  SecureBillingStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: android, iOptions: ios);

  /// Own namespace (data, key aliases, markers). A decryption error resets
  /// only this namespace, never other secrets.
  static const android = AndroidOptions(storageNamespace: 'idsnap_billing');
  static const ios = IOSOptions(
    accountName: 'idsnap.billing',
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
}

/// In-memory [BillingStorage] for tests and unsupported platforms.
class MemoryBillingStorage implements BillingStorage {
  MemoryBillingStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
