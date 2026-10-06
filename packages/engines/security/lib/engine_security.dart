/// Device security adapters: App Lock (biometric / device credential), the
/// secure-window flag that hides content from screenshots and the app
/// switcher, and encryption at rest (ADR-0010). On-device only — nothing
/// here uses the network.
library;

export 'src/folder_pin_store.dart';
export 'src/local_auth_app_lock.dart';
export 'src/secure_secret_store.dart';
export 'src/secure_window.dart';
export 'src/vault/secure_storage_vault_key_store.dart';
export 'src/vault/vault_cipher.dart' show AesGcmVaultCrypto, VaultFileCipher;
export 'src/vault/vault_format.dart' show VaultFormat;
