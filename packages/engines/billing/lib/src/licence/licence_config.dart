import 'package:engine_license/engine_license.dart';

/// Licence server base URL, set at build time:
/// `--dart-define=IDSNAP_LICENSE_URL=https://licence.example.com`.
const licenceUrlDefine = String.fromEnvironment('IDSNAP_LICENSE_URL');

/// The licence server's Ed25519 PUBLIC key (base64url), set at build time:
/// `--dart-define=IDSNAP_LICENSE_PUBLIC_KEY=...` (from `tool/keygen.dart`).
const licencePublicKeyDefine = String.fromEnvironment(
  'IDSNAP_LICENSE_PUBLIC_KEY',
);

/// Debug default: the server on this machine. The Android emulator reaches
/// the host as 10.0.2.2.
const debugLicenceUrl = 'http://localhost:8080';

/// A licensing build configuration that must not ship.
class LicenceConfigError extends Error {
  LicenceConfigError(this.message);

  final String message;

  @override
  String toString() => 'LicenceConfigError: $message';
}

/// The resolved licence settings for this build.
class LicenceSettings {
  const LicenceSettings({required this.baseUrl, required this.publicKey});

  final Uri baseUrl;

  /// base64url Ed25519 public key.
  final String publicKey;
}

/// Resolves and checks the build configuration. Release builds fail fast
/// (throw [LicenceConfigError]) when the URL is missing or not https, or
/// the key is missing, malformed or the published dev key. Debug and
/// profile builds fall back to [debugLicenceUrl] and the dev key.
LicenceSettings resolveLicenceSettings({
  required bool release,
  String url = licenceUrlDefine,
  String publicKey = licencePublicKeyDefine,
}) {
  final rawUrl = url.trim();
  final rawKey = publicKey.trim();
  if (release) {
    final uri = Uri.tryParse(rawUrl);
    if (rawUrl.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw LicenceConfigError(
        'Release builds need --dart-define=IDSNAP_LICENSE_URL=https://...',
      );
    }
    if (rawKey.isEmpty || decodeLicenceKey(rawKey) == null) {
      throw LicenceConfigError(
        'Release builds need --dart-define=IDSNAP_LICENSE_PUBLIC_KEY=<key> '
        '(apps/license_server/tool/keygen.dart).',
      );
    }
    if (isDevLicencePublicKey(rawKey)) {
      throw LicenceConfigError(
        'IDSNAP_LICENSE_PUBLIC_KEY is the published dev key; release builds '
        'refuse it.',
      );
    }
    return LicenceSettings(baseUrl: uri, publicKey: rawKey);
  }
  final uri = Uri.tryParse(rawUrl.isEmpty ? debugLicenceUrl : rawUrl);
  if (uri == null || uri.host.isEmpty) {
    throw LicenceConfigError('IDSNAP_LICENSE_URL is not a URL.');
  }
  final key = rawKey.isEmpty ? DevLicenceKeys.publicKey : rawKey;
  if (decodeLicenceKey(key) == null) {
    throw LicenceConfigError('IDSNAP_LICENSE_PUBLIC_KEY is malformed.');
  }
  return LicenceSettings(baseUrl: uri, publicKey: key);
}
