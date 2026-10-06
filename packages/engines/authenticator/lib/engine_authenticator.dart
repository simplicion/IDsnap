/// Offline 2FA maths: RFC 4226 HOTP, RFC 6238 TOTP, RFC 4648 Base32 and the
/// `otpauth://` Key URI Format. Pure Dart — no Flutter, no I/O, no network.
library;

export 'src/base32.dart';
export 'src/otp.dart';
export 'src/otp_codec.dart';
export 'src/otpauth_uri.dart';
