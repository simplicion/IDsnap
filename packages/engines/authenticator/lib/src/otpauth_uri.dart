import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/src/base32.dart';

/// Parser for the Key URI Format used by authenticator QR codes:
/// `otpauth://TYPE/LABEL?secret=…&issuer=…&algorithm=…&digits=…&period=…`
/// (`counter` is required for HOTP).
///
/// Validation is strict: unknown types, repeated parameters, unsupported
/// digits/algorithms, bad numbers and bad secrets are all rejected with
/// [FailureCode.invalidOtpUri] (or [FailureCode.invalidSecretKey] for the
/// secret) and a specific detail message.
abstract final class OtpAuthUri {
  static const notOtpAuth = 'This QR code is not a two-step verification code.';
  static const migrationUnsupported =
      'This is a Google Authenticator export. Export each account from the '
      'website instead, or enter its key manually.';
  static const unknownType =
      'Only time-based (TOTP) and counter-based (HOTP) '
      'codes are supported.';
  static const missingSecret = 'The QR code has no secret key.';
  static const missingLabel = 'The QR code has no account name.';
  static const repeatedParameter = 'The QR code repeats a setting.';
  static const badAlgorithm =
      'Unsupported algorithm. Use SHA1, SHA256 or '
      'SHA512.';
  static const badDigits = 'Codes must have 6 or 8 digits.';
  static const badPeriod =
      'The code period must be between 1 and 3600 '
      'seconds.';
  static const badCounter = 'Counter-based codes need a valid counter.';
  static const malformed = 'The QR code is damaged or incomplete.';

  static const maxPeriod = 3600;
  static const _known = {
    'secret',
    'issuer',
    'algorithm',
    'digits',
    'period',
    'counter',
  };

  static Result<NewOtpAccount> parse(String input) {
    final text = input.trim();
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return _fail(malformed);
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'otpauth-migration') return _fail(migrationUnsupported);
    if (scheme != 'otpauth') return _fail(notOtpAuth);

    final type = switch (uri.host.toLowerCase()) {
      'totp' => OtpType.totp,
      'hotp' => OtpType.hotp,
      _ => null,
    };
    if (type == null) return _fail(unknownType);

    // Strict: a parameter we care about may appear once only.
    final Map<String, List<String>> all;
    final String rawLabel;
    try {
      all = uri.queryParametersAll;
      rawLabel = Uri.decodeComponent(
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
      );
    } on Object {
      // Invalid percent-encoding.
      return _fail(malformed);
    }
    final params = <String, String>{};
    for (final e in all.entries) {
      final key = e.key.toLowerCase();
      if (!_known.contains(key)) continue;
      if (e.value.length != 1 || params.containsKey(key)) {
        return _fail(repeatedParameter);
      }
      params[key] = e.value.single.trim();
    }

    final secretRaw = params['secret'];
    if (secretRaw == null || secretRaw.isEmpty) return _fail(missingSecret);
    final secret = Base32.normalize(secretRaw);
    if (secret case Err(:final failure)) return Err(failure);

    // Label: "Issuer:account" (the colon may be percent-encoded).
    String? labelIssuer;
    var account = rawLabel.trim();
    final colon = account.indexOf(':');
    if (colon >= 0) {
      labelIssuer = account.substring(0, colon).trim();
      account = account.substring(colon + 1).trim();
    }
    final paramIssuer = params['issuer'];
    final issuer = (paramIssuer != null && paramIssuer.isNotEmpty)
        ? paramIssuer
        : (labelIssuer?.isNotEmpty ?? false)
        ? labelIssuer
        : null;
    if (account.isEmpty) {
      if (issuer == null) return _fail(missingLabel);
      account = issuer;
    }

    var algorithm = OtpAlgorithm.sha1;
    final a = params['algorithm'];
    if (a != null) {
      final parsed = OtpAlgorithm.tryParse(a);
      if (parsed == null) return _fail(badAlgorithm);
      algorithm = parsed;
    }

    var digits = 6;
    final d = params['digits'];
    if (d != null) {
      final parsed = _strictInt(d);
      if (parsed == null || !NewOtpAccount.supportedDigits.contains(parsed)) {
        return _fail(badDigits);
      }
      digits = parsed;
    }

    var period = 30;
    final p = params['period'];
    if (p != null) {
      final parsed = _strictInt(p);
      if (parsed == null || parsed < 1 || parsed > maxPeriod) {
        return _fail(badPeriod);
      }
      period = parsed;
    }

    var counter = 0;
    if (type == OtpType.hotp) {
      final c = params['counter'];
      final parsed = c == null ? null : _strictInt(c);
      if (parsed == null || parsed < 0) return _fail(badCounter);
      counter = parsed;
    }

    return Ok(
      NewOtpAccount(
        label: account,
        issuer: issuer,
        secret: secret.valueOrNull!,
        type: type,
        algorithm: algorithm,
        digits: digits,
        period: period,
        counter: counter,
      ),
    );
  }

  /// Digits only (no sign, no spaces, no hex), at most 15 of them.
  static int? _strictInt(String s) =>
      RegExp(r'^\d{1,15}$').hasMatch(s) ? int.parse(s) : null;

  static Result<NewOtpAccount> _fail(String detail) =>
      Err(AppFailure(FailureCode.invalidOtpUri, detail: detail));
}
