import 'package:meta/meta.dart';

/// What a licence grants. `expired` is never a plan: an ended licence is a
/// token of the plan it was, with `exp` in the past.
enum LicencePlan {
  /// Free day with every feature, from the device's first registration.
  trial,

  /// Prepaid day pass (N × 24 h).
  day,

  /// Monthly subscription.
  monthly;

  static LicencePlan? parse(Object? value) =>
      value is String ? values.asNameMap()[value] : null;
}

/// The signed claims of a licence token (format version 1).
///
/// Wire names: `v`, `did`, `plan`, `iat`, `exp`, `tid`, and the optional
/// `grace` and `rn`. Times are whole seconds since the Unix epoch on the
/// server's clock.
@immutable
class LicencePayload {
  const LicencePayload({
    required this.deviceHash,
    required this.plan,
    required this.issuedAt,
    required this.expiresAt,
    required this.tokenId,
    this.grace = Duration.zero,
    this.willRenew,
    this.version = currentVersion,
  });

  static const currentVersion = 1;

  /// `v`: token format version.
  final int version;

  /// `did`: salted SHA-256 of the device ID (64 hex chars). Never the raw ID.
  final String deviceHash;

  /// `plan`.
  final LicencePlan plan;

  /// `iat`: when the server issued the token.
  final DateTime issuedAt;

  /// `exp`: access ends here. For a renewing monthly plan this is the end
  /// of the paid period plus [grace], so a late renewal check doesn't lock
  /// the user out.
  final DateTime expiresAt;

  /// `tid`: random token id (support, de-duplication). Not a secret.
  final String tokenId;

  /// `grace`: how much of the time before [expiresAt] is grace rather than
  /// paid time. Zero for trials, day passes and cancelled monthly plans.
  final Duration grace;

  /// `rn`: monthly only, whether the subscription is set to renew.
  final bool? willRenew;

  /// End of the paid period: [expiresAt] minus [grace].
  DateTime get paidUntil => expiresAt.subtract(grace);

  Map<String, Object?> toJson() => {
    'v': version,
    'did': deviceHash,
    'plan': plan.name,
    'iat': _seconds(issuedAt),
    'exp': _seconds(expiresAt),
    'tid': tokenId,
    if (grace > Duration.zero) 'grace': grace.inSeconds,
    if (willRenew != null) 'rn': willRenew,
  };

  /// Parses decoded payload JSON. Returns null if a required claim is
  /// missing or has the wrong type. Unknown claims are ignored, so the
  /// server can add optional ones without breaking old apps.
  static LicencePayload? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final v = json['v'];
    final did = json['did'];
    final plan = LicencePlan.parse(json['plan']);
    final iat = json['iat'];
    final exp = json['exp'];
    final tid = json['tid'];
    final grace = json['grace'];
    final rn = json['rn'];
    if (v is! int ||
        did is! String ||
        plan == null ||
        iat is! int ||
        exp is! int ||
        tid is! String ||
        (grace != null && (grace is! int || grace < 0)) ||
        (rn != null && rn is! bool)) {
      return null;
    }
    return LicencePayload(
      version: v,
      deviceHash: did,
      plan: plan,
      issuedAt: _fromSeconds(iat),
      expiresAt: _fromSeconds(exp),
      tokenId: tid,
      grace: Duration(seconds: grace is int ? grace : 0),
      willRenew: rn is bool ? rn : null,
    );
  }

  static int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromSeconds(int s) =>
      DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

  @override
  bool operator ==(Object other) =>
      other is LicencePayload &&
      other.version == version &&
      other.deviceHash == deviceHash &&
      other.plan == plan &&
      other.issuedAt == issuedAt &&
      other.expiresAt == expiresAt &&
      other.tokenId == tokenId &&
      other.grace == grace &&
      other.willRenew == willRenew;

  @override
  int get hashCode => Object.hash(
    version,
    deviceHash,
    plan,
    issuedAt,
    expiresAt,
    tokenId,
    grace,
    willRenew,
  );

  @override
  String toString() =>
      'LicencePayload(${plan.name}, exp: $expiresAt, grace: $grace)';
}
