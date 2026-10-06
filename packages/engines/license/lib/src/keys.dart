/// DEV-ONLY licence key pair, for tests, debug builds and a local server.
///
/// !! NEVER USE IN PRODUCTION !! The private half is published right here,
/// so anyone can mint licences for it. Release builds of the app refuse
/// this public key, and the server refuses to start with this private key
/// unless ALLOW_DEV_KEY=true. Generate the real pair with
/// `dart run tool/keygen.dart` in apps/license_server.
abstract final class DevLicenceKeys {
  /// Ed25519 private seed (base64url). Public knowledge: dev only.
  static const privateKey = 'NpYuKxIgr-gwnsEap3kVB9Sqb7PIVOV_x4loo1t5pHo';

  /// The matching public key (base64url).
  static const publicKey = 'I6PVtFaHE674wflLberp0EqxT-0c-TPZN_DF_HkqPLY';
}

/// True if [encodedPublicKey] is the published dev key.
bool isDevLicencePublicKey(String encodedPublicKey) =>
    _normalise(encodedPublicKey) == DevLicenceKeys.publicKey;

/// True if [encodedPrivateKey] is the published dev key.
bool isDevLicencePrivateKey(String encodedPrivateKey) =>
    _normalise(encodedPrivateKey) == DevLicenceKeys.privateKey;

String _normalise(String key) =>
    key.trim().replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
