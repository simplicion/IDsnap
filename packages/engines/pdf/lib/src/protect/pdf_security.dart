import 'dart:convert';
import 'dart:typed_data';

import 'package:engine_pdf/src/protect/crypto.dart';

// PDF standard security handler, revision 6 (AES-256, "AESV3"), as
// specified in ISO 32000-2:2020 §7.6.4.3–7.6.4.4:
//  * Algorithm 2.B — the hardened password hash;
//  * Algorithm 8/9 — /U, /UE and /O, /OE;
//  * Algorithm 10 — /Perms;
//  * Algorithm 11/12 — authenticating the user/owner password;
//  * Algorithm 13 — validating /Perms.
// Strings and streams are encrypted with AES-256-CBC under the file key
// directly (no per-object key in R6), each prefixed by a random 16-byte IV
// and PKCS#7-padded (§7.6.3.1).

/// Permission bits of `/P` (ISO 32000-2 Table 22, 1-based bit positions).
abstract final class PdfPermissionBits {
  static const print = 1 << 2; // bit 3
  static const modify = 1 << 3; // bit 4
  static const copy = 1 << 4; // bit 5
  static const annotate = 1 << 5; // bit 6
  static const fillForms = 1 << 8; // bit 9
  static const accessibility = 1 << 9; // bit 10
  static const assemble = 1 << 10; // bit 11
  static const printHighQuality = 1 << 11; // bit 12

  /// Bits 7–8 and 13–32 must be 1; bits 1–2 must be 0.
  static const _reserved = 0xFFFFF0C0;

  /// `/P` as the signed 32-bit integer written to the file. Extraction for
  /// accessibility (bit 10) is always granted, as ISO 32000-2 requires.
  static int value({
    required bool print,
    required bool copy,
    required bool edit,
  }) {
    var p = _reserved | accessibility;
    if (print) p |= PdfPermissionBits.print | printHighQuality;
    if (copy) p |= PdfPermissionBits.copy;
    if (edit) p |= modify | annotate | fillForms | assemble;
    return p.toSigned(32);
  }
}

/// UTF-8 password bytes, truncated to 127 bytes (§7.6.4.3.3). SASLprep is
/// the identity for the printable ASCII passwords the app generates.
Uint8List r6PasswordBytes(String password) {
  final bytes = utf8.encode(password);
  return Uint8List.fromList(bytes.length > 127 ? bytes.sublist(0, 127) : bytes);
}

/// ISO 32000-2 Algorithm 2.B: hash of [password] with an 8-byte [salt] and
/// [userKey] (the 48-byte /U for owner hashes, empty for user hashes).
Uint8List r6Hash(Uint8List password, List<int> salt, List<int> userKey) {
  var k = sha256([...password, ...salt, ...userKey]);
  var round = 0;
  while (true) {
    round++;
    final k1 = <int>[...password, ...k, ...userKey];
    final repeated = Uint8List(k1.length * 64);
    for (var i = 0; i < 64; i++) {
      repeated.setAll(i * k1.length, k1);
    }
    final e = aesCbcNoPad(
      k.sublist(0, 16),
      k.sublist(16, 32),
      repeated,
      encrypt: true,
    );
    // The first 16 bytes of E as a big-endian number, mod 3 (256 ≡ 1 mod 3,
    // so the byte sum has the same remainder).
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      sum += e[i];
    }
    k = switch (sum % 3) {
      0 => sha256(e),
      1 => sha384(e),
      _ => sha512(e),
    };
    // At least 64 rounds, then until the last byte of E <= round - 32
    // (the initial SHA-256 counts as round 0, as in qpdf and Acrobat).
    if (round >= 64 && e.last <= round - 32) break;
  }
  return Uint8List.sublistView(k, 0, 32);
}

/// The values of an R6 `/Encrypt` dictionary plus the file key.
final class PdfR6Security {
  const PdfR6Security({
    required this.fileKey,
    required this.o,
    required this.u,
    required this.oe,
    required this.ue,
    required this.perms,
    required this.permissions,
    this.encryptMetadata = true,
  });

  /// Algorithms 8, 9 and 10. Salts and the file key are random unless given
  /// (known-answer tests inject them).
  factory PdfR6Security.create({
    required String userPassword,
    required String ownerPassword,
    required int permissions,
    Uint8List? fileKey,
    Uint8List? userSalts,
    Uint8List? ownerSalts,
    Uint8List? permsRandom,
  }) {
    final key = fileKey ?? secureRandomBytes(32);
    final user = r6PasswordBytes(userPassword);
    final owner = r6PasswordBytes(ownerPassword);
    final zeroIv = Uint8List(16);

    // Algorithm 8: /U = hash(user, validation salt) || validation salt ||
    // key salt; /UE = AES-256-CBC(hash(user, key salt), key).
    final us = userSalts ?? secureRandomBytes(16);
    final u = Uint8List(48)
      ..setAll(0, r6Hash(user, us.sublist(0, 8), const []))
      ..setAll(32, us);
    final ue = aesCbcNoPad(
      r6Hash(user, us.sublist(8, 16), const []),
      zeroIv,
      key,
      encrypt: true,
    );

    // Algorithm 9: the same for the owner password, salted with /U.
    final os = ownerSalts ?? secureRandomBytes(16);
    final o = Uint8List(48)
      ..setAll(0, r6Hash(owner, os.sublist(0, 8), u))
      ..setAll(32, os);
    final oe = aesCbcNoPad(
      r6Hash(owner, os.sublist(8, 16), u),
      zeroIv,
      key,
      encrypt: true,
    );

    // Algorithm 10: /Perms = AES-256-ECB(key, P as 64-bit LE || 'T' ||
    // 'adb' || 4 random bytes).
    final block = Uint8List(16);
    final p = permissions & 0xFFFFFFFF;
    for (var i = 0; i < 4; i++) {
      block[i] = (p >> (8 * i)) & 0xFF;
    }
    block
      ..fillRange(4, 8, 0xFF)
      ..[8] =
          0x54 // 'T': metadata is encrypted
      ..[9] =
          0x61 // 'a'
      ..[10] =
          0x64 // 'd'
      ..[11] =
          0x62 // 'b'
      ..setAll(12, permsRandom ?? secureRandomBytes(4));
    final perms = aesEcbBlock(key, block, encrypt: true);

    return PdfR6Security(
      fileKey: key,
      o: o,
      u: u,
      oe: oe,
      ue: ue,
      perms: perms,
      permissions: permissions.toSigned(32),
    );
  }

  final Uint8List fileKey;
  final Uint8List o;
  final Uint8List u;
  final Uint8List oe;
  final Uint8List ue;
  final Uint8List perms;

  /// Signed 32-bit `/P`.
  final int permissions;
  final bool encryptMetadata;

  Uint8List encrypt(List<int> plain) => aesCbcEncryptWithIv(fileKey, plain);
  Uint8List decrypt(List<int> data) => aesCbcDecryptWithIv(fileKey, data);
}

/// Which password [authenticateR6] accepted.
enum PdfPasswordKind { user, owner }

/// Algorithms 11, 12 and 13: returns the file key and which password
/// matched, or null when [password] is neither. Throws [FormatException]
/// for malformed entries or a /Perms mismatch (tampering).
({Uint8List fileKey, PdfPasswordKind kind})? authenticateR6({
  required String password,
  required Uint8List o,
  required Uint8List u,
  required Uint8List oe,
  required Uint8List ue,
  required Uint8List perms,
  required int permissions,
}) {
  if (o.length < 48 || u.length < 48 || oe.length < 32 || ue.length < 32) {
    throw const FormatException('Malformed R6 encryption dictionary');
  }
  final pw = r6PasswordBytes(password);
  final u48 = u.sublist(0, 48);
  final zeroIv = Uint8List(16);
  Uint8List? key;
  PdfPasswordKind? kind;
  if (bytesEqual(r6Hash(pw, o.sublist(32, 40), u48), o.sublist(0, 32))) {
    key = aesCbcNoPad(
      r6Hash(pw, o.sublist(40, 48), u48),
      zeroIv,
      oe.sublist(0, 32),
      encrypt: false,
    );
    kind = PdfPasswordKind.owner;
  } else if (bytesEqual(
    r6Hash(pw, u.sublist(32, 40), const []),
    u.sublist(0, 32),
  )) {
    key = aesCbcNoPad(
      r6Hash(pw, u.sublist(40, 48), const []),
      zeroIv,
      ue.sublist(0, 32),
      encrypt: false,
    );
    kind = PdfPasswordKind.user;
  }
  if (key == null || kind == null) return null;
  final block = aesEcbBlock(key, perms.sublist(0, 16), encrypt: false);
  final p = permissions & 0xFFFFFFFF;
  final pOk = List.generate(4, (i) => (p >> (8 * i)) & 0xFF);
  if (block[9] != 0x61 ||
      block[10] != 0x64 ||
      block[11] != 0x62 ||
      !bytesEqual(block.sublist(0, 4), pOk)) {
    throw const FormatException('/Perms does not match /P');
  }
  return (fileKey: key, kind: kind);
}
