import 'dart:convert' show latin1;
import 'dart:typed_data';

import 'package:engine_pdf/src/protect/crypto.dart';
import 'package:engine_pdf/src/protect/pdf_security.dart';
import 'package:engine_pdf/src/stamp/pdf_syntax.dart';

// Full rewrite of a PDF with (or without) the R6 security handler.
//
// Encrypting an existing file cannot be an incremental update: every string
// and stream of every object must be encrypted. The rewrite therefore
// reads every in-use object through [PdfFile] (classic and stream xrefs,
// object streams), renumbers them densely, and writes a fresh file with a
// classic cross-reference table:
//  * object streams and xref streams are dropped (their objects are written
//    individually), as is a linearization dictionary (no longer valid);
//  * every string is written as an encrypted hex string and every stream's
//    (still-filtered) data is encrypted, with `/Length` made direct;
//  * the trailer gets `/Encrypt`, `/ID` and keeps `/Root` and `/Info`.
// Anything the reader can't parse throws [PdfSyntaxException]; the engine
// then retries on a PDFium re-save of the document.

/// The file declares a security handler this rewriter can't decrypt.
class PdfEncryptedInputException implements Exception {
  const PdfEncryptedInputException();

  @override
  String toString() => 'PdfEncryptedInputException';
}

/// The password did not open the file (pure-Dart R6 check).
class PdfWrongPasswordException implements Exception {
  const PdfWrongPasswordException();

  @override
  String toString() => 'PdfWrongPasswordException';
}

/// Encrypts [input] (an unencrypted PDF) with AES-256 (R6).
Uint8List encryptPdfR6(Uint8List input, PdfR6Security security) {
  final file = PdfFile(input);
  if (file.trailer.containsKey('Encrypt')) {
    throw const PdfEncryptedInputException();
  }
  return _rewrite(file, input, encrypt: security);
}

/// Decrypts an R6 (AES-256) PDF with its open or owner [password]. Throws
/// [PdfWrongPasswordException] for a wrong password and
/// [PdfEncryptedInputException] for other security handlers.
Uint8List decryptPdfR6(Uint8List input, String password) {
  final file = PdfFile(input);
  final encrypt = file.resolve(file.trailer['Encrypt']);
  if (encrypt is! Map<String, Object>) {
    throw const PdfSyntaxException('Not encrypted');
  }
  final info = readR6Dictionary(file, encrypt);
  if (info == null) throw const PdfEncryptedInputException();
  final auth = authenticateR6(
    password: password,
    o: info.o,
    u: info.u,
    oe: info.oe,
    ue: info.ue,
    perms: info.perms,
    permissions: info.p,
  );
  if (auth == null) throw const PdfWrongPasswordException();
  final ref = file.trailer['Encrypt'];
  final key = auth.fileKey;
  file.streamDecryptor = (data) => aesCbcDecryptWithIv(key, data);
  return _rewrite(
    file,
    input,
    decryptKey: auth.fileKey,
    skipObject: ref is PdfRef ? ref.number : null,
    decryptMetadata: info.encryptMetadata,
  );
}

/// The R6 entries of an `/Encrypt` dictionary, or null if it is not
/// `/Standard` revision 6.
({
  Uint8List o,
  Uint8List u,
  Uint8List oe,
  Uint8List ue,
  Uint8List perms,
  int p,
  bool encryptMetadata,
})?
readR6Dictionary(PdfFile file, Map<String, Object> dict) {
  final filter = dict['Filter'];
  if (filter is! PdfName || filter.value != 'Standard') return null;
  if (asInt(file.resolve(dict['R'])) != 6) return null;
  Uint8List bytesOf(String key) {
    final v = file.resolve(dict[key]);
    if (v is! PdfRawString) throw PdfSyntaxException('Missing /$key');
    return decodePdfString(v.bytes);
  }

  final p = asInt(file.resolve(dict['P']));
  if (p == null) throw const PdfSyntaxException('Missing /P');
  return (
    o: bytesOf('O'),
    u: bytesOf('U'),
    oe: bytesOf('OE'),
    ue: bytesOf('UE'),
    perms: bytesOf('Perms'),
    p: p,
    encryptMetadata: file.resolve(dict['EncryptMetadata']) != false,
  );
}

Uint8List _rewrite(
  PdfFile file,
  Uint8List input, {
  PdfR6Security? encrypt,
  Uint8List? decryptKey,
  int? skipObject,
  bool decryptMetadata = true,
}) {
  // 1. Collect the objects to keep.
  final kept = <int, Object>{};
  for (final n in file.objectNumbers.toList()..sort()) {
    if (n == 0 || n == skipObject) continue;
    final obj = file.object(n);
    if (obj is PdfNull) continue;
    if (obj is PdfStreamObject) {
      final type = obj.dict['Type'];
      if (type is PdfName && (type.value == 'XRef' || type.value == 'ObjStm')) {
        continue;
      }
    }
    if (obj is Map<String, Object> && obj.containsKey('Linearized')) continue;
    kept[n] = obj;
  }
  final renumber = <int, int>{};
  var next = 1;
  for (final n in kept.keys) {
    renumber[n] = next++;
  }

  // Strings of objects inside an (encrypted) object stream are plain.
  var inObjectStream = false;
  Uint8List transformString(Uint8List plain) {
    if (decryptKey != null) {
      if (inObjectStream) return plain;
      try {
        return aesCbcDecryptWithIv(decryptKey, plain);
      } on FormatException {
        // Some producers leave short strings unencrypted; keep the bytes.
        return plain;
      }
    }
    return encrypt != null ? encrypt.encrypt(plain) : plain;
  }

  Object transform(Object value) => switch (value) {
    final PdfRef r => switch (renumber[r.number]) {
      final int n => PdfRef(n, 0),
      null => pdfNull,
    },
    final PdfRawString s => hexString(
      transformString(decodePdfString(s.bytes)),
    ),
    final List<Object> list => [for (final v in list) transform(v)],
    final Map<String, Object> dict => {
      for (final e in dict.entries) e.key: transform(e.value),
    },
    _ => value,
  };

  // 2. Catalog: declare the Adobe extension level for AESV3 under 1.x.
  final version = _headerVersion(input);
  final pdf20 = version >= 20;
  final rootRef = file.trailer['Root'];
  if (rootRef is! PdfRef || kept[rootRef.number] is! Map<String, Object>) {
    throw const PdfSyntaxException('No document catalog');
  }

  // 3. Write.
  final w = PdfWriter()
    ..text(pdf20 ? '%PDF-2.0\n' : '%PDF-1.7\n')
    ..raw(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  final offsets = <int>[];
  for (final MapEntry(key: old, value: obj) in kept.entries) {
    final n = renumber[old]!;
    inObjectStream = file.isCompressed(old);
    offsets.add(w.length);
    w.text('$n 0 obj\n');
    if (obj is PdfStreamObject) {
      final dict = transform(obj.dict) as Map<String, Object>;
      var data = obj.data;
      final type = obj.dict['Type'];
      final isMetadata = type is PdfName && type.value == 'Metadata';
      final crypt = _usesCryptFilter(file, obj.dict);
      if (!crypt) {
        if (decryptKey != null && (decryptMetadata || !isMetadata)) {
          data = aesCbcDecryptWithIv(decryptKey, data);
        } else if (encrypt != null) {
          data = encrypt.encrypt(data);
        }
      }
      dict['Length'] = data.length;
      w
        ..value(dict)
        ..text('\nstream\n')
        ..raw(data)
        ..text('\nendstream\nendobj\n');
    } else {
      var value = transform(obj);
      if (old == rootRef.number && encrypt != null && !pdf20) {
        value = _withAdobeExtension(value as Map<String, Object>);
      }
      w
        ..value(value)
        ..text('\nendobj\n');
    }
  }

  int? encryptNumber;
  if (encrypt != null) {
    encryptNumber = next;
    offsets.add(w.length);
    w
      ..text('$encryptNumber 0 obj\n')
      ..value(_encryptDictionary(encrypt))
      ..text('\nendobj\n');
  }

  final size = offsets.length + 1;
  final xref = w.length;
  w.text('xref\n0 $size\n0000000000 65535 f\r\n');
  for (final off in offsets) {
    w.text('${off.toString().padLeft(10, '0')} 00000 n\r\n');
  }

  final trailer = <String, Object>{
    'Size': size,
    'Root': PdfRef(renumber[rootRef.number]!, 0),
  };
  final info = file.trailer['Info'];
  if (info is PdfRef && renumber.containsKey(info.number)) {
    trailer['Info'] = PdfRef(renumber[info.number]!, 0);
  }
  if (encryptNumber != null) {
    trailer['Encrypt'] = PdfRef(encryptNumber, 0);
  }
  // /ID: keep the permanent identifier, new "changing" identifier.
  final oldId = file.resolve(file.trailer['ID']);
  final first = oldId is List<Object> && oldId.isNotEmpty ? oldId.first : null;
  trailer['ID'] = [
    if (first is PdfRawString && decryptKey == null)
      hexString(decodePdfString(first.bytes))
    else
      hexString(secureRandomBytes(16)),
    hexString(secureRandomBytes(16)),
  ];
  w
    ..text('trailer\n')
    ..value(trailer)
    ..text('\nstartxref\n$xref\n%%EOF\n');
  return w.takeBytes();
}

Map<String, Object> _encryptDictionary(PdfR6Security s) => {
  'Filter': const PdfName('Standard'),
  'V': 5,
  'R': 6,
  'Length': 256,
  'P': s.permissions,
  'O': hexString(s.o),
  'U': hexString(s.u),
  'OE': hexString(s.oe),
  'UE': hexString(s.ue),
  'Perms': hexString(s.perms),
  'CF': {
    'StdCF': {
      'AuthEvent': const PdfName('DocOpen'),
      'CFM': const PdfName('AESV3'),
      'Length': 32,
    },
  },
  'StmF': const PdfName('StdCF'),
  'StrF': const PdfName('StdCF'),
};

/// `/Extensions << /ADBE << /BaseVersion /1.7 /ExtensionLevel 8 >> >>`:
/// how PDF 1.7 files declare AES-256 (R6) for pre-2.0 readers.
Map<String, Object> _withAdobeExtension(Map<String, Object> catalog) {
  final out = {...catalog};
  final existing = out['Extensions'];
  final adbe = {'BaseVersion': const PdfName('1.7'), 'ExtensionLevel': 8};
  if (existing is Map<String, Object>) {
    out['Extensions'] = {...existing, 'ADBE': adbe};
  } else if (existing == null) {
    out['Extensions'] = {'ADBE': adbe};
  }
  return out;
}

bool _usesCryptFilter(PdfFile file, Map<String, Object> dict) {
  final f = file.resolve(dict['Filter']);
  if (f is PdfName) return f.value == 'Crypt';
  if (f is List<Object>) {
    return f.any((x) => x is PdfName && x.value == 'Crypt');
  }
  return false;
}

/// `%PDF-x.y` as 10x+y (17 for 1.7); 14 when unreadable.
int _headerVersion(Uint8List bytes) {
  final head = latin1.decode(
    Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, 1024)),
  );
  final m = RegExp(r'%PDF-(\d)\.(\d)').firstMatch(head);
  if (m == null) return 14;
  return int.parse(m.group(1)!) * 10 + int.parse(m.group(2)!);
}

/// A hex string token for [bytes].
PdfRawString hexString(List<int> bytes) {
  const digits = '0123456789ABCDEF';
  final out = Uint8List(bytes.length * 2 + 2);
  out[0] = 0x3C;
  for (var i = 0; i < bytes.length; i++) {
    out[1 + i * 2] = digits.codeUnitAt(bytes[i] >> 4);
    out[2 + i * 2] = digits.codeUnitAt(bytes[i] & 0x0F);
  }
  out[out.length - 1] = 0x3E;
  return PdfRawString(out);
}

/// The bytes a literal `( … )` or hex `< … >` string token denotes
/// (ISO 32000-2 §7.3.4).
Uint8List decodePdfString(Uint8List token) {
  if (token.isEmpty) return Uint8List(0);
  final out = BytesBuilder(copy: false);
  if (token[0] == 0x3C) {
    int? high;
    for (var i = 1; i < token.length; i++) {
      final c = token[i];
      if (c == 0x3E) break;
      final int v;
      if (c >= 0x30 && c <= 0x39) {
        v = c - 0x30;
      } else if (c >= 0x41 && c <= 0x46) {
        v = c - 0x37;
      } else if (c >= 0x61 && c <= 0x66) {
        v = c - 0x57;
      } else {
        continue; // whitespace
      }
      if (high == null) {
        high = v;
      } else {
        out.addByte((high << 4) | v);
        high = null;
      }
    }
    if (high != null) out.addByte(high << 4);
    return out.takeBytes();
  }
  // Literal string: strip the outer parentheses.
  final end = token.length - 1;
  var i = 1;
  while (i < end) {
    final c = token[i];
    if (c == 0x5C && i + 1 < end) {
      final n = token[i + 1];
      i += 2;
      switch (n) {
        case 0x6E: // n
          out.addByte(0x0A);
        case 0x72: // r
          out.addByte(0x0D);
        case 0x74: // t
          out.addByte(0x09);
        case 0x62: // b
          out.addByte(0x08);
        case 0x66: // f
          out.addByte(0x0C);
        case 0x0D: // line continuation
          if (i < end && token[i] == 0x0A) i++;
        case 0x0A:
          break;
        case >= 0x30 && <= 0x37:
          var v = n - 0x30;
          for (var k = 0; k < 2 && i < end; k++) {
            final d = token[i];
            if (d < 0x30 || d > 0x37) break;
            v = v * 8 + (d - 0x30);
            i++;
          }
          out.addByte(v & 0xFF);
        default: // \( \) \\ and unknown escapes: the character itself
          out.addByte(n);
      }
      continue;
    }
    if (c == 0x0D) {
      // An unescaped EOL is read as a single line feed.
      out.addByte(0x0A);
      i++;
      if (i < end && token[i] == 0x0A) i++;
      continue;
    }
    out.addByte(c);
    i++;
  }
  return out.takeBytes();
}
