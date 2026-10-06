import 'dart:io';

import 'package:docscan_data/src/drift_authenticator_repository.dart';
import 'package:docscan_data/src/json_stores.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// Authenticator accounts with their secrets and recovery codes (audit
/// H-04). The backup holding this section must be password-protected and
/// the export re-authenticated: the UI enforces both.
class AuthenticatorBackupSection implements BackupSection {
  AuthenticatorBackupSection(this._repo);

  static const sectionKey = 'authenticator';

  final DriftAuthenticatorRepository _repo;

  @override
  String get key => sectionKey;

  @override
  String get label => 'Authenticator accounts';

  @override
  Future<BackupSectionData?> export() async {
    final accounts = await _repo.exportAccounts();
    if (accounts.isEmpty) return null;
    return BackupSectionData(
      version: 1,
      data: accounts,
      count: accounts.length,
    );
  }

  @override
  Future<int> restore(Object? data, {required int version}) =>
      _repo.restoreAccounts(data);

  @override
  Future<void> erase() => _repo.eraseAll();
}

/// App settings (theme, scan defaults, App Lock…).
class SettingsBackupSection implements BackupSection {
  SettingsBackupSection(this._store);

  static const sectionKey = 'settings';

  final JsonSettingsStore _store;

  @override
  String get key => sectionKey;

  @override
  String get label => 'Settings';

  @override
  Future<BackupSectionData?> export() async => BackupSectionData(
    version: 1,
    data: (await _store.load()).toJson(),
    count: 1,
  );

  /// Settings from the backup replace this phone's (moving phones is the
  /// point of the backup). Counted as one item.
  @override
  Future<int> restore(Object? data, {required int version}) async {
    if (data is! Map) return 0;
    await _store.save(AppSettings.fromJson(data.cast<String, dynamic>()));
    return 1;
  }

  @override
  Future<void> erase() async {
    final f = File(_store.path);
    if (f.existsSync()) await f.delete();
  }
}

/// Keystore entries under fixed prefixes (folder and note PIN hashes and
/// their failure counters). Erase only: PINs never leave the phone.
class SecretPrefixEraser implements Erasable {
  SecretPrefixEraser(this._secrets, this.prefixes, {required this.label});

  final SecretStore _secrets;
  final List<String> prefixes;

  @override
  final String label;

  @override
  Future<void> erase() async {
    for (final key in await _secrets.keys()) {
      if (prefixes.any(key.startsWith)) await _secrets.delete(key);
    }
  }
}
