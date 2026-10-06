import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/src/base32.dart';
import 'package:engine_authenticator/src/otp.dart';
import 'package:engine_authenticator/src/otpauth_uri.dart';

/// [OtpCodec] adapter over [Otp], [Base32] and [OtpAuthUri].
class OtpCodecImpl implements OtpCodec {
  const OtpCodecImpl();

  @override
  Result<Uint8List> decodeSecret(String base32) => Base32.decode(base32);

  @override
  Result<String> normalizeSecret(String base32) => Base32.normalize(base32);

  @override
  String hotp(
    Uint8List secret, {
    required int counter,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) =>
      Otp.hotp(secret, counter: counter, digits: digits, algorithm: algorithm);

  @override
  String totp(
    Uint8List secret, {
    required DateTime at,
    int period = 30,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) => Otp.totp(
    secret,
    at: at,
    period: period,
    digits: digits,
    algorithm: algorithm,
  );

  @override
  Result<NewOtpAccount> parseUri(String uri) => OtpAuthUri.parse(uri);
}
