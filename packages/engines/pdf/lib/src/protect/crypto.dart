import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// Thin, synchronous wrappers over pointycastle (MIT-style licence, the Dart
// port of Bouncy Castle) for the two file-protection formats:
//  * PDF standard security handler R6 (ISO 32000-2 §7.6.4.3): AES-256-CBC,
//    SHA-256/384/512, AES-128-CBC inside the hardened hash (Algorithm 2.B).
//  * WinZip AE-2: AES-256-CTR (little-endian counter), HMAC-SHA1,
//    PBKDF2-HMAC-SHA1 with 1000 iterations.
// Everything here is plain data in, plain data out, so it runs inside
// background isolates.

final Random _random = Random.secure();

/// Cryptographically secure random bytes.
Uint8List secureRandomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

Uint8List sha256(List<int> data) => _digest(SHA256Digest(), data);
Uint8List sha384(List<int> data) => _digest(SHA384Digest(), data);
Uint8List sha512(List<int> data) => _digest(SHA512Digest(), data);

Uint8List _digest(Digest digest, List<int> data) =>
    digest.process(data is Uint8List ? data : Uint8List.fromList(data));

/// HMAC-SHA1 of [data] with [key] (RFC 2104).
Uint8List hmacSha1(List<int> key, List<int> data) {
  final mac = HMac(SHA1Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(key)));
  return mac.process(Uint8List.fromList(data));
}

/// PBKDF2-HMAC-SHA1 (RFC 8018 §5.2).
Uint8List pbkdf2HmacSha1(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, length));
  return kdf.process(Uint8List.fromList(password));
}

/// AES in CBC mode without padding; [data] must be a multiple of 16 bytes.
Uint8List aesCbcNoPad(
  List<int> key,
  List<int> iv,
  List<int> data, {
  required bool encrypt,
}) {
  if (data.length % 16 != 0) {
    throw ArgumentError('AES-CBC data must be a multiple of 16 bytes');
  }
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      encrypt,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
    );
  final input = data is Uint8List ? data : Uint8List.fromList(data);
  final out = Uint8List(input.length);
  for (var off = 0; off < input.length; off += 16) {
    cipher.processBlock(input, off, out, off);
  }
  return out;
}

/// AES-CBC with PKCS#7 padding: returns `iv || ciphertext` (the PDF string
/// and stream layout, ISO 32000-2 §7.6.3).
Uint8List aesCbcEncryptWithIv(List<int> key, List<int> plain) {
  final iv = secureRandomBytes(16);
  final pad = 16 - plain.length % 16;
  final padded = Uint8List(plain.length + pad)
    ..setAll(0, plain)
    ..fillRange(plain.length, plain.length + pad, pad);
  final body = aesCbcNoPad(key, iv, padded, encrypt: true);
  return Uint8List(16 + body.length)
    ..setAll(0, iv)
    ..setAll(16, body);
}

/// Inverse of [aesCbcEncryptWithIv]. Throws [FormatException] on bad
/// length or padding.
Uint8List aesCbcDecryptWithIv(List<int> key, List<int> data) {
  if (data.length < 32 || data.length % 16 != 0) {
    throw const FormatException('Bad AES ciphertext length');
  }
  final plain = aesCbcNoPad(
    key,
    data.sublist(0, 16),
    data.sublist(16),
    encrypt: false,
  );
  final pad = plain.last;
  if (pad < 1 || pad > 16) throw const FormatException('Bad AES padding');
  for (var i = plain.length - pad; i < plain.length; i++) {
    if (plain[i] != pad) throw const FormatException('Bad AES padding');
  }
  return Uint8List.sublistView(plain, 0, plain.length - pad);
}

/// One AES-256 block in ECB mode (used only for the R6 `/Perms` entry).
Uint8List aesEcbBlock(List<int> key, List<int> block, {required bool encrypt}) {
  final engine = AESEngine()
    ..init(encrypt, KeyParameter(Uint8List.fromList(key)));
  final out = Uint8List(16);
  engine.processBlock(Uint8List.fromList(block), 0, out, 0);
  return out;
}

/// AES-CTR as WinZip AES specifies it: the 16-byte counter block holds a
/// little-endian block number starting at 1. Symmetric, streaming.
class WinZipAesCtr {
  WinZipAesCtr(List<int> key)
    : _aes = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));

  final AESEngine _aes;
  final _counter = Uint8List(16);
  final _keystream = Uint8List(16);
  int _used = 16;

  void _nextBlock() {
    for (var i = 0; i < 16; i++) {
      _counter[i] = (_counter[i] + 1) & 0xFF;
      if (_counter[i] != 0) break;
    }
    _aes.processBlock(_counter, 0, _keystream, 0);
    _used = 0;
  }

  /// XORs [data] in place with the key stream.
  void process(Uint8List data) {
    var i = 0;
    final n = data.length;
    while (i < n) {
      if (_used == 16) _nextBlock();
      final take = min(16 - _used, n - i);
      for (var k = 0; k < take; k++) {
        data[i + k] ^= _keystream[_used + k];
      }
      _used += take;
      i += take;
    }
  }
}

/// Streaming HMAC-SHA1.
class HmacSha1Stream {
  HmacSha1Stream(List<int> key)
    : _mac = HMac(SHA1Digest(), 64)
        ..init(KeyParameter(Uint8List.fromList(key)));

  final HMac _mac;

  void add(Uint8List data) => _mac.update(data, 0, data.length);

  Uint8List close() {
    final out = Uint8List(_mac.macSize);
    _mac.doFinal(out, 0);
    return out;
  }
}

/// Constant-time comparison.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
