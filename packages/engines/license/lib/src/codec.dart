import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:engine_license/src/payload.dart';

/// Why a token string could not be turned into a trusted payload.
enum LicenceTokenError {
  /// Not `base64url.base64url`, not JSON, or a required claim is missing.
  malformed,

  /// The signature doesn't match the payload for this public key (tampered
  /// payload, or signed with a different key).
  badSignature,

  /// Signed by us, but a format version this build doesn't understand.
  unsupportedVersion,
}

class LicenceTokenException implements Exception {
  const LicenceTokenException(this.error);

  final LicenceTokenError error;

  @override
  String toString() => 'LicenceTokenException(${error.name})';
}

// The pure-Dart implementation, on purpose: the same code runs in the app,
// on the server and in tests, with no platform channel.
final _ed25519 = DartEd25519(sha512: const DartSha512());

/// Longest token accepted. Real tokens are about 300 characters.
const maxLicenceTokenLength = 2048;

const _signatureLength = 64;
const _keyLength = 32;

final _base64UrlChars = RegExp(r'^[A-Za-z0-9_-]+$');

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List? _unb64(String text) {
  if (!_base64UrlChars.hasMatch(text)) return null;
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    return null;
  }
}

/// Decodes a 32-byte key written as base64url or standard base64, with or
/// without padding. Returns null for anything else.
Uint8List? decodeLicenceKey(String text) {
  final cleaned = text
      .trim()
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
  final bytes = _unb64(cleaned);
  return bytes == null || bytes.length != _keyLength ? null : bytes;
}

/// Encodes a key as unpadded base64url (safe in env vars and --dart-define).
String encodeLicenceKey(List<int> bytes) => _b64(bytes);

/// Signs licence tokens. Server only: needs the private key.
class LicenceSigner {
  LicenceSigner._(this._keyPair, this.publicKey);

  /// [seed] is the 32-byte Ed25519 private key seed.
  static Future<LicenceSigner> fromSeed(List<int> seed) async {
    if (seed.length != _keyLength) {
      throw ArgumentError('An Ed25519 seed is $_keyLength bytes.');
    }
    final pair = await _ed25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return LicenceSigner._(pair, Uint8List.fromList(public.bytes));
  }

  /// [key] as produced by `tool/keygen.dart` (base64url, 32 bytes).
  static Future<LicenceSigner> fromEncodedSeed(String key) {
    final seed = decodeLicenceKey(key);
    if (seed == null) {
      throw const FormatException(
        'The signing key must be 32 bytes, base64url encoded.',
      );
    }
    return fromSeed(seed);
  }

  final SimpleKeyPair _keyPair;

  /// The matching public key (what the app ships).
  final Uint8List publicKey;

  Future<String> sign(LicencePayload payload) async {
    final body = utf8.encode(jsonEncode(payload.toJson()));
    final signature = await _ed25519.sign(body, keyPair: _keyPair);
    return '${_b64(body)}.${_b64(signature.bytes)}';
  }
}

/// Verifies licence tokens offline with the public key only.
class LicenceVerifier {
  LicenceVerifier(List<int> publicKey)
    : _publicKey = SimplePublicKey(
        List<int>.unmodifiable(publicKey),
        type: KeyPairType.ed25519,
      ) {
    if (publicKey.length != _keyLength) {
      throw ArgumentError('An Ed25519 public key is $_keyLength bytes.');
    }
  }

  /// Throws [FormatException] if [key] isn't a base64url 32-byte key.
  factory LicenceVerifier.fromEncodedKey(String key) {
    final bytes = decodeLicenceKey(key);
    if (bytes == null) {
      throw const FormatException(
        'The licence public key must be 32 bytes, base64url encoded.',
      );
    }
    return LicenceVerifier(bytes);
  }

  final SimplePublicKey _publicKey;

  /// Returns the payload if [token] is well formed, signed by our key and
  /// of a supported version. Throws [LicenceTokenException] otherwise.
  ///
  /// This says nothing about the device or the expiry: see `checkLicence`.
  /// The signature is checked before the payload is parsed, so unsigned
  /// JSON is never interpreted.
  Future<LicencePayload> verify(String token) async {
    if (token.length > maxLicenceTokenLength) {
      throw const LicenceTokenException(LicenceTokenError.malformed);
    }
    final parts = token.split('.');
    if (parts.length != 2) {
      throw const LicenceTokenException(LicenceTokenError.malformed);
    }
    final body = _unb64(parts[0]);
    final signature = _unb64(parts[1]);
    if (body == null || signature == null) {
      throw const LicenceTokenException(LicenceTokenError.malformed);
    }
    if (signature.length != _signatureLength) {
      throw const LicenceTokenException(LicenceTokenError.badSignature);
    }
    var ok = false;
    try {
      ok = await _ed25519.verify(
        body,
        signature: Signature(signature, publicKey: _publicKey),
      );
    } on Object {
      ok = false;
    }
    if (!ok) throw const LicenceTokenException(LicenceTokenError.badSignature);

    Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      throw const LicenceTokenException(LicenceTokenError.malformed);
    }
    final payload = LicencePayload.fromJson(json);
    if (payload == null) {
      throw const LicenceTokenException(LicenceTokenError.malformed);
    }
    if (payload.version != LicencePayload.currentVersion) {
      throw const LicenceTokenException(LicenceTokenError.unsupportedVersion);
    }
    return payload;
  }
}

/// A fresh Ed25519 key pair as (private seed, public key), both base64url.
Future<({String privateKey, String publicKey})> generateLicenceKeyPair() async {
  final pair = await _ed25519.newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final public = await pair.extractPublicKey();
  return (
    privateKey: encodeLicenceKey(seed),
    publicKey: encodeLicenceKey(public.bytes),
  );
}
