import 'package:meta/meta.dart';

// Offline 2FA authenticator (PRD Module 2). Secrets and recovery codes never
// appear in these entities' persisted metadata: they live in the platform
// keystore behind a SecretStore, addressed by OtpAccount.secretKeyId.

/// HMAC hash used to derive codes (RFC 6238 §1.2). SHA-1 is the default and
/// what almost every website uses.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.label);

  /// Name as written in `otpauth://` URIs and shown in the UI.
  final String label;

  static OtpAlgorithm? tryParse(String value) {
    final v = value.trim().toUpperCase().replaceAll('-', '');
    for (final a in values) {
      if (a.label == v) return a;
    }
    return null;
  }
}

/// Time-based (RFC 6238) or counter-based (RFC 4226) one-time passwords.
enum OtpType {
  totp('Time-based'),
  hotp('Counter-based');

  const OtpType(this.label);
  final String label;
}

/// Everything needed to create an account. [secret] is the Base32 shared key
/// as entered or scanned; it is written to secure storage only.
@immutable
class NewOtpAccount {
  const NewOtpAccount({
    required this.label,
    required this.secret,
    this.issuer,
    this.type = OtpType.totp,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
  });

  /// Account name, usually an email or username.
  final String label;

  /// Service name ("GitHub"); `null` when unknown.
  final String? issuer;

  /// Base32 shared secret.
  final String secret;
  final OtpType type;
  final OtpAlgorithm algorithm;

  /// 6 or 8.
  final int digits;

  /// TOTP step in seconds (ignored for HOTP).
  final int period;

  /// HOTP moving factor (ignored for TOTP).
  final int counter;

  /// Only these digit counts are accepted by the authenticator.
  static const supportedDigits = {6, 8};

  @override
  bool operator ==(Object other) =>
      other is NewOtpAccount &&
      other.label == label &&
      other.issuer == issuer &&
      other.secret == secret &&
      other.type == type &&
      other.algorithm == algorithm &&
      other.digits == digits &&
      other.period == period &&
      other.counter == counter;

  @override
  int get hashCode => Object.hash(
    label,
    issuer,
    secret,
    type,
    algorithm,
    digits,
    period,
    counter,
  );

  // Never include the secret.
  @override
  String toString() => 'NewOtpAccount(${type.name}, $algorithm, $digits)';
}

/// A stored authenticator account (metadata only — no secret).
@immutable
class OtpAccount {
  const OtpAccount({
    required this.id,
    required this.label,
    required this.secretKeyId,
    required this.createdAt,
    this.issuer,
    this.type = OtpType.totp,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
    this.sortOrder = 0,
  });

  final String id;
  final String label;
  final String? issuer;

  /// Key of the shared secret in secure storage.
  final String secretKeyId;
  final OtpType type;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;
  final int counter;
  final int sortOrder;
  final DateTime createdAt;

  /// Issuer when known, otherwise the label.
  String get title {
    final i = issuer?.trim();
    return i == null || i.isEmpty ? label : i;
  }

  /// The label when an issuer is shown as [title], otherwise `null`.
  String? get subtitle {
    final i = issuer?.trim();
    return i == null || i.isEmpty ? null : label;
  }

  OtpAccount copyWith({
    String? label,
    String? issuer,
    bool clearIssuer = false,
    int? counter,
    int? sortOrder,
  }) => OtpAccount(
    id: id,
    label: label ?? this.label,
    issuer: clearIssuer ? null : issuer ?? this.issuer,
    secretKeyId: secretKeyId,
    type: type,
    algorithm: algorithm,
    digits: digits,
    period: period,
    counter: counter ?? this.counter,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is OtpAccount &&
      other.id == id &&
      other.label == label &&
      other.issuer == issuer &&
      other.secretKeyId == secretKeyId &&
      other.type == type &&
      other.algorithm == algorithm &&
      other.digits == digits &&
      other.period == period &&
      other.counter == counter &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    issuer,
    secretKeyId,
    type,
    algorithm,
    digits,
    period,
    counter,
    sortOrder,
    createdAt,
  );

  @override
  String toString() => 'OtpAccount($id, ${type.name})';
}

/// A single-use emergency ("backup") code for an account.
@immutable
class RecoveryCode {
  const RecoveryCode(this.code, {this.used = false});

  factory RecoveryCode.fromJson(Map<String, dynamic> j) =>
      RecoveryCode(j['code'] as String, used: (j['used'] as bool?) ?? false);

  final String code;
  final bool used;

  RecoveryCode copyWith({bool? used}) =>
      RecoveryCode(code, used: used ?? this.used);

  Map<String, dynamic> toJson() => {'code': code, 'used': used};

  /// Splits pasted text into codes: one per line (or comma/semicolon
  /// separated), trimmed, blank entries and duplicates dropped, order kept.
  static List<String> splitPasted(String text) {
    final seen = <String>{};
    return [
      for (final raw in text.split(RegExp(r'[\r\n,;]+')))
        if (raw.trim().isNotEmpty && seen.add(raw.trim())) raw.trim(),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is RecoveryCode && other.code == code && other.used == used;

  @override
  int get hashCode => Object.hash(code, used);

  @override
  String toString() => 'RecoveryCode(used: $used)';
}
