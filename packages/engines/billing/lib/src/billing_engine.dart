import 'dart:async';
import 'dart:convert';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_billing/src/billing_storage.dart';
import 'package:engine_billing/src/billing_store.dart';
import 'package:engine_billing/src/entitlement_cache.dart';
import 'package:engine_billing/src/model.dart';
import 'package:engine_billing/src/play_signature.dart';
import 'package:engine_billing/src/resolver.dart';
import 'package:engine_billing/src/trial.dart';

/// Offline billing: trial, store purchases and a verified entitlement
/// cache. No server; see docs/adr/0009-offline-billing-entitlements.md.
///
/// Lifecycle: [start] once at launch (reads the trial record and the cache
/// from secure storage, so the status is right before the store answers),
/// then [refresh] in the background at launch and on every resume.
class BillingEngine {
  BillingEngine({
    required BillingStore store,
    required BillingStorage storage,
    PlaySignatureVerifier? verifier,
    DateTime Function()? now,
    Duration purchaseTimeout = const Duration(minutes: 15),
    RedactedLogger? logger,
  }) : _store = store,
       _tracker = TrialTracker(storage),
       _cacheStore = EntitlementCacheStore(storage),
       _verifier = verifier,
       _now = now ?? DateTime.now,
       _purchaseTimeout = purchaseTimeout,
       _log = logger ?? RedactedLogger('billing');

  final BillingStore _store;
  final TrialTracker _tracker;
  final EntitlementCacheStore _cacheStore;
  final PlaySignatureVerifier? _verifier;
  final DateTime Function() _now;
  final Duration _purchaseTimeout;
  final RedactedLogger _log;

  final _changes = StreamController<BillingStatus>.broadcast();
  final _waiters = <String, Completer<PurchaseResult>>{};
  final _products = <String, StoreProduct>{};
  StreamSubscription<List<StorePurchase>>? _subscription;
  Future<void>? _refreshing;

  TrialStatus? _trial;
  CachedEntitlement? _cache;
  var _confirmedThisSession = false;
  var _pending = false;
  BillingStatus? _last;

  /// The entitlement right now (recomputed on every read, so a trial or a
  /// plan that ends while the app is open lapses on time).
  BillingStatus get status {
    final now = _now().toUtc();
    return resolveEntitlement(
      now: now,
      // Before [start] finishes (or if secure storage never answers), assume
      // a fresh trial rather than locking the user out.
      trial: _trial ?? TrialStatus(firstLaunch: now, maxSeen: now, now: now),
      cache: _cache,
      confirmedThisSession: _confirmedThisSession,
    ).withPending(pending: _pending);
  }

  /// Emits whenever [status] changes because of stored or store data.
  Stream<BillingStatus> get changes => _changes.stream;

  /// Loads the trial record and the cached entitlement and starts
  /// listening to the store. Doesn't wait for the store.
  Future<void> start() async {
    _trial = await _tracker.check(_now().toUtc());
    _cache = await _cacheStore.load();
    _subscription ??= _store.purchaseUpdates.listen(
      (updates) => unawaited(_onUpdates(updates)),
      onError: (Object e) => _log.warn('purchase_stream_error'),
    );
    _emit();
  }

  /// Advances the trial clock and asks the store what this account owns.
  /// Safe to call often; concurrent calls share one query.
  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    _trial = await _tracker.check(_now().toUtc());
    if (await _available()) {
      List<StorePurchase>? owned;
      try {
        owned = await _store.queryOwned();
      } on Object {
        _log.warn('query_owned_failed');
      }
      if (owned != null) await _applySnapshot(owned);
    }
    _emit();
  }

  /// Localized prices from the store, or the labelled fallback prices when
  /// the store can't be reached.
  Future<List<PlanPrice>> prices() async {
    if (await _available()) {
      try {
        final products = await _store.queryProducts(BillingProducts.all);
        for (final p in products) {
          _products[p.id] = p;
        }
      } on Object {
        _log.warn('query_products_failed');
      }
    }
    PlanPrice price(BillingPlan plan, String fallback) {
      final p = _products[plan.productId];
      return p == null
          ? PlanPrice(plan: plan, price: fallback, fromStore: false)
          : PlanPrice(plan: plan, price: p.price, fromStore: true);
    }

    return [
      price(BillingPlan.monthly, BillingProducts.fallbackMonthlyPrice),
      price(BillingPlan.lifetime, BillingProducts.fallbackLifetimePrice),
    ];
  }

  /// Runs the store purchase for [plan] and waits for its outcome on the
  /// purchase stream. Upgrading monthly → lifetime is a separate one-time
  /// purchase; the monthly plan must then be cancelled in the store (the
  /// UI says so), since stores don't convert a subscription into a
  /// one-time product.
  Future<PurchaseResult> purchase(BillingPlan plan) async {
    if (!await _available()) {
      return const PurchaseResult(PurchaseResultKind.storeUnavailable);
    }
    final id = plan.productId;
    if (!_products.containsKey(id)) await prices();
    if (!_products.containsKey(id)) {
      return const PurchaseResult(
        PurchaseResultKind.failed,
        message: "This plan isn't available in the store right now.",
      );
    }
    final previous = _waiters.remove(id);
    if (previous != null && !previous.isCompleted) {
      previous.complete(const PurchaseResult(PurchaseResultKind.cancelled));
    }
    final waiter = _waiters[id] = Completer<PurchaseResult>();
    var started = false;
    try {
      started = await _store.buy(id);
    } on Object {
      _log.warn('buy_failed', {'plan': plan});
    }
    if (!started) {
      _waiters.remove(id);
      // "Already owned" also lands here: a refresh picks the purchase up.
      await refresh();
      if (_covers(plan)) {
        return const PurchaseResult(PurchaseResultKind.purchased);
      }
      return const PurchaseResult(
        PurchaseResultKind.failed,
        message: "The store couldn't start the purchase. Please try again.",
      );
    }
    return await waiter.future.timeout(
      _purchaseTimeout,
      onTimeout: () {
        _waiters.remove(id);
        return const PurchaseResult(PurchaseResultKind.cancelled);
      },
    );
  }

  /// Asks the store for this account's purchases (the "Restore purchases"
  /// button). Also finishes any unacknowledged purchase.
  Future<RestoreResult> restore() async {
    if (!await _available()) {
      return const RestoreResult(
        restored: false,
        message: "The app store isn't available on this device.",
      );
    }
    await refresh();
    final kind = status.kind;
    if (kind == EntitlementKind.monthly || kind == EntitlementKind.lifetime) {
      return const RestoreResult(restored: true);
    }
    return const RestoreResult(
      restored: false,
      message:
          'No IDSnap Pro purchase was found for the account signed in to '
          'the store.',
    );
  }

  /// Opens the store's subscription page (cancel, change payment).
  Future<bool> manageSubscription() async {
    try {
      return await _store.openManageSubscriptions(BillingProducts.monthly);
    } on Object {
      return false;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
  }

  // ── Store updates ─────────────────────────────────────────────────────────

  Future<void> _onUpdates(List<StorePurchase> updates) async {
    for (final p in updates) {
      final plan = BillingPlan.fromProductId(p.productId);
      if (plan == null) continue;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          _pending = true;
          _settle(
            p.productId,
            const PurchaseResult(PurchaseResultKind.pending),
          );
        case StorePurchaseStatus.canceled:
          _pending = false;
          await _complete(p);
          _settle(
            p.productId,
            const PurchaseResult(PurchaseResultKind.cancelled),
          );
        case StorePurchaseStatus.error:
          _pending = false;
          await _complete(p);
          _settle(
            p.productId,
            const PurchaseResult(
              PurchaseResultKind.failed,
              message: 'The store reported a problem. You were not charged.',
            ),
          );
        case StorePurchaseStatus.purchased || StorePurchaseStatus.restored:
          if (!_verify(p)) {
            // Not acknowledged: an unverifiable Android purchase is
            // refunded by Google after 3 days.
            _log.warn('purchase_unverified', {'plan': plan});
            _settle(
              p.productId,
              const PurchaseResult(
                PurchaseResultKind.failed,
                message: "This purchase couldn't be verified on this device.",
              ),
            );
            continue;
          }
          _pending = false;
          await _grant(plan, p);
          await _complete(p);
          _settle(
            p.productId,
            const PurchaseResult(PurchaseResultKind.purchased),
          );
      }
    }
    _emit();
  }

  /// Applies the store's full list of what this account owns. The store is
  /// the authority: a plan it no longer lists has ended (or was refunded).
  Future<void> _applySnapshot(List<StorePurchase> owned) async {
    StorePurchase? monthly;
    StorePurchase? lifetime;
    var pending = false;
    for (final p in owned) {
      final plan = BillingPlan.fromProductId(p.productId);
      if (plan == null) continue;
      if (p.status == StorePurchaseStatus.pending) {
        pending = true;
        continue;
      }
      if (p.status != StorePurchaseStatus.purchased &&
          p.status != StorePurchaseStatus.restored) {
        continue;
      }
      if (!_verify(p)) {
        _log.warn('owned_unverified', {'plan': plan});
        continue;
      }
      // Acknowledge anything still pending acknowledgement (e.g. the app
      // was killed right after the purchase).
      await _complete(p);
      if (plan == BillingPlan.lifetime) {
        lifetime = p;
      } else {
        monthly = p;
      }
    }
    _pending = pending;
    _confirmedThisSession = true;
    if (lifetime != null) {
      await _grant(BillingPlan.lifetime, lifetime);
    } else if (monthly != null) {
      await _grant(BillingPlan.monthly, monthly);
    } else if (_cache?.kind == CachedKind.monthly) {
      await _setCache(
        CachedEntitlement(
          kind: CachedKind.lapsed,
          verifiedAt: _now().toUtc(),
          expiresAt: _cache!.expiresAt,
        ),
      );
    } else if (_cache?.kind == CachedKind.lifetime) {
      _log.warn('lifetime_not_owned');
      await _setCache(null);
    }
  }

  Future<void> _grant(BillingPlan plan, StorePurchase p) async {
    final now = _now().toUtc();
    _confirmedThisSession = true;
    if (plan == BillingPlan.lifetime) {
      await _setCache(
        CachedEntitlement(kind: CachedKind.lifetime, verifiedAt: now),
      );
      return;
    }
    // Lifetime always wins over a (not yet cancelled) monthly plan.
    if (_cache?.kind == CachedKind.lifetime) return;
    await _setCache(
      CachedEntitlement(
        kind: CachedKind.monthly,
        verifiedAt: now,
        expiresAt: nextRenewal(p.transactionDate ?? now, now),
        willRenew: p.autoRenewing ?? true,
      ),
    );
  }

  Future<void> _setCache(CachedEntitlement? value) async {
    if (value == _cache) return;
    _cache = value;
    await _cacheStore.save(value);
  }

  /// Local signature check (Android, when the license key is configured).
  /// iOS StoreKit 2 verifies its signed transactions on the device before
  /// the plugin reports them as purchased.
  bool _verify(StorePurchase p) {
    final verifier = _verifier;
    final data = p.signedData;
    if (verifier == null || data == null) return true;
    final signature = p.signature;
    if (signature == null || !verifier.verify(data, signature)) return false;
    try {
      final json = jsonDecode(data);
      if (json is! Map<String, Object?>) return false;
      final ids = [json['productId'], ...?(json['productIds'] as List?)];
      return ids.contains(p.productId);
    } on FormatException {
      return false;
    }
  }

  Future<void> _complete(StorePurchase p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _store.complete(p);
    } on Object {
      // Retried on the next refresh (launch/resume), well within Play's
      // 3-day acknowledgement window.
      _log.warn('complete_failed');
    }
  }

  void _settle(String productId, PurchaseResult result) {
    final waiter = _waiters.remove(productId);
    if (waiter != null && !waiter.isCompleted) waiter.complete(result);
  }

  bool _covers(BillingPlan plan) => switch (status.kind) {
    EntitlementKind.lifetime => true,
    EntitlementKind.monthly => plan == BillingPlan.monthly,
    _ => false,
  };

  Future<bool> _available() async {
    try {
      return await _store.isAvailable();
    } on Object {
      return false;
    }
  }

  void _emit() {
    final s = status;
    if (s == _last || _changes.isClosed) return;
    _last = s;
    _changes.add(s);
  }
}
