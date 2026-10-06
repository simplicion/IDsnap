import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_pdf/src/protect/crypto.dart';
import 'package:engine_pdf/zip.dart';
import 'package:flutter_test/flutter_test.dart';

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

Matcher _kind(ArchiveErrorKind kind) =>
    isA<ArchiveException>().having((e) => e.kind, 'kind', kind);

void main() {
  const codec = ZipArchiveCodec();
  late Directory dir;
  late String text;
  late Uint8List random;
  late String textPath;
  late String randomPath;
  late String emptyPath;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zip_codec_test');
    text = 'Passport line 1 — éü 名前\n' * 3000;
    random = secureRandomBytes(1500000); // > 1 chunk
    textPath = '${dir.path}/in/notes.txt';
    randomPath = '${dir.path}/in/scan.jpg';
    emptyPath = '${dir.path}/in/empty.txt';
    await Directory('${dir.path}/in').create(recursive: true);
    await File(textPath).writeAsString(text);
    await File(randomPath).writeAsBytes(random);
    await File(emptyPath).writeAsBytes(const []);
  });

  tearDownAll(() => dir.delete(recursive: true));

  Future<String> build(String name, {String? password}) async {
    final out = '${dir.path}/$name';
    final w = await codec.createWriter(out, password: password);
    final seen = <int>[];
    await w.addDirectory('IDs & Proofs/');
    await w.addDirectory('IDs & Proofs/Empty/');
    await w.addFile(textPath, 'IDs & Proofs/Notes ü.txt', onBytes: seen.add);
    await w.addFile(randomPath, 'Photo.jpg');
    await w.addFile(emptyPath, 'empty.txt');
    await w.addBytes(utf8.encode('{"version":3}'), 'manifest.json');
    final size = await w.close();
    expect(size, File(out).lengthSync());
    expect(seen, isNotEmpty);
    return out;
  }

  Future<void> expectContents(ArchiveReader r, {String? password}) async {
    expect(r.entries.map((e) => e.name), [
      'IDs & Proofs/',
      'IDs & Proofs/Empty/',
      'IDs & Proofs/Notes ü.txt',
      'Photo.jpg',
      'empty.txt',
      'manifest.json',
    ]);
    final t = '${dir.path}/x/${DateTime.now().microsecondsSinceEpoch}';
    await r.extract('IDs & Proofs/Notes ü.txt', t, password: password);
    expect(await File(t).readAsString(), text);
    await r.extract('Photo.jpg', '$t.jpg', password: password);
    expect(await File('$t.jpg').readAsBytes(), random);
    await r.extract('empty.txt', '$t.e', password: password);
    expect(File('$t.e').lengthSync(), 0);
    expect(
      utf8.decode(await r.readBytes('manifest.json', password: password)),
      '{"version":3}',
    );
  }

  test(
    'plain archive round-trips and opens in an independent reader',
    () async {
      final out = await build('plain.zip');
      final r = await codec.openReader(out);
      expect(r.hasEncryptedEntries, isFalse);
      await expectContents(r);
      await r.close();

      final a = ar.ZipDecoder().decodeBytes(File(out).readAsBytesSync());
      final byName = {for (final f in a.files) f.name: f};
      expect(
        utf8.decode(byName['IDs & Proofs/Notes ü.txt']!.readBytes()!),
        text,
      );
      expect(byName['Photo.jpg']!.readBytes(), random);
      // Text is deflated, the JPEG stored.
      expect(
        r.entry('IDs & Proofs/Notes ü.txt')!.compressedSize,
        lessThan(utf8.encode(text).length),
      );
      expect(r.entry('Photo.jpg')!.compressedSize, random.length);
    },
  );

  test(
    'AES-256 archive round-trips; password is required and checked',
    () async {
      final out = await build('aes.zip', password: 'Backup-Pass-1');
      final bytes = File(out).readAsBytesSync();
      expect(latin1.decode(bytes).contains('Passport line'), isFalse);
      final r = await codec.openReader(out);
      expect(r.hasEncryptedEntries, isTrue);
      expect(r.entry('IDs & Proofs/')!.encrypted, isFalse);
      expect(r.entry('Photo.jpg')!.encrypted, isTrue);
      await expectContents(r, password: 'Backup-Pass-1');
      await expectLater(
        r.readBytes('manifest.json'),
        throwsA(_kind(ArchiveErrorKind.passwordRequired)),
      );
      await expectLater(
        r.readBytes('manifest.json', password: 'wrong'),
        throwsA(_kind(ArchiveErrorKind.wrongPassword)),
      );
      final target = '${dir.path}/wrong/out.txt';
      await expectLater(
        r.extract('Photo.jpg', target, password: 'nope'),
        throwsA(_kind(ArchiveErrorKind.wrongPassword)),
      );
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
      await r.close();

      // Independent AE-2 reader.
      final a = ar.ZipDecoder().decodeBytes(bytes, password: 'Backup-Pass-1');
      final photo = a.files.firstWhere((f) => f.name == 'Photo.jpg');
      expect(photo.readBytes(), random);
    },
  );

  test('rejects non-ASCII passwords up front', () async {
    await expectLater(
      codec.createWriter('${dir.path}/n.zip', password: 'pässword'),
      throwsA(_kind(ArchiveErrorKind.unsupported)),
    );
    expect(File('${dir.path}/n.zip').existsSync(), isFalse);
  });

  test('detects tampering and truncation', () async {
    final out = await build('tamper.zip', password: 'pw-tamper');
    final bytes = File(out).readAsBytesSync();
    final r0 = await codec.openReader(out);
    final photoOffset = _localDataOffset(bytes, 'Photo.jpg');
    await r0.close();
    final tampered = Uint8List.fromList(bytes);
    tampered[photoOffset + 18 + 1000] ^= 0x01; // inside the ciphertext
    final tp = '${dir.path}/tampered.zip';
    File(tp).writeAsBytesSync(tampered);
    final r = await codec.openReader(tp);
    await expectLater(
      r.extract('Photo.jpg', '${dir.path}/t.jpg', password: 'pw-tamper'),
      throwsA(_kind(ArchiveErrorKind.corrupt)),
    );
    expect(File('${dir.path}/t.jpg').existsSync(), isFalse);
    await r.close();

    final cut = '${dir.path}/cut.zip';
    File(cut).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    await expectLater(
      codec.openReader(cut),
      throwsA(_kind(ArchiveErrorKind.corrupt)),
    );
    final notZip = '${dir.path}/not.zip';
    File(notZip).writeAsStringSync('hello, not a zip at all');
    await expectLater(
      codec.openReader(notZip),
      throwsA(_kind(ArchiveErrorKind.corrupt)),
    );
  });

  test('plain CRC mismatch is reported as corrupt', () async {
    final out = await build('crc.zip');
    final bytes = Uint8List.fromList(File(out).readAsBytesSync());
    final off = _localDataOffset(bytes, 'Photo.jpg'); // stored: raw bytes
    bytes[off + 10] ^= 0xFF;
    final p = '${dir.path}/crc-bad.zip';
    File(p).writeAsBytesSync(bytes);
    final r = await codec.openReader(p);
    await expectLater(
      r.extract('Photo.jpg', '${dir.path}/crc.jpg'),
      throwsA(_kind(ArchiveErrorKind.corrupt)),
    );
    await r.close();
  });

  test('reads ZIPs written by other tools (older IDSnap backups)', () async {
    final a = ar.Archive()
      ..addFile(ar.ArchiveFile.string('manifest.json', '{"version":2}'))
      ..addFile(ar.ArchiveFile.bytes('Work/scan.jpg', random))
      ..addFile(ar.ArchiveFile.string('Work/notes.txt', text));
    final p = '${dir.path}/legacy.zip';
    File(p).writeAsBytesSync(ar.ZipEncoder().encodeBytes(a));
    final r = await codec.openReader(p);
    expect(await r.readBytes('Work/scan.jpg'), random);
    expect(utf8.decode(await r.readBytes('Work/notes.txt')), text);
    await r.close();
  });

  test(
    'abort deletes the partial archive; cancel leaves no part file',
    () async {
      final big = '${dir.path}/in/big.bin';
      final sink = File(big).openSync(mode: FileMode.write);
      for (var i = 0; i < 24; i++) {
        sink.writeFromSync(secureRandomBytes(1 << 20));
      }
      sink.closeSync();

      final out = '${dir.path}/aborted.zip';
      final w = await codec.createWriter(out, password: 'abort-me');
      final pending = expectLater(
        w.addFile(big, 'big.bin', onBytes: (_) {}),
        throwsA(_kind(ArchiveErrorKind.cancelled)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await w.abort();
      await pending;
      expect(File(out).existsSync(), isFalse);

      // Extraction cancelled midway.
      final full = '${dir.path}/full.zip';
      final w2 = await codec.createWriter(full);
      await w2.addFile(big, 'big.bin');
      await w2.close();
      final r = await codec.openReader(full);
      final token = JobCancelToken();
      final target = '${dir.path}/xbig/big.bin';
      final job = r.extract(
        'big.bin',
        target,
        cancel: token,
        onBytes: (n) {
          if (n > 2 << 20) token.cancel();
        },
      );
      await expectLater(job, throwsA(_kind(ArchiveErrorKind.cancelled)));
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
      await r.close();
    },
  );

  test('7-Zip opens plain and AES-256 archives (when installed)', () async {
    final seven = _sevenZip();
    if (seven == null) return markTestSkipped('7-Zip not installed');
    final aes = await build('seven-aes.zip', password: 'Seven-Zip-Test!');
    final ok = await Process.run(seven, ['t', '-pSeven-Zip-Test!', aes]);
    expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
    expect('${ok.stdout}', contains('Everything is Ok'));
    final info = await Process.run(seven, ['l', '-slt', aes]);
    expect('${info.stdout}', contains('AES-256'));
    final bad = await Process.run(seven, ['t', '-pwrong', aes]);
    expect(bad.exitCode, isNot(0));
    final plain = await build('seven-plain.zip');
    final p = await Process.run(seven, ['t', plain]);
    expect(p.exitCode, 0, reason: '${p.stdout}${p.stderr}');
    final x = Directory('${dir.path}/x7');
    final ex = await Process.run(seven, [
      'x',
      '-pSeven-Zip-Test!',
      '-o${x.path}',
      aes,
    ]);
    expect(ex.exitCode, 0);
    expect(File('${x.path}/IDs & Proofs/Notes ü.txt').readAsStringSync(), text);
    expect(Directory('${x.path}/IDs & Proofs/Empty').existsSync(), isTrue);

    // And our reader opens what 7-Zip writes (AES-256 ZIP).
    final made = '${dir.path}/by7z.zip';
    final mk = await Process.run(seven, [
      'a',
      '-tzip',
      '-mem=AES256',
      '-pFrom-7z',
      made,
      textPath,
    ]);
    expect(mk.exitCode, 0, reason: '${mk.stdout}${mk.stderr}');
    final r = await codec.openReader(made);
    expect(
      utf8.decode(await r.readBytes('notes.txt', password: 'From-7z')),
      text,
    );
    await r.close();
  });
}

/// Offset of an entry's data (after its local header) found by scanning.
int _localDataOffset(Uint8List b, String name) {
  final want = utf8.encode(name);
  for (var i = 0; i + 30 < b.length; i++) {
    if (b[i] != 0x50 || b[i + 1] != 0x4b || b[i + 2] != 3 || b[i + 3] != 4) {
      continue;
    }
    final n = b[i + 26] | b[i + 27] << 8;
    final x = b[i + 28] | b[i + 29] << 8;
    final got = b.sublist(i + 30, i + 30 + n);
    if (got.length == want.length &&
        Iterable<int>.generate(n).every((k) => got[k] == want[k])) {
      return i + 30 + n + x;
    }
  }
  throw StateError('entry not found');
}
