import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:test/test.dart';

DateTime _unix(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  // RFC 4226 Appendix D: secret = ASCII "12345678901234567890".
  final rfcSecret = utf8.encode('12345678901234567890');

  group('HOTP (RFC 4226 Appendix D)', () {
    const expected = [
      '755224',
      '287082',
      '359152',
      '969429',
      '338314',
      '254676',
      '287922',
      '162583',
      '399871',
      '520489',
    ];
    for (var count = 0; count < expected.length; count++) {
      test('count $count', () {
        expect(Otp.hotp(rfcSecret, counter: count), expected[count]);
      });
    }

    test('rejects bad digits and negative counters', () {
      expect(
        () => Otp.hotp(rfcSecret, counter: 0, digits: 9),
        throwsArgumentError,
      );
      expect(() => Otp.hotp(rfcSecret, counter: -1), throwsArgumentError);
    });

    test('large counters use the full 64-bit big-endian encoding', () {
      // Same value as the TOTP vector at T = 20000000000 / 30.
      expect(Otp.hotp(rfcSecret, counter: 666666666, digits: 8), '65353130');
    });
  });

  group('TOTP (RFC 6238 Appendix B)', () {
    // Seeds per algorithm, as in the RFC's reference implementation.
    final seeds = {
      OtpAlgorithm.sha1: utf8.encode('12345678901234567890'),
      OtpAlgorithm.sha256: utf8.encode('12345678901234567890123456789012'),
      OtpAlgorithm.sha512: utf8.encode(
        '1234567890123456789012345678901234567890'
        '123456789012345678901234',
      ),
    };
    const vectors = <(int, OtpAlgorithm, String)>[
      (59, OtpAlgorithm.sha1, '94287082'),
      (59, OtpAlgorithm.sha256, '46119246'),
      (59, OtpAlgorithm.sha512, '90693936'),
      (1111111109, OtpAlgorithm.sha1, '07081804'),
      (1111111109, OtpAlgorithm.sha256, '68084774'),
      (1111111109, OtpAlgorithm.sha512, '25091201'),
      (1111111111, OtpAlgorithm.sha1, '14050471'),
      (1111111111, OtpAlgorithm.sha256, '67062674'),
      (1111111111, OtpAlgorithm.sha512, '99943326'),
      (1234567890, OtpAlgorithm.sha1, '89005924'),
      (1234567890, OtpAlgorithm.sha256, '91819424'),
      (1234567890, OtpAlgorithm.sha512, '93441116'),
      (2000000000, OtpAlgorithm.sha1, '69279037'),
      (2000000000, OtpAlgorithm.sha256, '90698825'),
      (2000000000, OtpAlgorithm.sha512, '38618901'),
      (20000000000, OtpAlgorithm.sha1, '65353130'),
      (20000000000, OtpAlgorithm.sha256, '77737706'),
      (20000000000, OtpAlgorithm.sha512, '47863826'),
    ];
    for (final (time, algorithm, code) in vectors) {
      test('T=$time ${algorithm.label}', () {
        expect(
          Otp.totp(
            seeds[algorithm]!,
            at: _unix(time),
            digits: 8,
            algorithm: algorithm,
          ),
          code,
        );
      });
    }

    test('6 digits is the last 6 digits of the 8-digit value', () {
      expect(Otp.totp(rfcSecret, at: _unix(59)), '287082');
    });

    test('custom period changes the step', () {
      // T=59 with a 60 s period is step 0 → HOTP count 0.
      expect(Otp.totp(rfcSecret, at: _unix(59), period: 60), '755224');
      expect(Otp.timeStep(_unix(59), 60), 0);
      expect(Otp.timeStep(_unix(60), 60), 1);
    });

    test('codes change exactly on period boundaries', () {
      final a = Otp.totp(rfcSecret, at: _unix(89));
      final b = Otp.totp(rfcSecret, at: _unix(60));
      final c = Otp.totp(rfcSecret, at: _unix(90));
      expect(a, b);
      expect(c, isNot(a));
    });

    test('remaining time', () {
      expect(Otp.secondsRemaining(_unix(60), 30), 30);
      expect(Otp.secondsRemaining(_unix(89), 30), 1);
      expect(
        Otp.remainingFraction(
          DateTime.fromMillisecondsSinceEpoch(75000, isUtc: true),
          30,
        ),
        closeTo(0.5, 1e-9),
      );
      expect(() => Otp.timeStep(_unix(1), 0), throwsArgumentError);
    });

    test('local and UTC DateTimes give the same code', () {
      final utc = _unix(1234567890);
      expect(
        Otp.totp(rfcSecret, at: utc.toLocal()),
        Otp.totp(rfcSecret, at: utc),
      );
    });
  });

  group('OtpCodecImpl', () {
    const codec = OtpCodecImpl();

    test('decodes Base32 and generates the RFC code', () {
      final secret = codec
          .decodeSecret('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ')
          .valueOrNull!;
      expect(secret, Uint8List.fromList(rfcSecret));
      expect(codec.hotp(secret, counter: 1), '287082');
      expect(codec.totp(secret, at: _unix(59), digits: 8), '94287082');
    });

    test('normalizes and parses through the port', () {
      expect(
        codec.normalizeSecret('gezd gnbv gy3t qojq').valueOrNull,
        'GEZDGNBVGY3TQOJQ',
      );
      final r = codec.parseUri(
        'otpauth://totp/ACME:jo?secret=GEZDGNBVGY3TQOJQ&issuer=ACME',
      );
      expect(r.valueOrNull?.issuer, 'ACME');
      expect(
        codec.parseUri('nope').failureOrNull?.code,
        FailureCode.invalidOtpUri,
      );
    });
  });
}
