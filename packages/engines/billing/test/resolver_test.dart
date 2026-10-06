import 'package:engine_billing/engine_billing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 2);
  TrialStatus trial({Duration age = Duration.zero, DateTime? maxSeen}) =>
      TrialStatus(
        firstLaunch: t0,
        maxSeen: maxSeen ?? t0.add(age),
        now: t0.add(age),
      );

  group('resolveEntitlement', () {
    test('active trial', () {
      final s = resolveEntitlement(
        now: t0.add(const Duration(days: 25)),
        trial: trial(age: const Duration(days: 25)),
        cache: null,
      );
      expect(s.kind, EntitlementKind.trial);
      expect(s.trialDaysLeft, 5);
      expect(s.isEntitled, isTrue);
    });

    test('trial over and nothing bought → expired (trialEnded)', () {
      final now = t0.add(const Duration(days: 31));
      final s = resolveEntitlement(now: now, trial: trial(), cache: null);
      expect(s.kind, EntitlementKind.expired);
      expect(s.lapseReason, LapseReason.trialEnded);
      expect(s.isEntitled, isFalse);
    });

    test('lifetime always wins, even with the clock set back', () {
      final s = resolveEntitlement(
        now: t0.add(const Duration(days: 40)),
        trial: trial(maxSeen: t0.add(const Duration(days: 90))),
        cache: CachedEntitlement(kind: CachedKind.lifetime, verifiedAt: t0),
      );
      expect(s.kind, EntitlementKind.lifetime);
    });

    test('cached monthly plan works offline until it expires', () {
      final expires = t0.add(const Duration(days: 40));
      final cache = CachedEntitlement(
        kind: CachedKind.monthly,
        verifiedAt: t0,
        expiresAt: expires,
        willRenew: true,
      );
      final s = resolveEntitlement(
        now: t0.add(const Duration(days: 35)),
        trial: trial(),
        cache: cache,
      );
      expect(s.kind, EntitlementKind.monthly);
      expect(s.expiresAt, expires);
      expect(s.willRenew, isTrue);
      expect(s.inGracePeriod, isFalse);
    });

    test('grace period: honoured for 3 days past expiry, then lapses', () {
      final expires = t0.add(const Duration(days: 40));
      final cache = CachedEntitlement(
        kind: CachedKind.monthly,
        verifiedAt: t0,
        expiresAt: expires,
      );
      final inGrace = resolveEntitlement(
        now: expires.add(const Duration(days: 2, hours: 23)),
        trial: trial(),
        cache: cache,
      );
      expect(inGrace.kind, EntitlementKind.monthly);
      expect(inGrace.inGracePeriod, isTrue);

      final lapsed = resolveEntitlement(
        now: expires.add(subscriptionGracePeriod),
        trial: trial(),
        cache: cache,
      );
      expect(lapsed.kind, EntitlementKind.expired);
      expect(lapsed.lapseReason, LapseReason.subscriptionEnded);
    });

    test('a store-confirmed lapse says the plan ended', () {
      final s = resolveEntitlement(
        now: t0.add(const Duration(days: 60)),
        trial: trial(),
        cache: CachedEntitlement(
          kind: CachedKind.lapsed,
          verifiedAt: t0,
          expiresAt: t0.add(const Duration(days: 50)),
        ),
      );
      expect(s.kind, EntitlementKind.expired);
      expect(s.lapseReason, LapseReason.subscriptionEnded);
    });

    test('paid monthly beats an active trial', () {
      final s = resolveEntitlement(
        now: t0.add(const Duration(days: 2)),
        trial: trial(age: const Duration(days: 2)),
        cache: CachedEntitlement(
          kind: CachedKind.monthly,
          verifiedAt: t0,
          expiresAt: t0.add(const Duration(days: 30)),
        ),
      );
      expect(s.kind, EntitlementKind.monthly);
    });

    test('clock set back: trial and unconfirmed cache are not honoured', () {
      final now = t0.add(const Duration(days: 3));
      final tampered = trial(
        age: const Duration(days: 3),
        maxSeen: t0.add(const Duration(days: 20)),
      );
      final cache = CachedEntitlement(
        kind: CachedKind.monthly,
        verifiedAt: t0,
        expiresAt: t0.add(const Duration(days: 10)),
      );
      final s = resolveEntitlement(now: now, trial: tampered, cache: cache);
      expect(s.kind, EntitlementKind.expired);
      expect(s.lapseReason, LapseReason.clockTampered);

      final confirmed = resolveEntitlement(
        now: now,
        trial: tampered,
        cache: cache,
        confirmedThisSession: true,
      );
      expect(confirmed.kind, EntitlementKind.monthly);
    });
  });

  group('nextRenewal', () {
    test('first monthly anniversary after now', () {
      final bought = DateTime.utc(2026, 1, 15, 10);
      expect(
        nextRenewal(bought, DateTime.utc(2026, 1, 20)),
        DateTime.utc(2026, 2, 15, 10),
      );
      expect(
        nextRenewal(bought, DateTime.utc(2026, 3, 15, 11)),
        DateTime.utc(2026, 4, 15, 10),
      );
    });

    test('clamps to month end like the stores do', () {
      final bought = DateTime.utc(2026, 1, 31);
      expect(
        nextRenewal(bought, DateTime.utc(2026, 2, 2)),
        DateTime.utc(2026, 2, 28),
      );
    });

    test('crosses the year boundary', () {
      expect(
        nextRenewal(DateTime.utc(2026, 11, 30), DateTime.utc(2026, 12, 31)),
        DateTime.utc(2027, 1, 30),
      );
    });
  });
}
