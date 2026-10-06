import 'package:engine_license/src/codec.dart';
import 'package:engine_license/src/payload.dart';
import 'package:meta/meta.dart';

/// How far the clock may go backwards (time-zone travel, NTP corrections)
/// before it counts as being set back.
const clockSkewTolerance = Duration(minutes: 10);

/// True when [now] is more than [tolerance] behind [maxSeen], the latest
/// time this install has seen (its own clock, or the server's).
bool isClockRolledBack(
  DateTime now,
  DateTime? maxSeen, {
  Duration tolerance = clockSkewTolerance,
}) => maxSeen != null && now.isBefore(maxSeen.subtract(tolerance));

enum LicenceVerdictKind {
  /// Signed by us, for this device, not expired, clock plausible.
  valid,

  /// Genuine and for this device, but past `exp`.
  expired,

  /// Genuine and for this device, but the phone's clock is behind a time
  /// already seen, so the expiry can't be trusted until the date is fixed.
  clockRolledBack,

  /// Genuine, but issued to another device.
  wrongDevice,

  /// See [LicenceTokenError].
  malformed,
  badSignature,
  unsupportedVersion,
}

@immutable
class LicenceVerdict {
  const LicenceVerdict(this.kind, [this.payload]);

  final LicenceVerdictKind kind;

  /// Set whenever the signature was valid (valid, expired, clockRolledBack,
  /// wrongDevice). Never set for untrusted input.
  final LicencePayload? payload;

  bool get isValid => kind == LicenceVerdictKind.valid;

  @override
  String toString() => 'LicenceVerdict(${kind.name}, $payload)';
}

/// Time and device checks for a payload whose signature is already
/// verified. Cheap and synchronous: call it on every entitlement read so a
/// licence that ends while the app is open lapses on time.
///
/// `exp` is exclusive: at exactly `exp` the licence has ended.
LicenceVerdict evaluateLicence({
  required LicencePayload payload,
  required String deviceHash,
  required DateTime now,
  DateTime? maxSeen,
  Duration tolerance = clockSkewTolerance,
}) {
  if (payload.deviceHash != deviceHash) {
    return LicenceVerdict(LicenceVerdictKind.wrongDevice, payload);
  }
  if (isClockRolledBack(now, maxSeen, tolerance: tolerance)) {
    return LicenceVerdict(LicenceVerdictKind.clockRolledBack, payload);
  }
  if (!now.isBefore(payload.expiresAt)) {
    return LicenceVerdict(LicenceVerdictKind.expired, payload);
  }
  return LicenceVerdict(LicenceVerdictKind.valid, payload);
}

/// Full offline verification of a token string: signature and version
/// ([LicenceVerifier.verify]), then device, clock rollback and expiry
/// ([evaluateLicence]). Never throws.
Future<LicenceVerdict> checkLicence({
  required String token,
  required LicenceVerifier verifier,
  required String deviceHash,
  required DateTime now,
  DateTime? maxSeen,
  Duration tolerance = clockSkewTolerance,
}) async {
  final LicencePayload payload;
  try {
    payload = await verifier.verify(token);
  } on LicenceTokenException catch (e) {
    return LicenceVerdict(switch (e.error) {
      LicenceTokenError.malformed => LicenceVerdictKind.malformed,
      LicenceTokenError.badSignature => LicenceVerdictKind.badSignature,
      LicenceTokenError.unsupportedVersion =>
        LicenceVerdictKind.unsupportedVersion,
    });
  }
  return evaluateLicence(
    payload: payload,
    deviceHash: deviceHash,
    now: now,
    maxSeen: maxSeen,
    tolerance: tolerance,
  );
}
