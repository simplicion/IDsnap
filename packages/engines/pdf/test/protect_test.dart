import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_pdf/src/protect/ae2_zip_writer.dart';
import 'package:engine_pdf/src/protect/crypto.dart';
import 'package:engine_pdf/src/protect/pdf_encryptor.dart';
import 'package:engine_pdf/src/protect/pdf_security.dart';
import 'package:engine_pdf/src/stamp/pdf_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' as rx;

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(180, 200, 220));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

/// 7-Zip, when installed (interoperability check with a real unzip tool).
String? _sevenZip() {
  for (final c in [
    r'C:\Program Files\7-Zip\7z.exe',
    '/usr/bin/7z',
    '/usr/local/bin/7z',
    '/opt/homebrew/bin/7z',
  ]) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

void main() {
  group('crypto known-answer tests', () {
    test('AES-256 block (FIPS-197 appendix C.3)', () {
      final key = unhex(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      final ct = aesEcbBlock(
        key,
        unhex('00112233445566778899aabbccddeeff'),
        encrypt: true,
      );
      expect(hex(ct), '8ea2b7ca516745bfeafc49904b496089');
    });

    test('HMAC-SHA1 (RFC 2202 cases 1 and 2)', () {
      expect(
        hex(hmacSha1(List.filled(20, 0x0b), utf8.encode('Hi There'))),
        'b617318655057264e28bc0b6fb378c8ef146be00',
      );
      expect(
        hex(
          hmacSha1(
            utf8.encode('Jefe'),
            utf8.encode('what do ya want for nothing?'),
          ),
        ),
        'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79',
      );
    });

    test('PBKDF2-HMAC-SHA1 (RFC 6070)', () {
      final pw = utf8.encode('password');
      final salt = utf8.encode('salt');
      expect(
        hex(pbkdf2HmacSha1(pw, salt, 1, 20)),
        '0c60c80f961f0e71f3a9b524af6012062fe037a6',
      );
      expect(
        hex(pbkdf2HmacSha1(pw, salt, 4096, 20)),
        '4b007901b765489abead49d926f721d065a429c1',
      );
      expect(
        hex(
          pbkdf2HmacSha1(
            utf8.encode('passwordPASSWORDpassword'),
            utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
            4096,
            25,
          ),
        ),
        '3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038',
      );
    });

    test('AE key derivation is PBKDF2-HMAC-SHA1 x1000 split 32/32/2', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final keys = deriveAe256Keys(ascii.encode('secret'), salt);
      final all = pbkdf2HmacSha1(ascii.encode('secret'), salt, 1000, 66);
      expect(keys.aesKey, all.sublist(0, 32));
      expect(keys.hmacKey, all.sublist(32, 64));
      expect(keys.verifier, all.sublist(64, 66));
    });

    test('WinZip CTR uses a little-endian counter starting at 1', () {
      final key = Uint8List(32);
      final data = Uint8List(48);
      WinZipAesCtr(key).process(data);
      Uint8List counter(int n) => Uint8List(16)..[0] = n;
      expect(data.sublist(0, 16), aesEcbBlock(key, counter(1), encrypt: true));
      expect(data.sublist(32), aesEcbBlock(key, counter(3), encrypt: true));
      // Split processing gives the same stream.
      final split = Uint8List(48);
      WinZipAesCtr(key)
        ..process(Uint8List.sublistView(split, 0, 5))
        ..process(Uint8List.sublistView(split, 5));
      expect(split, data);
    });

    test('AES-CBC with IV and PKCS#7 round-trips every length', () {
      final key = secureRandomBytes(32);
      for (final n in [0, 1, 15, 16, 17, 1000]) {
        final plain = secureRandomBytes(n);
        final enc = aesCbcEncryptWithIv(key, plain);
        expect(enc.length, 16 + (n ~/ 16 + 1) * 16);
        expect(aesCbcDecryptWithIv(key, enc), plain);
      }
    });
  });

  group('PDF R6 security handler', () {
    test('/P encodes the permission flags', () {
      final all = PdfPermissionBits.value(print: true, copy: true, edit: true);
      expect(all, -4); // 0xFFFFFFFC: everything allowed
      final none = PdfPermissionBits.value(
        print: false,
        copy: false,
        edit: false,
      );
      expect(none & PdfPermissionBits.print, 0);
      expect(none & PdfPermissionBits.copy, 0);
      expect(none & PdfPermissionBits.modify, 0);
      expect(none & PdfPermissionBits.accessibility, isNonZero);
      expect(none & 0xC0, 0xC0); // reserved bits 7-8
      expect(none, isNegative); // bits 13-32 set
    });

    test('user and owner passwords authenticate to the same file key', () {
      final s = PdfR6Security.create(
        userPassword: 'open-me',
        ownerPassword: 'owner-pw',
        permissions: -4,
      );
      expect(s.o.length, 48);
      expect(s.u.length, 48);
      expect(s.oe.length, 32);
      expect(s.ue.length, 32);
      expect(s.perms.length, 16);
      ({Uint8List fileKey, PdfPasswordKind kind})? auth(String pw) =>
          authenticateR6(
            password: pw,
            o: s.o,
            u: s.u,
            oe: s.oe,
            ue: s.ue,
            perms: s.perms,
            permissions: s.permissions,
          );
      expect(auth('open-me')!.fileKey, s.fileKey);
      expect(auth('open-me')!.kind, PdfPasswordKind.user);
      expect(auth('owner-pw')!.fileKey, s.fileKey);
      expect(auth('owner-pw')!.kind, PdfPasswordKind.owner);
      expect(auth('Open-me'), isNull);
      expect(auth(''), isNull);
    });

    test('hash is deterministic for fixed salts (regression vector)', () {
      final a = r6Hash(
        r6PasswordBytes('test'),
        unhex('0001020304050607'),
        const [],
      );
      final b = r6Hash(
        r6PasswordBytes('test'),
        unhex('0001020304050607'),
        const [],
      );
      expect(a, b);
      expect(a.length, 32);
      expect(
        a,
        isNot(sha256([...utf8.encode('test'), 0, 1, 2, 3, 4, 5, 6, 7])),
      );
    });

    test('decodes literal and hex strings', () {
      Uint8List d(String s) =>
          decodePdfString(Uint8List.fromList(latin1.encode(s)));
      expect(latin1.decode(d(r'(a\(b\)c\\d)')), r'a(b)c\d');
      expect(d(r'(\101\12\0)'), [0x41, 0x0A, 0x00]);
      expect(latin1.decode(d('(line\\\ncont)')), 'linecont');
      expect(latin1.decode(d(r'(tab\there)')), 'tab\there');
      expect(d('<48 65 6C6C 6F>'), ascii.encode('Hello'));
      expect(d('<ABC>'), [0xAB, 0xC0]);
    });
  });

  group('PDF encryption with PDFium verification', () {
    final engine = PdfEngineImpl();
    late Directory dir;
    var ready = false;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('protect_test');
      try {
        await rx.pdfrxInitialize();
        ready = true;
      } on Object catch (e) {
        // Test diagnostics only.
        // ignore: avoid_print
        print('PDFium unavailable: $e');
      }
    });

    tearDownAll(() => dir.delete(recursive: true));

    Future<String> source(String name, int pages) async {
      final bytes = (await engine.fromImages(
        [for (var i = 0; i < pages; i++) _jpeg(300 + i * 10, 400)],
        const PdfBuildOptions(),
        textLayers: [
          for (var i = 0; i < pages; i++)
            OcrResult(
              script: OcrScript.latin,
              blocks: [
                OcrBlock([
                  OcrLine('Secret marker $i', const NRect(0.1, 0.1, 0.6, 0.05)),
                ]),
              ],
            ),
        ],
      )).valueOrNull!;
      final f = File('${dir.path}/$name.pdf');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    Future<rx.PdfDocument> openWith(String path, String? password) =>
        rx.PdfDocument.openFile(
          path,
          // One attempt only: the provider is called until it returns null.
          passwordProvider: rx.createSimplePasswordProvider(password),
          firstAttemptByEmptyPassword: password == null,
        );

    test(
      'protects a PDF with AES-256 (R6); opens only with the password',
      () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        final input = await source('plain', 3);
        final out = '${dir.path}/out/protected.pdf';
        final r = await engine.protectPdf(
          input,
          const PdfProtection(openPassword: 'Tr0ub4dor&3'),
          outputPath: out,
        );
        expect(r.failureOrNull, isNull);
        expect(r.valueOrNull!.pageCount, 3);
        expect(r.valueOrNull!.sizeBytes, File(out).lengthSync());

        final bytes = File(out).readAsBytesSync();
        final text = latin1.decode(bytes);
        expect(text, contains('/Filter /Standard'));
        expect(text, contains('/R 6'));
        expect(text, contains('/V 5'));
        expect(text, contains('/CFM /AESV3'));
        expect(text, contains('/ExtensionLevel 8'));
        expect(text, isNot(contains('Secret marker')));

        // Without a password: the typed failure.
        expect(
          (await engine.pageCount(out)).failureOrNull?.code,
          FailureCode.passwordProtected,
        );
        expect((await engine.needsPassword(out)).valueOrNull, isTrue);
        expect((await engine.needsPassword(input)).valueOrNull, isFalse);

        // Wrong password: rejected by PDFium.
        await expectLater(
          openWith(out, 'wrong'),
          throwsA(isA<rx.PdfPasswordException>()),
        );

        // Right password: same pages, text extractable, R6 reported.
        final doc = await openWith(out, 'Tr0ub4dor&3');
        try {
          expect(doc.isEncrypted, isTrue);
          expect(doc.pages.length, 3);
          expect(doc.permissions?.securityHandlerRevision, 6);
          // Unsigned 0xFFFFFFFC: every permission granted.
          expect(doc.permissions?.permissions.toSigned(32), -4);
          final t = await doc.pages[2].loadText();
          expect(t?.fullText, contains('Secret marker 2'));
        } finally {
          await doc.dispose();
        }
      },
    );

    test('owner password restricts printing, copying and editing', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      final input = await source('perm', 1);
      final out = '${dir.path}/perm-protected.pdf';
      final r = await engine.protectPdf(
        input,
        const PdfProtection(
          openPassword: 'user-pass',
          ownerPassword: 'owner-pass',
          allowPrinting: false,
          allowCopying: false,
          allowEditing: false,
        ),
        outputPath: out,
      );
      expect(r.isOk, isTrue);
      final doc = await openWith(out, 'user-pass');
      try {
        final p = doc.permissions!.permissions.toSigned(32);
        expect(p & PdfPermissionBits.print, 0);
        expect(p & PdfPermissionBits.printHighQuality, 0);
        expect(p & PdfPermissionBits.copy, 0);
        expect(p & PdfPermissionBits.modify, 0);
        expect(p & PdfPermissionBits.annotate, 0);
      } finally {
        await doc.dispose();
      }
      // The owner password also opens it.
      final owner = await openWith(out, 'owner-pass');
      expect(owner.pages.length, 1);
      await owner.dispose();
    });

    test('pure-Dart decryption restores every object byte-for-byte', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      final input = File(await source('dart-rt', 2)).readAsBytesSync();
      final s = PdfR6Security.create(
        userPassword: 'pw',
        ownerPassword: 'owner',
        permissions: -4,
      );
      final encrypted = encryptPdfR6(input, s);
      expect(
        () => decryptPdfR6(encrypted, 'nope'),
        throwsA(isA<PdfWrongPasswordException>()),
      );
      final decrypted = decryptPdfR6(encrypted, 'pw');

      // Compare decoded page content streams of the original and the
      // decrypted rewrite.
      final a = PdfFile(input);
      final b = PdfFile(decrypted);
      final pa = a.pages();
      final pb = b.pages();
      expect(pb.length, pa.length);
      for (var i = 0; i < pa.length; i++) {
        final ca = a.resolve(pa[i].dict['Contents']);
        final cb = b.resolve(pb[i].dict['Contents']);
        expect(
          a.decodeStream(ca as PdfStreamObject),
          b.decodeStream(cb as PdfStreamObject),
        );
      }
      expect(b.trailer.containsKey('Encrypt'), isFalse);
    });

    test('removes a password (and rejects a wrong one)', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      final input = await source('to-unlock', 2);
      final locked = '${dir.path}/locked.pdf';
      await engine.protectPdf(
        input,
        const PdfProtection(openPassword: 'let me in'),
        outputPath: locked,
      );
      final wrong = await engine.removePdfPassword(
        locked,
        'let me out',
        outputPath: '${dir.path}/x.pdf',
      );
      expect(wrong.failureOrNull?.code, FailureCode.wrongPassword);

      final out = '${dir.path}/unlocked.pdf';
      final r = await engine.removePdfPassword(
        locked,
        'let me in',
        outputPath: out,
      );
      expect(r.failureOrNull, isNull);
      expect(r.valueOrNull!.pageCount, 2);
      expect((await engine.pageCount(out)).valueOrNull, 2);
      final text = (await engine.extractText(out)).valueOrNull!;
      expect(text[1], contains('Secret marker 1'));

      final notLocked = await engine.removePdfPassword(
        input,
        'anything',
        outputPath: '${dir.path}/y.pdf',
      );
      expect(notLocked.failureOrNull?.code, FailureCode.conversionFailed);
      expect(notLocked.failureOrNull?.detail, 'Not protected');
    });

    test(
      're-protects an already protected PDF with its current password',
      () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        final input = await source('twice', 1);
        final first = '${dir.path}/first.pdf';
        await engine.protectPdf(
          input,
          const PdfProtection(openPassword: 'old'),
          outputPath: first,
        );
        final missing = await engine.protectPdf(
          first,
          const PdfProtection(openPassword: 'new'),
          outputPath: '${dir.path}/z.pdf',
        );
        expect(missing.failureOrNull?.code, FailureCode.passwordProtected);
        final second = '${dir.path}/second.pdf';
        final r = await engine.protectPdf(
          first,
          const PdfProtection(openPassword: 'new'),
          outputPath: second,
          currentPassword: 'old',
        );
        expect(r.isOk, isTrue);
        final doc = await openWith(second, 'new');
        expect(doc.pages.length, 1);
        await doc.dispose();
      },
    );

    test('encrypts PDFium output with object and xref streams', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      // A merge goes through PDFium's writer.
      final merged = (await engine.merge([
        await source('m1', 1),
        await source('m2', 2),
      ])).valueOrNull!;
      final path = '${dir.path}/merged.pdf';
      await File(path).writeAsBytes(merged);
      final out = '${dir.path}/merged-protected.pdf';
      final r = await engine.protectPdf(
        path,
        const PdfProtection(openPassword: 'm'),
        outputPath: out,
      );
      expect(r.valueOrNull?.pageCount, 3);
    });

    // Fixtures written by qpdf 12.4 (via pikepdf) from a two-page text PDF:
    // other producers and older security handlers.
    const fixtures = 'test/fixtures/encrypted';

    test('pure-Dart R6 authentication matches qpdf (independent writer)', () {
      final bytes = File('$fixtures/qpdf-r6-objstm.pdf').readAsBytesSync();
      expect(
        () => decryptPdfR6(bytes, 'bad'),
        throwsA(isA<PdfWrongPasswordException>()),
      );
      for (final pw in ['u6', 'o6']) {
        final plain = decryptPdfR6(bytes, pw);
        final file = PdfFile(plain);
        expect(file.trailer.containsKey('Encrypt'), isFalse);
        expect(file.pages(), hasLength(2));
        final content = file.resolve(file.pages().first.dict['Contents']);
        expect(
          latin1.decode(file.decodeStream(content as PdfStreamObject)),
          contains('Hello'),
        );
      }
    });

    test('removes passwords written by other tools (R3 RC4, R4 AES-128, '
        'R6 with object streams)', () async {
      if (!ready) return markTestSkipped('PDFium unavailable');
      for (final (name, pw) in [
        ('r3-rc4', 'u3'),
        ('r4-aes128', 'o4'),
        ('qpdf-r6-objstm', 'u6'),
      ]) {
        final out = '${dir.path}/$name-open.pdf';
        final r = await engine.removePdfPassword(
          '$fixtures/$name.pdf',
          pw,
          outputPath: out,
        );
        expect(r.failureOrNull, isNull, reason: name);
        expect((await engine.pageCount(out)).valueOrNull, 2, reason: name);
        final text = (await engine.extractText(out)).valueOrNull!;
        expect(text.first, contains('Hello'), reason: name);
        final wrong = await engine.removePdfPassword(
          '$fixtures/$name.pdf',
          'nope',
          outputPath: '${dir.path}/$name-x.pdf',
        );
        expect(wrong.failureOrNull?.code, FailureCode.wrongPassword);
      }
    });

    test(
      'owner-only PDFs open without a password; restrictions removable',
      () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        const path = '$fixtures/owner-only-r6.pdf';
        expect((await engine.needsPassword(path)).valueOrNull, isFalse);
        final r = await engine.removePdfPassword(
          path,
          'o6',
          outputPath: '${dir.path}/owner-only-open.pdf',
        );
        expect(r.failureOrNull, isNull);
      },
    );

    test(
      'upgrades an AES-128 PDF to AES-256 with its current password',
      () async {
        if (!ready) return markTestSkipped('PDFium unavailable');
        final out = '${dir.path}/upgraded.pdf';
        final r = await engine.protectPdf(
          '$fixtures/r4-aes128.pdf',
          const PdfProtection(openPassword: 'fresh'),
          outputPath: out,
          currentPassword: 'u4',
        );
        expect(r.valueOrNull?.pageCount, 2);
        final doc = await openWith(out, 'fresh');
        expect(doc.permissions?.securityHandlerRevision, 6);
        await doc.dispose();
      },
    );

    test('rejects an empty or too-long password and a missing file', () async {
      final input = '${dir.path}/none.pdf';
      final r = await engine.protectPdf(
        input,
        const PdfProtection(openPassword: ''),
        outputPath: '${dir.path}/o.pdf',
      );
      expect(r.failureOrNull?.detail, 'Password');
      expect(validatePdfPassword('x' * 128), isNotNull);
      expect(validatePdfPassword('x' * 127), isNull);
      final missing = await engine.protectPdf(
        input,
        const PdfProtection(openPassword: 'fine'),
        outputPath: '${dir.path}/o.pdf',
      );
      expect(missing.failureOrNull?.code, FailureCode.notFound);
    });
  });

  group('AES-256 ZIP (WinZip AE-2)', () {
    final engine = PdfEngineImpl();
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('zip_protect_test');
    });

    tearDownAll(() => dir.delete(recursive: true));

    Future<String> write(String name, List<int> bytes) async {
      final f = File('${dir.path}/in/$name');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      return f.path;
    }

    test('round-trips several files through an independent reader', () async {
      final text = utf8.encode('Tax form line 1\n' * 500);
      final jpeg = _jpeg(64, 64);
      final random = secureRandomBytes(70000);
      final sources = [
        ZipSource(path: await write('form.txt', text), fileName: 'form.txt'),
        ZipSource(path: await write('id.jpg', jpeg), fileName: 'ID card.jpg'),
        ZipSource(path: await write('blob.bin', random), fileName: 'blob.bin'),
        ZipSource(path: await write('empty.txt', []), fileName: 'empty.txt'),
        // Same name twice → de-duplicated.
        ZipSource(path: await write('form2.txt', text), fileName: 'form.txt'),
      ];
      final out = '${dir.path}/out/bundle.zip';
      final progress = <double>[];
      final r = await engine.writeProtectedZip(
        sources,
        'c0rrect-Horse',
        outputPath: out,
        onProgress: progress.add,
      );
      expect(r.failureOrNull, isNull);
      expect(r.valueOrNull!.format, DocumentFormat.zip);
      final bytes = File(out).readAsBytesSync();
      expect(r.valueOrNull!.sizeBytes, bytes.length);
      expect(DocumentFormat.sniff(bytes.sublist(0, 8)), DocumentFormat.zip);
      // No plaintext leaks.
      expect(latin1.decode(bytes).contains('Tax form line'), isFalse);

      final archive = ar.ZipDecoder().decodeBytes(
        bytes,
        password: 'c0rrect-Horse',
      );
      final byName = {for (final f in archive.files) f.name: f.readBytes()};
      expect(byName.keys, [
        'form.txt',
        'ID card.jpg',
        'blob.bin',
        'empty.txt',
        'form (2).txt',
      ]);
      expect(byName['form.txt'], text);
      expect(byName['form (2).txt'], text);
      expect(byName['ID card.jpg'], jpeg);
      expect(byName['blob.bin'], random);
      expect(byName['empty.txt'] ?? Uint8List(0), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(progress, isNotEmpty);

      expect(
        () => ar.ZipDecoder()
            .decodeBytes(bytes, password: 'wrong')
            .files
            .first
            .readBytes(),
        throwsA(anything),
      );
    });

    test('writes the AE-2 headers (method 99, 0x9901, CRC 0)', () async {
      final out = '${dir.path}/hdr.zip';
      await engine.writeProtectedZip(
        [
          ZipSource(
            path: await write('a.txt', utf8.encode('hello')),
            fileName: 'a.txt',
          ),
        ],
        'pw',
        outputPath: out,
      );
      final b = File(out).readAsBytesSync();
      int u16(int o) => b[o] | b[o + 1] << 8;
      int u32(int o) => u16(o) | u16(o + 2) << 16;
      expect(u32(0), 0x04034b50);
      expect(u16(4), 51); // version needed
      expect(u16(6) & 1, 1); // encrypted
      expect(u16(8), 99); // AES
      expect(u32(14), 0); // CRC 0 (AE-2)
      final nameLen = u16(26);
      final extra = 30 + nameLen;
      expect(u16(extra), 0x9901);
      expect(u16(extra + 2), 7);
      expect(u16(extra + 4), 2); // AE-2
      expect(String.fromCharCodes(b.sublist(extra + 6, extra + 8)), 'AE');
      expect(b[extra + 8], 3); // AES-256
      expect(u16(extra + 9), 8); // deflated inside
      // salt (16) + verifier (2) + data + MAC (10), patched after writing.
      expect(u32(18), greaterThan(28));
      expect(u32(22), 5); // uncompressed size
    });

    test('rejects non-ASCII passwords and empty input', () async {
      final r = await engine.writeProtectedZip(
        [
          ZipSource(path: await write('b.txt', [1]), fileName: 'b.txt'),
        ],
        'pässword',
        outputPath: '${dir.path}/x.zip',
      );
      expect(r.failureOrNull?.detail, 'Password');
      final none = await engine.writeProtectedZip(
        const [],
        'pw',
        outputPath: '${dir.path}/y.zip',
      );
      expect(none.isOk, isFalse);
      final missing = await engine.writeProtectedZip(
        [ZipSource(path: '${dir.path}/nope', fileName: 'nope')],
        'pw',
        outputPath: '${dir.path}/z.zip',
      );
      expect(missing.failureOrNull?.code, FailureCode.notFound);
    });

    test('7-Zip verifies the archive and the HMAC (when installed)', () async {
      final sevenZip = _sevenZip();
      if (sevenZip == null) return markTestSkipped('7-Zip not installed');
      final data = secureRandomBytes(300000);
      final out = '${dir.path}/seven.zip';
      await engine.writeProtectedZip(
        [
          ZipSource(path: await write('r.bin', data), fileName: 'r.bin'),
          ZipSource(
            path: await write('t.txt', utf8.encode('abc ' * 10000)),
            fileName: 'notes.txt',
          ),
        ],
        'Seven-Zip-Test!',
        outputPath: out,
      );
      final ok = await Process.run(sevenZip, ['t', '-pSeven-Zip-Test!', out]);
      expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
      expect('${ok.stdout}', contains('Everything is Ok'));
      final info = await Process.run(sevenZip, ['l', '-slt', out]);
      expect('${info.stdout}', contains('AES-256'));
      final bad = await Process.run(sevenZip, ['t', '-pwrong', out]);
      expect(bad.exitCode, isNot(0));
      final extract = Directory('${dir.path}/x7');
      final x = await Process.run(sevenZip, [
        'x',
        '-pSeven-Zip-Test!',
        '-o${extract.path}',
        out,
      ]);
      expect(x.exitCode, 0);
      expect(File('${extract.path}/r.bin').readAsBytesSync(), data);
    });
  });
}
