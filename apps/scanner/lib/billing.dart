import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:engine_billing/engine_billing.dart' as billing;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Android application id, for the Play subscription-management link
/// (store mode only).
const androidPackageName = 'com.idsnap.app';

/// Set by `flutter build` from pubspec.yaml's version.
const _appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '1.0.0',
);

/// Builds the entitlement service for this build's monetization mode
/// (`--dart-define=IDSNAP_MONETIZATION=ads|licence|store`, ADR-0013).
///
/// - `ads` (the default): billing is SWITCHED OFF. Returns
///   [FreeEntitlementService] at once: everything is unlocked for good,
///   no licence client is built, the device is never registered and no
///   licence request is ever made. The licence defines aren't read.
/// - `licence`: licensing as in ADR-0012. Loads and verifies the stored
///   licence (so Pro state is right at cold start, offline), then
///   refreshes it from the licence server in the background. Release
///   builds throw [billing.LicenceConfigError] at startup when
///   IDSNAP_LICENSE_URL / IDSNAP_LICENSE_PUBLIC_KEY are missing or unsafe.
/// - `store`: the Google Play Billing / StoreKit path (ADR-0009;
///   app-store distribution may require store billing for digital
///   features — the owner's decision).
///
/// [clientFactory] builds the licence HTTP client (licence mode only);
/// tests pass one that fails to prove no client exists in ads mode.
Future<EntitlementService> startBilling({
  MonetizationMode? mode,
  billing.LicenceClient? client,
  billing.LicenceClient Function(Uri baseUrl)? clientFactory,
  billing.BillingStorage? storage,
  billing.DeviceIdentity? identity,
  billing.UrlOpener? openUrl,
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
  List<Duration> pollSchedule = billing.defaultPurchasePollSchedule,
  bool release = kReleaseMode,
  String? publicKey,
}) async {
  switch (mode ?? resolveMonetizationMode()) {
    case MonetizationMode.ads:
      return const FreeEntitlementService();
    case MonetizationMode.store:
      return await startStoreBilling(storage: storage);
    case MonetizationMode.licence:
  }

  final settings = billing.resolveLicenceSettings(release: release);
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final store =
      storage ??
      (mobile
          ? billing.SecureBillingStorage()
          : billing.MemoryBillingStorage());
  final engine = billing.LicenceEngine(
    storage: store,
    client:
        client ?? (clientFactory ?? _httpLicenceClient).call(settings.baseUrl),
    verifier: billing.LicenceVerifier.fromEncodedKey(
      publicKey ?? settings.publicKey,
    ),
    identity:
        identity ??
        (mobile
            ? billing.PlatformDeviceIdentity(store)
            : billing.FixedDeviceIdentity('desktop-debug')),
    openUrl: openUrl ?? _openExternal,
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    appVersion: _appVersion,
    now: now,
    sleep: sleep,
    pollSchedule: pollSchedule,
  );
  try {
    await engine.start().timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // Secure storage stuck: continue; the next refresh reloads the licence.
  }
  unawaited(engine.refresh());
  return LicenceEntitlementService(engine);
}

billing.LicenceClient _httpLicenceClient(Uri baseUrl) =>
    billing.HttpLicenceClient(baseUrl: baseUrl);

/// Checkout and the billing portal open in the external browser (custom
/// tab): card data never touches the app.
Future<bool> _openExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Adapts the licence engine to the [EntitlementService] port in contracts.
class LicenceEntitlementService implements EntitlementService {
  LicenceEntitlementService(this.engine);

  final billing.LicenceEngine engine;

  @override
  EntitlementState get current => toEntitlementState(engine.status);

  @override
  Stream<EntitlementState> get changes =>
      engine.changes.map(toEntitlementState);

  @override
  Future<ProPricing> pricing() async {
    final p = await engine.pricing();
    return ProPricing(
      dayPriceCents: p.dayPriceCents,
      monthPriceCents: p.monthPriceCents,
      currency: p.currency,
      minDays: p.minDays,
      maxDays: p.maxDays,
      fromServer: p.fromServer,
    );
  }

  @override
  Future<PurchaseOutcome> purchase(ProPurchase request) async {
    final r = await engine.purchase(
      request.plan == ProPlan.monthly
          ? billing.CheckoutProduct.monthly
          : billing.CheckoutProduct.day,
      days: request.plan == ProPlan.dayPass ? request.days : null,
    );
    return switch (r.kind) {
      billing.LicencePurchaseKind.purchased => const PurchaseOutcome(
        PurchaseOutcomeKind.purchased,
      ),
      billing.LicencePurchaseKind.pending => const PurchaseOutcome(
        PurchaseOutcomeKind.pending,
      ),
      billing.LicencePurchaseKind.failed => PurchaseOutcome(
        PurchaseOutcomeKind.failed,
        message: r.message,
      ),
      billing.LicencePurchaseKind.offline => const PurchaseOutcome(
        PurchaseOutcomeKind.unavailable,
        message: 'Connect to the internet to pay. You were not charged.',
      ),
    };
  }

  @override
  Future<LicenceRefreshOutcome> refreshLicence() async {
    final r = await engine.refresh();
    if (r.ok) return const LicenceRefreshOutcome(ok: true);
    return LicenceRefreshOutcome(
      ok: false,
      message: switch (r.failure) {
        billing.LicenceFailureKind.offline =>
          "You're offline. Connect to the internet and try again.",
        billing.LicenceFailureKind.rateLimited =>
          'Too many attempts. Please wait a few minutes.',
        _ =>
          "The licence server isn't answering right now. Your current "
              'licence keeps working; try again later.',
      },
    );
  }

  @override
  Future<void> refresh() async {
    if (engine.shouldRefresh) await engine.refresh();
  }

  @override
  Future<bool> openManageSubscription() => engine.openManageSubscription();
}

EntitlementState toEntitlementState(billing.LicenceStatus s) {
  final pending = s.purchasePending;
  return switch (s.kind) {
    billing.LicenceKind.trial => TrialEntitlement(
      endsAt: s.expiresAt!,
      purchasePending: pending,
    ),
    billing.LicenceKind.dayPass => DayPassEntitlement(
      expiresAt: s.expiresAt!,
      purchasePending: pending,
    ),
    billing.LicenceKind.monthly => MonthlyEntitlement(
      renewsAt: s.paidUntil,
      expiresAt: s.expiresAt,
      willRenew: s.willRenew,
      inGracePeriod: s.inGracePeriod,
      purchasePending: pending,
    ),
    billing.LicenceKind.expired => ExpiredEntitlement(
      reason: switch (s.lapse) {
        billing.LicenceLapse.dayPassEnded => LapseReason.dayPassEnded,
        billing.LicenceLapse.monthlyEnded => LapseReason.subscriptionEnded,
        billing.LicenceLapse.clockTampered => LapseReason.clockTampered,
        billing.LicenceLapse.notActivated => LapseReason.notActivated,
        billing.LicenceLapse.trialEnded || null => LapseReason.trialEnded,
      },
      endedAt: s.expiresAt,
      purchasePending: pending,
    ),
  };
}

// ── Store billing (IDSNAP_MONETIZATION=store; ADR-0009) ─────────────────────

/// Google Play Billing / StoreKit with a local trial. Compiles and is
/// tested, but isn't used unless selected at build time. Monthly only:
/// the day pass doesn't exist in the stores, and lifetime was retired.
Future<EntitlementService> startStoreBilling({
  billing.BillingStore? store,
  billing.BillingStorage? storage,
}) async {
  final supported = billing.InAppPurchaseStore.supported;
  final engine = billing.BillingEngine(
    store:
        store ??
        (supported
            ? billing.InAppPurchaseStore(androidPackageName: androidPackageName)
            : const billing.UnavailableBillingStore()),
    storage:
        storage ??
        (supported
            ? billing.SecureBillingStorage()
            : billing.MemoryBillingStorage()),
    verifier: billing.PlaySignatureVerifier.fromBase64(billing.playLicenseKey),
  );
  try {
    await engine.start().timeout(const Duration(seconds: 5));
  } on Object {
    // Secure storage stuck or failing: fresh in-memory trial this session.
  }
  unawaited(engine.refresh());
  return StoreEntitlementService(engine);
}

/// Adapts the legacy store engine to the [EntitlementService] port.
class StoreEntitlementService implements EntitlementService {
  StoreEntitlementService(this.engine);

  final billing.BillingEngine engine;

  @override
  EntitlementState get current => storeToEntitlementState(engine.status);

  @override
  Stream<EntitlementState> get changes =>
      engine.changes.map(storeToEntitlementState);

  @override
  Future<ProPricing> pricing() async => fallbackPricing;

  @override
  Future<PurchaseOutcome> purchase(ProPurchase request) async {
    if (request.plan != ProPlan.monthly) {
      return const PurchaseOutcome(
        PurchaseOutcomeKind.unavailable,
        message: "Day passes aren't sold through the app store.",
      );
    }
    final r = await engine.purchase(billing.BillingPlan.monthly);
    return PurchaseOutcome(switch (r.kind) {
      billing.PurchaseResultKind.purchased => PurchaseOutcomeKind.purchased,
      billing.PurchaseResultKind.pending => PurchaseOutcomeKind.pending,
      billing.PurchaseResultKind.cancelled => PurchaseOutcomeKind.cancelled,
      billing.PurchaseResultKind.failed => PurchaseOutcomeKind.failed,
      billing.PurchaseResultKind.storeUnavailable =>
        PurchaseOutcomeKind.unavailable,
    }, message: r.message);
  }

  @override
  Future<LicenceRefreshOutcome> refreshLicence() async {
    final r = await engine.restore();
    return LicenceRefreshOutcome(ok: r.restored, message: r.message);
  }

  @override
  Future<void> refresh() => engine.refresh();

  @override
  Future<bool> openManageSubscription() => engine.manageSubscription();
}

EntitlementState storeToEntitlementState(billing.BillingStatus s) =>
    switch (s.kind) {
      billing.EntitlementKind.trial => TrialEntitlement(
        endsAt: s.trialEndsAt ?? DateTime.now().toUtc(),
        purchasePending: s.purchasePending,
      ),
      billing.EntitlementKind.monthly => MonthlyEntitlement(
        renewsAt: s.expiresAt,
        expiresAt: s.expiresAt,
        willRenew: s.willRenew,
        inGracePeriod: s.inGracePeriod,
        purchasePending: s.purchasePending,
      ),
      // Legacy lifetime purchases (none were sold) stay unlocked.
      billing.EntitlementKind.lifetime => MonthlyEntitlement(
        willRenew: false,
        purchasePending: s.purchasePending,
      ),
      billing.EntitlementKind.expired => ExpiredEntitlement(
        reason: switch (s.lapseReason) {
          billing.LapseReason.subscriptionEnded =>
            LapseReason.subscriptionEnded,
          billing.LapseReason.clockTampered => LapseReason.clockTampered,
          billing.LapseReason.trialEnded || null => LapseReason.trialEnded,
        },
        endedAt: s.expiresAt ?? s.trialEndsAt,
        purchasePending: s.purchasePending,
      ),
    };
