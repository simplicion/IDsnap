import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:test/test.dart';

const _secret = 'JBSWY3DPEHPK3PXP';

NewOtpAccount _ok(String uri) {
  final r = OtpAuthUri.parse(uri);
  expect(r.failureOrNull, isNull, reason: r.failureOrNull?.detail);
  return r.valueOrNull!;
}

void _fails(String uri, String detail, {FailureCode? code}) {
  final f = OtpAuthUri.parse(uri).failureOrNull;
  expect(f, isNotNull, reason: uri);
  expect(f!.code, code ?? FailureCode.invalidOtpUri, reason: uri);
  expect(f.detail, detail, reason: uri);
}

void main() {
  group('valid URIs', () {
    test('Key URI Format example with defaults', () {
      final a = _ok(
        'otpauth://totp/Example:alice@google.com?secret=$_secret'
        '&issuer=Example',
      );
      expect(a.type, OtpType.totp);
      expect(a.label, 'alice@google.com');
      expect(a.issuer, 'Example');
      expect(a.secret, _secret);
      expect(a.algorithm, OtpAlgorithm.sha1);
      expect(a.digits, 6);
      expect(a.period, 30);
      expect(a.counter, 0);
    });

    test('all parameters', () {
      final a = _ok(
        'otpauth://totp/ACME%20Co:john.doe@email.com?'
        'secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co'
        '&algorithm=SHA512&digits=8&period=60',
      );
      expect(a.label, 'john.doe@email.com');
      expect(a.issuer, 'ACME Co');
      expect(a.algorithm, OtpAlgorithm.sha512);
      expect(a.digits, 8);
      expect(a.period, 60);
    });

    test('HOTP with counter', () {
      final a = _ok('otpauth://hotp/Bank:me?secret=$_secret&counter=42');
      expect(a.type, OtpType.hotp);
      expect(a.counter, 42);
      expect(a.issuer, 'Bank');
    });

    test('issuer parameter takes precedence over the label prefix', () {
      final a = _ok('otpauth://totp/Old%20Name:me?secret=$_secret&issuer=New');
      expect(a.issuer, 'New');
      expect(a.label, 'me');
    });

    test('empty issuer parameter falls back to the label prefix', () {
      expect(
        _ok('otpauth://totp/Prefix:me?secret=$_secret&issuer=').issuer,
        'Prefix',
      );
    });

    test('label without issuer', () {
      final a = _ok('otpauth://totp/me@example.com?secret=$_secret');
      expect(a.issuer, isNull);
      expect(a.label, 'me@example.com');
    });

    test('encoded colon and spaces around it', () {
      final a = _ok('otpauth://totp/My%20Bank%3A%20%20me?secret=$_secret');
      expect(a.issuer, 'My Bank');
      expect(a.label, 'me');
    });

    test('only an issuer: the issuer becomes the label', () {
      final a = _ok('otpauth://totp/?secret=$_secret&issuer=Solo');
      expect(a.label, 'Solo');
      expect(a.issuer, 'Solo');
    });

    test('case-insensitive scheme, type, keys and algorithm', () {
      final a = _ok(
        'OTPAUTH://TOTP/x?SECRET=${_secret.toLowerCase()}&Algorithm=sha256',
      );
      expect(a.algorithm, OtpAlgorithm.sha256);
      expect(a.secret, _secret);
    });

    test('secret with spaces and padding is normalised', () {
      expect(
        _ok('otpauth://totp/x?secret=jbsw%20y3dp%20ehpk%203pxp%3D%3D').secret,
        _secret,
      );
    });

    test('unknown parameters (image, etc.) are ignored', () {
      _ok('otpauth://totp/x?secret=$_secret&image=https%3A%2F%2Fa.b%2Fc.png');
    });

    test('surrounding whitespace is trimmed', () {
      _ok('  otpauth://totp/x?secret=$_secret \n');
    });

    test('HOTP counter 0 is valid', () {
      expect(_ok('otpauth://hotp/x?secret=$_secret&counter=0').counter, 0);
    });
  });

  group('invalid URIs', () {
    test('wrong scheme', () {
      _fails('https://example.com', OtpAuthUri.notOtpAuth);
      _fails('hello world', OtpAuthUri.notOtpAuth);
      _fails('', OtpAuthUri.notOtpAuth);
    });

    test('Google Authenticator export', () {
      _fails(
        'otpauth-migration://offline?data=abc',
        OtpAuthUri.migrationUnsupported,
      );
    });

    test('unknown type', () {
      _fails('otpauth://motp/x?secret=$_secret', OtpAuthUri.unknownType);
      _fails('otpauth:totp/x?secret=$_secret', OtpAuthUri.unknownType);
    });

    test('missing or empty secret', () {
      _fails('otpauth://totp/x', OtpAuthUri.missingSecret);
      _fails('otpauth://totp/x?secret=', OtpAuthUri.missingSecret);
    });

    test('bad secret is an invalidSecretKey failure', () {
      _fails(
        'otpauth://totp/x?secret=ABC1',
        Base32.badCharacter,
        code: FailureCode.invalidSecretKey,
      );
    });

    test('missing label and issuer', () {
      _fails('otpauth://totp/?secret=$_secret', OtpAuthUri.missingLabel);
      _fails('otpauth://totp/%20:%20?secret=$_secret', OtpAuthUri.missingLabel);
    });

    test('repeated parameters', () {
      _fails(
        'otpauth://totp/x?secret=$_secret&secret=$_secret',
        OtpAuthUri.repeatedParameter,
      );
      _fails(
        'otpauth://totp/x?secret=$_secret&digits=6&DIGITS=8',
        OtpAuthUri.repeatedParameter,
      );
    });

    test('bad algorithm', () {
      _fails(
        'otpauth://totp/x?secret=$_secret&algorithm=MD5',
        OtpAuthUri.badAlgorithm,
      );
    });

    test('bad digits', () {
      for (final d in ['5', '7', '10', 'six', '-6', '6.0', ' ']) {
        _fails(
          'otpauth://totp/x?secret=$_secret&digits=$d',
          OtpAuthUri.badDigits,
        );
      }
    });

    test('bad period', () {
      for (final p in ['0', '-30', '3601', 'abc', '1e3']) {
        _fails(
          'otpauth://totp/x?secret=$_secret&period=$p',
          OtpAuthUri.badPeriod,
        );
      }
    });

    test('HOTP needs a valid counter', () {
      _fails('otpauth://hotp/x?secret=$_secret', OtpAuthUri.badCounter);
      _fails(
        'otpauth://hotp/x?secret=$_secret&counter=-1',
        OtpAuthUri.badCounter,
      );
      _fails(
        'otpauth://hotp/x?secret=$_secret&counter=0x10',
        OtpAuthUri.badCounter,
      );
    });

    test('malformed percent-encoding', () {
      _fails('otpauth://totp/%E0%A4%A?secret=$_secret', OtpAuthUri.malformed);
    });
  });
}
