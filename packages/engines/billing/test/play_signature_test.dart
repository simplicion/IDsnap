import 'package:engine_billing/engine_billing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generated with:
///   openssl genrsa -out k.pem 2048
///   openssl rsa -in k.pem -pubout -outform DER | base64 -w0
///   openssl dgst -sha1 -sign k.pem data.json | base64 -w0
const testPublicKey =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6nX7VtIN0hoqtEF8fcAM9kjXgJPH'
    'loiUHrkMlvYedu3SLMZaueTXgt43sxoPG4hOUAmLnaWnmqv2zVLRbg2bXQ3uIEXaS5RyOeR0'
    '4Pw7wM3bgf2pz/TvLyescCTArEAZYK83ibUxOoTA9JrqdWeM/5ZET16jkAH7u/wqxLNs54kQ'
    '8+c+huYDkwpEhknNzzzCUrRr8meS9yFgxM8VkoXDlj/OO4J4p3KMeP7ip5yQggwijFb9pbTZ'
    '3g2xMcY7ZX6uvmmdt6fZYje2nyD7PDyxkDR5r/YXxc800Lv9BhOjnpWwQI0sjiqs2d3+wJOr'
    'T3pAf5OlGc7xl6veqOe+HpT1mQIDAQAB';

const signedLifetimeJson =
    '{"orderId":"GPA.1234-5678","packageName":"com.idsnap.app",'
    '"productId":"idsnap_pro_lifetime","purchaseTime":1790000000000,'
    '"purchaseState":0,"purchaseToken":"tok","acknowledged":false}';

const signedLifetimeSignature =
    'dOAzTKnssv9A9rhoWeUrJQOb6i5Zksv0NOeUITB2BxotZKIIZtlp5XWlosdWLyE1BOYedFaP'
    '67+SqHrlSGJJVDmEj1kTlW+0nnTp9X7E8ceM5X/cJvfoo7rFBHLQ7sZd2vW8rGZIE29FGPNY'
    'fBCWuE2gRbPYf7wro6rem8eZmoaDhg2cG0M+awxDI0kSMvyhda5QHmZlCQ/jZJm0QyrUlrrN'
    '99amhdFTmbFsJqQklWd9BhK7t4uOjHagKXPgLDA1IVFhUhm1WB+/PjhaPaCN6D6tnvXcxOHT'
    'LmW/bSbxFVlh8oyK8TCrCOWJGGM9FCc/o14xk/MOOqDZrwm5B90MEQ==';

void main() {
  test('parses the key and accepts a genuine signature', () {
    final v = PlaySignatureVerifier.fromBase64(testPublicKey);
    expect(v, isNotNull);
    expect(v!.verify(signedLifetimeJson, signedLifetimeSignature), isTrue);
  });

  test('rejects tampered data or signatures', () {
    final v = PlaySignatureVerifier.fromBase64(testPublicKey)!;
    expect(
      v.verify(
        signedLifetimeJson.replaceFirst('lifetime', 'monthly'),
        signedLifetimeSignature,
      ),
      isFalse,
    );
    final badSig = signedLifetimeSignature.replaceFirst('dOAz', 'dOA0');
    expect(v.verify(signedLifetimeJson, badSig), isFalse);
    expect(v.verify(signedLifetimeJson, 'not base64!'), isFalse);
    expect(v.verify(signedLifetimeJson, ''), isFalse);
  });

  test('empty or malformed keys disable verification', () {
    expect(PlaySignatureVerifier.fromBase64(''), isNull);
    expect(PlaySignatureVerifier.fromBase64('AAAA'), isNull);
    expect(PlaySignatureVerifier.fromBase64('%%%'), isNull);
  });
}
