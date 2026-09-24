import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentFormat.sniff', () {
    test('detects by magic bytes, ignoring a lying extension', () {
      final pdf = Uint8List.fromList('%PDF-1.7'.codeUnits);
      expect(
        DocumentFormat.sniff(pdf, nameHint: 'photo.jpg'),
        DocumentFormat.pdf,
      );
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]);
      expect(DocumentFormat.sniff(jpg), DocumentFormat.jpeg);
    });

    test('uses hint for OOXML containers and text', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2]);
      expect(
        DocumentFormat.sniff(zip, nameHint: 'a.docx'),
        DocumentFormat.docx,
      );
      expect(DocumentFormat.sniff(zip, nameHint: 'a.bin'), DocumentFormat.zip);
      final txt = Uint8List.fromList('hello,world\n1,2'.codeUnits);
      expect(DocumentFormat.sniff(txt, nameHint: 'a.csv'), DocumentFormat.csv);
    });

    test('binary garbage is unknown', () {
      final bin = Uint8List.fromList([0, 1, 2, 3, 0, 0]);
      expect(
        DocumentFormat.sniff(bin, nameHint: 'x.txt'),
        DocumentFormat.unknown,
      );
    });
  });

  group('RedactedLogger', () {
    test('redacts paths and long strings', () {
      final lines = <String>[];
      RedactedLogger('t', sink: lines.add).info('saved', {
        'pages': 3,
        'path': '/data/user/secret.pdf',
        'text': 'x' * 100,
        'ok': 'short',
      });
      expect(lines.single, contains('pages: 3'));
      expect(lines.single, isNot(contains('secret')));
      expect(lines.single, contains('ok: short'));
    });
  });

  group('Result', () {
    test('guard captures thrown errors as typed failures', () async {
      final r = await guard<int>(
        () async => throw StateError('boom'),
        code: FailureCode.corruptFile,
      );
      expect(r.failureOrNull?.code, FailureCode.corruptFile);
      expect(r.failureOrNull.toString(), isNot(contains('boom')));
    });

    test('map and fold', () {
      const Result<int> r = Ok(2);
      expect(r.map((v) => v * 2).valueOrNull, 4);
      expect(r.fold((v) => 'ok$v', (f) => 'err'), 'ok2');
    });
  });
}
