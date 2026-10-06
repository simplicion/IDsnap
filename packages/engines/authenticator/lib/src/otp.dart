import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// RFC 4226 / RFC 6238 one-time passwords. Pure, synchronous and cheap (one
/// HMAC per code), so it runs on the UI isolate.
abstract final class Otp {
  static const _pow10 = [1, 10, 100, 1000, 10000, 100000, 1000000, 10000000];

  /// HOTP value for [counter] (RFC 4226 §5.3), zero-padded to [digits].
  static String hotp(
    List<int> secret, {
    required int counter,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) {
    if (digits < 1 || digits > 8) {
      throw ArgumentError.value(digits, 'digits', 'must be 1..8');
    }
    if (counter < 0) {
      throw ArgumentError.value(counter, 'counter', 'must be >= 0');
    }
    // 8-byte big-endian counter. Split into two 32-bit halves so this also
    // compiles to JavaScript (no 64-bit setUint64 on the web).
    final msg = ByteData(8)
      ..setUint32(0, counter ~/ 0x100000000)
      ..setUint32(4, counter % 0x100000000);
    final mac = Hmac(
      _hash(algorithm),
      secret,
    ).convert(msg.buffer.asUint8List()).bytes;
    // Dynamic truncation (RFC 4226 §5.4).
    final offset = mac[mac.length - 1] & 0x0F;
    final binary =
        ((mac[offset] & 0x7F) << 24) |
        ((mac[offset + 1] & 0xFF) << 16) |
        ((mac[offset + 2] & 0xFF) << 8) |
        (mac[offset + 3] & 0xFF);
    // 10^8 exceeds the table; 8 digits uses 100000000 directly.
    final modulus = digits == 8 ? 100000000 : _pow10[digits];
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  /// TOTP value for the time step containing [at] (RFC 6238 §4.2).
  static String totp(
    List<int> secret, {
    required DateTime at,
    int period = 30,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) => hotp(
    secret,
    counter: timeStep(at, period),
    digits: digits,
    algorithm: algorithm,
  );

  /// T = floor((unix seconds − T0) / period), with T0 = 0.
  static int timeStep(DateTime at, int period) {
    if (period <= 0) {
      throw ArgumentError.value(period, 'period', 'must be > 0');
    }
    final seconds = at.millisecondsSinceEpoch ~/ 1000;
    return seconds ~/ period;
  }

  /// Fraction of the current step still left, in (0, 1].
  static double remainingFraction(DateTime at, int period) {
    final ms = at.millisecondsSinceEpoch % (period * 1000);
    return 1 - ms / (period * 1000);
  }

  /// Whole seconds left in the current step, 1..period.
  static int secondsRemaining(DateTime at, int period) {
    final ms = at.millisecondsSinceEpoch % (period * 1000);
    return period - ms ~/ 1000;
  }

  static Hash _hash(OtpAlgorithm a) => switch (a) {
    OtpAlgorithm.sha1 => sha1,
    OtpAlgorithm.sha256 => sha256,
    OtpAlgorithm.sha512 => sha512,
  };
}
