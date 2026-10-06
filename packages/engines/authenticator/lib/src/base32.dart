import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';

/// RFC 4648 Base32 (the alphabet used by every authenticator QR code).
abstract final class Base32 {
  static const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Shortest accepted secret: 80 bits, the size most websites issue (RFC
  /// 4226 recommends 160). Anything shorter is almost surely a typo.
  static const minSecretBytes = 10;

  /// Longest accepted secret. SHA-512 keys are 64 bytes; this leaves room.
  static const maxSecretBytes = 256;

  static const tooShort =
      'The key is too short. Copy the whole key from the website.';
  static const tooLong = 'The key is too long to be an authenticator key.';
  static const empty = 'Enter the secret key.';
  static const badCharacter =
      'The key has a character that is not allowed. Use A–Z and 2–7 only '
      '(no 0, 1, 8 or 9).';
  static const badLength =
      'The key has the wrong length. Check you copied every character.';

  /// Uppercase, drops whitespace and dashes (as printed by some websites)
  /// and trailing `=` padding. Does not validate.
  static String clean(String input) => input
      .replaceAll(RegExp(r'[\s-]'), '')
      .toUpperCase()
      .replaceFirst(RegExp(r'=+$'), '');

  /// Canonical form of a valid secret (see [clean]) or a failure.
  static Result<String> normalize(String input) =>
      decode(input).map((_) => clean(input));

  /// Decodes [input], tolerating spaces, dashes, lowercase and missing
  /// padding. Rejects characters outside the alphabet, impossible lengths,
  /// stray padding and secrets outside [minSecretBytes]..[maxSecretBytes].
  static Result<Uint8List> decode(String input) {
    final s = clean(input);
    if (s.isEmpty) return _fail(empty);
    if (s.contains('=')) return _fail(badCharacter);
    for (var i = 0; i < s.length; i++) {
      if (!alphabet.contains(s[i])) return _fail(badCharacter);
    }
    // Valid unpadded lengths: 8n + {0, 2, 4, 5, 7} characters.
    if (const {1, 3, 6}.contains(s.length % 8)) return _fail(badLength);
    final out = Uint8List(s.length * 5 ~/ 8);
    var buffer = 0;
    var bits = 0;
    var index = 0;
    for (var i = 0; i < s.length; i++) {
      buffer = (buffer << 5) | alphabet.indexOf(s[i]);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out[index++] = (buffer >> bits) & 0xFF;
      }
      buffer &= (1 << bits) - 1;
    }
    if (out.length < minSecretBytes) return _fail(tooShort);
    if (out.length > maxSecretBytes) return _fail(tooLong);
    return Ok(out);
  }

  /// Unpadded Base32 of [bytes].
  static String encode(List<int> bytes) {
    final sb = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xFF);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(alphabet[(buffer >> bits) & 0x1F]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) sb.write(alphabet[(buffer << (5 - bits)) & 0x1F]);
    return sb.toString();
  }

  static Result<Uint8List> _fail(String message) =>
      Err(AppFailure(FailureCode.invalidSecretKey, detail: message));
}
