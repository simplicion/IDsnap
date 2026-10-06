import 'dart:convert';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:test/test.dart';

void main() {
  const rfc = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // "12345678901234567890"

  group('decode', () {
    test('RFC 4648 test vectors round-trip', () {
      // §10 vectors (short ones are below the secret minimum, so check the
      // encoder for them and the decoder for a long one).
      const vectors = {
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };
      vectors.forEach((plain, encoded) {
        expect(Base32.encode(utf8.encode(plain)), encoded);
      });
      final long = utf8.encode('foobarfoobarfoobar');
      expect(Base32.decode(Base32.encode(long)).valueOrNull, long);
    });

    test('decodes the RFC 4226 secret', () {
      expect(
        utf8.decode(Base32.decode(rfc).valueOrNull!),
        '12345678901234567890',
      );
    });

    test('tolerates spaces, dashes, lowercase and padding', () {
      final expected = Base32.decode(rfc).valueOrNull;
      for (final input in [
        'gezdgnbvgy3tqojqgezdgnbvgy3tqojq',
        'GEZD GNBV GY3T QOJQ GEZD GNBV GY3T QOJQ',
        '  gezd-gnbv-gy3t-qojq\ngezd\tgnbv gy3t qojq  ',
        '$rfc====',
      ]) {
        expect(Base32.decode(input).valueOrNull, expected, reason: input);
      }
      // Missing padding: 26 chars = 16 bytes (would be padded to 32).
      expect(
        Base32.decode('JBSWY3DPEHPK3PXPJBSWY3DPEE').valueOrNull?.length,
        16,
      );
      expect(Base32.decode('JBSWY3DPEHPK3PXPJBSWY3DPEE======').isOk, isTrue);
    });

    Matcher failsWith(String detail) => isA<Err<Object?>>().having(
      (e) => (e.failure.code, e.failure.detail),
      'failure',
      (FailureCode.invalidSecretKey, detail),
    );

    test('rejects invalid characters', () {
      for (final bad in ['GEZDGNBVGY3TQOJ0', 'GEZDGNBVGY3TQOJ1', 'GEZD!NBV']) {
        expect(Base32.decode(bad), failsWith(Base32.badCharacter), reason: bad);
      }
      expect(
        Base32.decode('GEZD==GNBVGY3TQOJQ'),
        failsWith(Base32.badCharacter),
      );
    });

    test('rejects impossible lengths', () {
      // 8n + 1, 3 or 6 characters can't come from whole bytes.
      for (final bad in ['GEZDGNBVGY3TQOJQG', 'GEZDGNBVGY3TQOJQGEZ']) {
        expect(Base32.decode(bad), failsWith(Base32.badLength), reason: bad);
      }
    });

    test('rejects empty, too short and too long secrets', () {
      expect(Base32.decode('  '), failsWith(Base32.empty));
      expect(Base32.decode('MZXW6YTBOI'), failsWith(Base32.tooShort));
      expect(
        Base32.decode('A' * 480), // 300 bytes
        failsWith(Base32.tooLong),
      );
    });
  });

  test('normalize returns the canonical key', () {
    expect(
      Base32.normalize('gezd gnbv gy3t qojq====').valueOrNull,
      'GEZDGNBVGY3TQOJQ',
    );
    expect(Base32.normalize('nope!').isOk, isFalse);
  });
}
