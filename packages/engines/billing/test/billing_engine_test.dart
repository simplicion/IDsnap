import 'package:engine_billing/engine_billing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_store.dart';
import 'play_signature_test.dart';

void main() {
  late FakeBillingStore store;
  late MemoryBillingStorage storage;
  late TestClock clock;

  setUp(() {
    store = FakeBillingStore();
    storage = MemoryBillingStorage();
    clock = TestClock(DateTime.utc(2026, 10, 1, 12));
  });

  tearDown(() => store.close());

  BillingEngine engine({PlaySignatureVerifier? verifier}) => BillingEngine(
    store: store,
    storage: storage,
    verifier: verifier,
    now: clock.call,
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('first start: trial with 30 days, before the store answers', () async {
    final e = engine();
    await e.start();
    expect(e.status.kind, EntitlementKind.trial);
    expect(e.status.trialDaysLeft, 30);
  });

  test('trial ends after 30 days without a purchase', () async {
    final e = engine();
    await e.start();
    clock.advance(const Duration(days: 30));
    expect(e.status.kind, EntitlementKind.expired);
    expect(e.status.lapseReason, LapseReason.trialEnded);
  });

  test('purchase success: unlocks, caches and acknowledges', () async {
    final e = engine();
    await e.start();
    clock.advance(const Duration(days: 40));
    final result = e.purchase(BillingPlan.lifetime);
    await flush();
    expect(store.bought, [BillingProducts.lifetime]);
    final p = purchase(BillingProducts.lifetime);
    store.emit([p]);
    expect((await result).kind, PurchaseResultKind.purchased);
    expect(e.status.kind, EntitlementKind.lifetime);
    expect(store.completed, [p], reason: 'must acknowledge within 3 days');

    // Cold start offline: the cache keeps Pro unlocked.
    store.available = false;
    final again = engine();
    await again.start();
    await again.refresh();
    expect(again.status.kind, EntitlementKind.lifetime);
  });

  test('monthly purchase caches the renewal date', () async {
    final e = engine();
    await e.start();
    final result = e.purchase(BillingPlan.monthly);
    await flush();
    store.emit([
      purchase(BillingProducts.monthly, at: clock.now, autoRenewing: true),
    ]);
    expect((await result).kind, PurchaseResultKind.purchased);
    expect(e.status.kind, EntitlementKind.monthly);
    expect(e.status.expiresAt, DateTime.utc(2026, 11, 1, 12));
    expect(e.status.willRenew, isTrue);
  });

  test(
    'pending purchase: not unlocked, not acknowledged, until paid',
    () async {
      final e = engine();
      await e.start();
      clock.advance(const Duration(days: 31));
      final result = e.purchase(BillingPlan.lifetime);
      await flush();
      store.emit([
        purchase(
          BillingProducts.lifetime,
          status: StorePurchaseStatus.pending,
          needsAck: false,
        ),
      ]);
      expect((await result).kind, PurchaseResultKind.pending);
      expect(e.status.isEntitled, isFalse);
      expect(e.status.purchasePending, isTrue);
      expect(store.completed, isEmpty);

      store.emit([purchase(BillingProducts.lifetime)]);
      await flush();
      expect(e.status.kind, EntitlementKind.lifetime);
      expect(e.status.purchasePending, isFalse);
      expect(store.completed, hasLength(1));
    },
  );

  test('cancelled and error outcomes leave the state unchanged', () async {
    final e = engine();
    await e.start();
    clock.advance(const Duration(days: 31));

    final cancelled = e.purchase(BillingPlan.monthly);
    await flush();
    store.emit([
      purchase(BillingProducts.monthly, status: StorePurchaseStatus.canceled),
    ]);
    expect((await cancelled).kind, PurchaseResultKind.cancelled);

    final failed = e.purchase(BillingPlan.monthly);
    await flush();
    store.emit([
      purchase(BillingProducts.monthly, status: StorePurchaseStatus.error),
    ]);
    final r = await failed;
    expect(r.kind, PurchaseResultKind.failed);
    expect(r.message, isNotNull);
    expect(e.status.kind, EntitlementKind.expired);
    // Failed/cancelled transactions are finished so they don't linger (iOS).
    expect(store.completed, hasLength(2));
  });

  test('store unavailable: purchase says so; prices fall back', () async {
    store.available = false;
    final e = engine();
    await e.start();
    expect(
      (await e.purchase(BillingPlan.monthly)).kind,
      PurchaseResultKind.storeUnavailable,
    );
    final prices = await e.prices();
    expect(prices.map((p) => p.price), [r'$2', r'$50']);
    expect(prices.every((p) => !p.fromStore), isTrue);
  });

  test('prices come from the store when it answers', () async {
    final e = engine();
    await e.start();
    final prices = await e.prices();
    expect(prices.map((p) => p.price), [r'$1.99', r'$49.99']);
    expect(prices.every((p) => p.fromStore), isTrue);
  });

  test('flow that cannot start but is already owned → purchased', () async {
    store.onBuy = (_) => false;
    final e = engine();
    await e.start();
    store.owned = [purchase(BillingProducts.lifetime, needsAck: false)];
    final r = await e.purchase(BillingPlan.lifetime);
    expect(r.kind, PurchaseResultKind.purchased);
  });

  group('restore', () {
    test('finds an owned purchase and acknowledges it', () async {
      final e = engine();
      await e.start();
      clock.advance(const Duration(days: 45));
      final owned = purchase(BillingProducts.lifetime);
      store.owned = [owned];
      final r = await e.restore();
      expect(r.restored, isTrue);
      expect(e.status.kind, EntitlementKind.lifetime);
      expect(store.completed, [owned]);
    });

    test('nothing owned → honest message', () async {
      final e = engine();
      await e.start();
      final r = await e.restore();
      expect(r.restored, isFalse);
      expect(r.message, contains('No IDSnap Pro purchase'));
    });

    test('restored items on the purchase stream unlock too', () async {
      final e = engine();
      await e.start();
      store.emit([
        purchase(
          BillingProducts.monthly,
          status: StorePurchaseStatus.restored,
          needsAck: false,
          at: clock.now,
        ),
      ]);
      await flush();
      expect(e.status.kind, EntitlementKind.monthly);
      expect(store.completed, isEmpty, reason: 'already acknowledged');
    });
  });

  group('refresh', () {
    test('store no longer lists the plan → subscription ended', () async {
      final e = engine();
      await e.start();
      store.owned = [purchase(BillingProducts.monthly, at: clock.now)];
      await e.refresh();
      expect(e.status.kind, EntitlementKind.monthly);

      clock.advance(const Duration(days: 45));
      store.owned = [];
      await e.refresh();
      expect(e.status.kind, EntitlementKind.expired);
      expect(e.status.lapseReason, LapseReason.subscriptionEnded);
    });

    test(
      'store unreachable → cached plan + grace period, then lapse',
      () async {
        final e = engine();
        await e.start();
        store.owned = [purchase(BillingProducts.monthly, at: clock.now)];
        await e.refresh();
        final expires = e.status.expiresAt!;

        store.available = false;
        final offline = engine();
        clock.now = expires.add(const Duration(days: 1));
        await offline.start();
        await offline.refresh();
        expect(offline.status.kind, EntitlementKind.monthly);
        expect(offline.status.inGracePeriod, isTrue);

        clock.now = expires.add(const Duration(days: 4));
        expect(offline.status.kind, EntitlementKind.expired);
      },
    );

    test('store query failure keeps the cache', () async {
      final e = engine();
      await e.start();
      store.owned = [purchase(BillingProducts.lifetime)];
      await e.refresh();
      store.owned = null;
      await e.refresh();
      expect(e.status.kind, EntitlementKind.lifetime);
    });

    test('lifetime wins over an active monthly (upgrade)', () async {
      final e = engine();
      await e.start();
      store.owned = [
        purchase(BillingProducts.monthly, at: clock.now),
        purchase(BillingProducts.lifetime),
      ];
      await e.refresh();
      expect(e.status.kind, EntitlementKind.lifetime);
    });

    test('emits changes', () async {
      final e = engine();
      final seen = <EntitlementKind>[];
      final sub = e.changes.listen((s) => seen.add(s.kind));
      await e.start();
      store.owned = [purchase(BillingProducts.lifetime)];
      await e.refresh();
      await flush();
      expect(seen, [EntitlementKind.trial, EntitlementKind.lifetime]);
      await sub.cancel();
    });
  });

  group('Play signature verification', () {
    late PlaySignatureVerifier verifier;
    setUp(() => verifier = PlaySignatureVerifier.fromBase64(testPublicKey)!);

    test('a valid signature unlocks', () async {
      final e = engine(verifier: verifier);
      await e.start();
      store.emit([
        purchase(
          BillingProducts.lifetime,
          signedData: signedLifetimeJson,
          signature: signedLifetimeSignature,
        ),
      ]);
      await flush();
      expect(e.status.kind, EntitlementKind.lifetime);
      expect(store.completed, hasLength(1));
    });

    test('a forged purchase is rejected and not acknowledged', () async {
      final e = engine(verifier: verifier);
      await e.start();
      clock.advance(const Duration(days: 31));
      final result = e.purchase(BillingPlan.lifetime);
      await flush();
      store.emit([
        purchase(
          BillingProducts.lifetime,
          signedData: signedLifetimeJson.replaceFirst('tok', 'forged'),
          signature: signedLifetimeSignature,
        ),
      ]);
      final r = await result;
      expect(r.kind, PurchaseResultKind.failed);
      expect(e.status.isEntitled, isFalse);
      expect(store.completed, isEmpty);
    });

    test('signed data for another product is rejected', () async {
      final e = engine(verifier: verifier);
      await e.start();
      clock.advance(const Duration(days: 31));
      store.emit([
        purchase(
          BillingProducts.monthly,
          signedData: signedLifetimeJson,
          signature: signedLifetimeSignature,
        ),
      ]);
      await flush();
      expect(e.status.isEntitled, isFalse);
    });
  });

  test('clock set back after the trial → expired with tamper reason', () async {
    final e = engine();
    await e.start();
    clock.advance(const Duration(days: 20));
    await e.refresh();
    clock.now = clock.now.subtract(const Duration(days: 15));
    await e.refresh();
    expect(e.status.kind, EntitlementKind.expired);
    expect(e.status.lapseReason, LapseReason.clockTampered);
  });

  test('purchase times out as cancelled if the store never answers', () async {
    final e = BillingEngine(
      store: store,
      storage: storage,
      now: clock.call,
      purchaseTimeout: const Duration(milliseconds: 20),
    );
    await e.start();
    final r = await e.purchase(BillingPlan.monthly);
    expect(r.kind, PurchaseResultKind.cancelled);
  });
}
