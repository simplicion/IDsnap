import 'package:engine_license/engine_license.dart';
import 'package:license_server/src/gateway.dart';
import 'package:license_server/src/store.dart';

/// What a device may use at one instant, and until when.
class Entitlement {
  const Entitlement({
    required this.plan,
    required this.expiresAt,
    required this.active,
    this.grace = Duration.zero,
    this.willRenew,
    this.subscriptionStatus,
  });

  /// The plan in force, or (when not [active]) the one that ended last.
  final LicencePlan plan;

  /// When access ends (or ended). Includes [grace].
  final DateTime expiresAt;
  final bool active;

  /// Monthly only: the part of [expiresAt] beyond the paid period.
  final Duration grace;

  /// Monthly only.
  final bool? willRenew;
  final SubscriptionStatus? subscriptionStatus;

  DateTime get paidUntil => expiresAt.subtract(grace);

  Map<String, Object?> toJson() => {
    'status': active ? plan.name : 'expired',
    'plan': plan.name,
    'expiresAt': expiresAt.toIso8601String(),
    'paidUntil': paidUntil.toIso8601String(),
    'willRenew': ?willRenew,
    if (subscriptionStatus != null)
      'subscriptionStatus': subscriptionStatus!.wire,
    if (!active)
      'reason': plan == LicencePlan.trial ? 'trial_ended' : 'plan_ended',
  };
}

/// Pure entitlement math.
///
/// - Trial: until `trial_ends_at` (set once, at first registration).
/// - Day pass: until `paid_until`.
/// - Monthly: until the period end, plus [grace] while the subscription is
///   still set to renew (ACTIVE, TRIALING or PAST_DUE: a late renewal or
///   180 Pay's dunning retries must not lock a paying user out). A
///   cancelled plan runs to its period end with no grace; an EXPIRED one
///   has ended.
///
/// Of everything still running, the one that lasts longest wins (ties:
/// monthly, then day pass, then trial). If nothing is running, the result
/// is the plan that ended most recently, with `active: false`.
Entitlement computeEntitlement({
  required DeviceRow device,
  required List<SubscriptionRow> subscriptions,
  required DateTime now,
  required Duration grace,
}) {
  final candidates = <Entitlement>[
    for (final s in subscriptions) _monthly(s, now, grace),
    if (device.paidUntil != null)
      Entitlement(
        plan: LicencePlan.day,
        expiresAt: device.paidUntil!,
        active: now.isBefore(device.paidUntil!),
      ),
    Entitlement(
      plan: LicencePlan.trial,
      expiresAt: device.trialEndsAt,
      active: now.isBefore(device.trialEndsAt),
    ),
  ];
  // Stable sort, monthly first in the list: on equal expiry monthly wins.
  Entitlement best(Iterable<Entitlement> from) =>
      from.reduce((a, b) => b.expiresAt.isAfter(a.expiresAt) ? b : a);

  final running = candidates.where((c) => c.active);
  return best(running.isNotEmpty ? running : candidates);
}

Entitlement _monthly(SubscriptionRow s, DateTime now, Duration grace) {
  final renewing =
      !s.cancelAtPeriodEnd &&
      (s.status == SubscriptionStatus.active ||
          s.status == SubscriptionStatus.trialing ||
          s.status == SubscriptionStatus.pastDue);
  var end = renewing ? s.periodEnd.add(grace) : s.periodEnd;
  if (s.status == SubscriptionStatus.expired && s.updatedAt.isBefore(end)) {
    end = s.updatedAt;
  }
  return Entitlement(
    plan: LicencePlan.monthly,
    expiresAt: end,
    active: now.isBefore(end),
    grace: renewing ? grace : Duration.zero,
    willRenew: renewing,
    subscriptionStatus: s.status,
  );
}

/// [from] plus [months] calendar months, day clamped to the month's length
/// (Jan 31 + 1 month = Feb 28/29), in UTC.
DateTime addMonths(DateTime from, int months) {
  final d = from.toUtc();
  final total = d.month - 1 + months;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(
    year,
    month,
    d.day > lastDay ? lastDay : d.day,
    d.hour,
    d.minute,
    d.second,
  );
}
