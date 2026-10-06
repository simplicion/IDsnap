import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The Play Console "Licensing" public key (Monetize › Monetization setup),
/// base64 X.509 SubjectPublicKeyInfo. Passed at build time:
///
///     flutter build appbundle --release \
///       --dart-define=IDSNAP_PLAY_LICENSE_KEY=MIIBIjANBgkqh...
///
/// It is a public key, so embedding it is fine. When empty, Android purchase
/// signatures are not checked locally (debug and sideloaded builds).
const playLicenseKey = String.fromEnvironment('IDSNAP_PLAY_LICENSE_KEY');

/// Checks a Google Play purchase signature on the device: RSASSA-PKCS1-v1_5
/// with SHA-1 over the purchase's original JSON, against the app's license
/// public key. Nothing is sent anywhere.
///
/// This stops forged purchase data injected into the app process from a
/// fake billing service; it can't stop someone who patches the app itself.
/// There's no server, by design (ADR-0008, ADR-0009).
class PlaySignatureVerifier {
  PlaySignatureVerifier._(this._modulus, this._exponent, this._length);

  /// Parses a base64 SubjectPublicKeyInfo. Returns null if [base64Key] is
  /// empty or not an RSA public key.
  static PlaySignatureVerifier? fromBase64(String base64Key) {
    final trimmed = base64Key.replaceAll(RegExp(r'\s'), '');
    if (trimmed.isEmpty) return null;
    try {
      final der = base64.decode(trimmed);
      final key = _parseSpki(der);
      if (key == null) return null;
      final (n, e) = key;
      return PlaySignatureVerifier._(n, e, (n.bitLength + 7) ~/ 8);
    } on FormatException {
      return null;
    }
  }

  final BigInt _modulus;
  final BigInt _exponent;
  final int _length;

  /// True if [signatureBase64] is a valid signature of [signedData].
  bool verify(String signedData, String signatureBase64) {
    final Uint8List sig;
    try {
      sig = base64.decode(signatureBase64.trim());
    } on FormatException {
      return false;
    }
    if (sig.length != _length) return false;
    final s = _toBigInt(sig);
    if (s >= _modulus) return false;
    final em = _toBytes(s.modPow(_exponent, _modulus), _length);
    final expected = _encode(utf8.encode(signedData));
    if (expected.length != em.length) return false;
    var diff = 0;
    for (var i = 0; i < em.length; i++) {
      diff |= em[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// EMSA-PKCS1-v1_5 encoding of SHA-1(message).
  Uint8List _encode(List<int> message) {
    const sha1DigestInfo = [
      0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, //
      0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
    ];
    final t = [...sha1DigestInfo, ...sha1.convert(message).bytes];
    final padLength = _length - t.length - 3;
    if (padLength < 8) return Uint8List(0);
    return Uint8List.fromList([
      0x00,
      0x01,
      for (var i = 0; i < padLength; i++) 0xff,
      0x00,
      ...t,
    ]);
  }

  static BigInt _toBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _toBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  /// SubjectPublicKeyInfo → (modulus, exponent) for rsaEncryption keys.
  static (BigInt, BigInt)? _parseSpki(Uint8List der) {
    final r = _DerReader(der);
    final spki = r.read(0x30);
    final alg = spki.read(0x30);
    final oid = alg.readBytes(0x06);
    const rsaEncryption = [
      0x2a,
      0x86,
      0x48,
      0x86,
      0xf7,
      0x0d,
      0x01,
      0x01,
      0x01,
    ];
    if (oid.length != rsaEncryption.length) return null;
    for (var i = 0; i < oid.length; i++) {
      if (oid[i] != rsaEncryption[i]) return null;
    }
    final bits = spki.readBytes(0x03);
    if (bits.isEmpty || bits[0] != 0) return null;
    final rsa = _DerReader(Uint8List.sublistView(bits, 1)).read(0x30);
    final n = _toBigInt(rsa.readBytes(0x02));
    final e = _toBigInt(rsa.readBytes(0x02));
    if (n.bitLength < 1024 || e <= BigInt.one) return null;
    return (n, e);
  }
}

/// Minimal DER reader (definite lengths only) for the key above.
class _DerReader {
  _DerReader(this._bytes);

  final Uint8List _bytes;
  var _pos = 0;

  Uint8List readBytes(int tag) {
    if (_pos + 2 > _bytes.length || _bytes[_pos] != tag) {
      throw const FormatException('Unexpected DER tag');
    }
    _pos++;
    var length = _bytes[_pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || _pos + count > _bytes.length) {
        throw const FormatException('Bad DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[_pos++];
      }
    }
    if (_pos + length > _bytes.length) {
      throw const FormatException('Truncated DER');
    }
    final value = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return value;
  }

  _DerReader read(int tag) => _DerReader(readBytes(tag));
}
