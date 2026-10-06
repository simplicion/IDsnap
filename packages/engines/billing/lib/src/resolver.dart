import 'package:engine_billing/src/entitlement_cache.dart';
import 'package:engine_billing/src/model.dart';
import 'package:engine_billing/src/trial.dart';

/// How long a cached monthly plan stays unlocked past its expiry when the
/// store can't be reached to confirm the renewal (offline, Play Store
/// disabled). After that it lapses until the store confirms it again.
const subscriptionGracePeriod = Duration(days: 3);

/// Pure entitlement decision. Paid beats trial; lifetime beats monthly.
///
/// [confirmedThisSession]: the store confirmed [cache] since launch. A
/// cached plan that wasn't confirmed is not honoured while the clock is set
/// back, so moving the date back can't stretch a lapsed subscription.
BillingStatus resolveEntitlement({
  required DateTime now,
  required TrialStatus? trial,
  required CachedEntitlement? cache,
  bool confirmedThisSession = false,
  Duration grace = subscriptionGracePeriod,
}) {
  final t = trial?.at(now);
  final tampered = t?.clockTampered ?? false;
  final trialEndsAt = t?.endsAt;
  final daysLeft = t?.daysLeft ?? 0;

  if (cache?.kind == CachedKind.lifetime) {
    return BillingStatus(
      kind: EntitlementKind.lifetime,
      trialEndsAt: trialEndsAt,
      trialDaysLeft: daysLeft,
    );
  }

  if (cache != null && cache.kind == CachedKind.monthly) {
    final expires = cache.expiresAt;
    final trusted = confirmedThisSession || !tampered;
    if (trusted && (expires == null || now.isBefore(expires))) {
      return BillingStatus(
        kind: EntitlementKind.monthly,
        trialEndsAt: trialEndsAt,
        trialDaysLeft: daysLeft,
        expiresAt: expires,
        willRenew: cache.willRenew,
      );
    }
    if (trusted && expires != null && now.isBefore(expires.add(grace))) {
      return BillingStatus(
        kind: EntitlementKind.monthly,
        trialEndsAt: trialEndsAt,
        trialDaysLeft: daysLeft,
        expiresAt: expires,
        willRenew: cache.willRenew,
        inGracePeriod: true,
      );
    }
  }

  if (t != null && t.active) {
    return BillingStatus(
      kind: EntitlementKind.trial,
      trialEndsAt: trialEndsAt,
      trialDaysLeft: daysLeft,
    );
  }

  final hadPlan =
      cache != null &&
      (cache.kind == CachedKind.monthly || cache.kind == CachedKind.lapsed);
  return BillingStatus(
    kind: EntitlementKind.expired,
    trialEndsAt: trialEndsAt,
    expiresAt: hadPlan ? cache.expiresAt : null,
    lapseReason: tampered
        ? LapseReason.clockTampered
        : (hadPlan ? LapseReason.subscriptionEnded : LapseReason.trialEnded),
  );
}

/// End of the current monthly billing period for a subscription that the
/// store reports as active now: the first monthly anniversary of
/// [purchased] after [now] (day clamped to the month's length, as stores
/// do: a subscription bought on Jan 31 renews on Feb 28/29).
DateTime nextRenewal(DateTime purchased, DateTime now) {
  final p = purchased.toUtc();
  var months = 1;
  while (true) {
    final candidate = _addMonths(p, months);
    if (candidate.isAfter(now)) return candidate;
    months++;
    if (months > 12 * 100) return now.add(const Duration(days: 31));
  }
}

DateTime _addMonths(DateTime d, int months) {
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
