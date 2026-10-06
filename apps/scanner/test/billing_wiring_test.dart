import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_scanner/billing.dart';
import 'package:engine_billing/engine_billing.dart' as billing;
import 'package:flutter_test/flutter_test.dart';

class _OfflineClient implements billing.LicenceClient {
  static const _offline = billing.LicenceClientException(
    billing.LicenceFailureKind.offline,
  );

  @override
  Future<billing.LicenceResponse> register({
    required String deviceHash,
    required String platform,
    required String appVersion,
  }) async => throw _offline;

  @override
  Future<billing.LicenceResponse> entitlement(String deviceHash) async =>
      throw _offline;

  @override
  Future<billing.ServerPricing> config() async => throw _offline;

  @override
  Future<billing.CheckoutResponse> checkout({
    required String deviceHash,
    required billing.CheckoutProduct product,
    int? days,
  }) async => throw _offline;

  @override
  Future<Uri> portal(String deviceHash) async => throw _offline;
}

class _Store extends billing.UnavailableBillingStore {
  _Store({this.owned = const []});

  final List<billing.StorePurchase> owned;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<billing.StorePurchase>?> queryOwned() async => owned;
}

void main() {
  group('free with ads (IDSNAP_MONETIZATION=ads, the default)', () {
    test('the default build is the free one', () {
      expect(resolveMonetizationMode(), MonetizationMode.ads);
      expect(resolveMonetizationMode('licence'), MonetizationMode.licence);
      expect(resolveMonetizationMode('license'), MonetizationMode.licence);
      expect(resolveMonetizationMode('store'), MonetizationMode.store);
      expect(
        () => resolveMonetizationMode('freemium'),
        throwsA(isA<MonetizationConfigError>()),
      );
    });

    test(
      'everything is unlocked for good, with no licence client, no '
      'device registration and no licence defines, even in release',
      () async {
        final service = await startBilling(
          mode: MonetizationMode.ads,
          // A release build with NO licence defines must start.
          release: true,
          // Fails the test if anything builds a licence HTTP client.
          clientFactory: (_) =>
              fail('a licence client was constructed in ads mode'),
        );
        expect(service, isA<FreeEntitlementService>());
        final state = service.current;
        expect(state, isA<FreeEntitlement>());
        expect(state.isEntitled, isTrue);
        expect(state.accessEndsAt, isNull);
        for (final feature in ProFeature.values) {
          expect(canUse(feature, state), isTrue, reason: feature.name);
        }
        // Nothing to refresh, buy or manage; none of it touches a network.
        await service.refresh();
        expect((await service.refreshLicence()).ok, isTrue);
        expect(
          (await service.purchase(const ProPurchase.monthly())).kind,
          PurchaseOutcomeKind.unavailable,
        );
        expect(await service.openManageSubscription(), isFalse);
      },
    );

    test('the router backstop never sends anyone to the paywall', () {
      for (final t in ToolId.values) {
        expect(
          proRedirect(Uri.parse(Routes.tool(t)), const FreeEntitlement()),
          isNull,
          reason: t.name,
        );
      }
      for (final location in [
        Routes.scan(),
        Routes.idCard(),
        Routes.passportPhotoCamera,
        Routes.qrGenerate,
        Routes.kits,
      ]) {
        expect(
          proRedirect(Uri.parse(location), const FreeEntitlement()),
          isNull,
          reason: location,
        );
      }
    });

    test('licence mode does build its client through the factory', () async {
      var built = 0;
      await startBilling(
        mode: MonetizationMode.licence,
        clientFactory: (_) {
          built++;
          return _OfflineClient();
        },
        storage: billing.MemoryBillingStorage(),
        identity: billing.FixedDeviceIdentity('test-device'),
      );
      expect(built, 1);
    });
  });

  test('first launch offline: not activated, nothing unlocked', () async {
    final service = await startBilling(
      mode: MonetizationMode.licence,
      client: _OfflineClient(),
      storage: billing.MemoryBillingStorage(),
      identity: billing.FixedDeviceIdentity('test-device'),
    );
    final state = service.current;
    expect(
      state,
      isA<ExpiredEntitlement>().having(
        (e) => e.reason,
        'reason',
        LapseReason.notActivated,
      ),
    );
    expect(canUse(ProFeature.scan, state), isFalse);
    expect(canUse(ProFeature.viewDocuments, state), isTrue);
    expect((await service.pricing()).fromServer, isFalse);
    expect(
      (await service.purchase(const ProPurchase.dayPass(2))).kind,
      PurchaseOutcomeKind.unavailable,
    );
    final refreshed = await service.refreshLicence();
    expect(refreshed.ok, isFalse);
    expect(refreshed.message, contains('offline'));
  });

  test('licence-mode release builds refuse to start without the licence '
      'defines', () {
    expect(
      () => startBilling(
        mode: MonetizationMode.licence,
        client: _OfflineClient(),
        storage: billing.MemoryBillingStorage(),
        release: true,
      ),
      throwsA(isA<billing.LicenceConfigError>()),
    );
  });

  test('state mapping covers every licence status', () {
    final t = DateTime.utc(2026, 11);
    expect(
      toEntitlementState(
        billing.LicenceStatus(kind: billing.LicenceKind.trial, expiresAt: t),
      ),
      isA<TrialEntitlement>().having((e) => e.endsAt, 'endsAt', t),
    );
    expect(
      toEntitlementState(
        billing.LicenceStatus(kind: billing.LicenceKind.dayPass, expiresAt: t),
      ),
      isA<DayPassEntitlement>(),
    );
    expect(
      toEntitlementState(
        billing.LicenceStatus(
          kind: billing.LicenceKind.monthly,
          expiresAt: t.add(const Duration(days: 3)),
          paidUntil: t,
          willRenew: true,
          inGracePeriod: true,
        ),
      ),
      isA<MonthlyEntitlement>()
          .having((m) => m.renewsAt, 'renewsAt', t)
          .having((m) => m.inGracePeriod, 'grace', isTrue),
    );
    for (final (lapse, reason) in [
      (billing.LicenceLapse.trialEnded, LapseReason.trialEnded),
      (billing.LicenceLapse.dayPassEnded, LapseReason.dayPassEnded),
      (billing.LicenceLapse.monthlyEnded, LapseReason.subscriptionEnded),
      (billing.LicenceLapse.clockTampered, LapseReason.clockTampered),
      (billing.LicenceLapse.notActivated, LapseReason.notActivated),
    ]) {
      expect(
        toEntitlementState(
          billing.LicenceStatus(
            kind: billing.LicenceKind.expired,
            lapse: lapse,
          ),
        ),
        isA<ExpiredEntitlement>().having((e) => e.reason, 'reason', reason),
      );
    }
  });

  test(
    'store mode still compiles and maps (IDSNAP_MONETIZATION=store)',
    () async {
      final service = await startStoreBilling(
        store: _Store(
          owned: [
            billing.StorePurchase(
              productId: billing.BillingProducts.monthly,
              status: billing.StorePurchaseStatus.purchased,
            ),
          ],
        ),
        storage: billing.MemoryBillingStorage(),
      );
      await service.refresh();
      expect(service.current, isA<MonthlyEntitlement>());
      expect(
        (await service.purchase(const ProPurchase.dayPass(1))).kind,
        PurchaseOutcomeKind.unavailable,
      );
    },
  );

  test('router backstop: locked tools redirect, free areas never do', () {
    const expired = ExpiredEntitlement(reason: LapseReason.trialEnded);
    expect(
      proRedirect(Uri.parse(Routes.tool(ToolId.ocr, docId: 'd1')), expired),
      startsWith('/paywall'),
    );
    for (final free in [
      Routes.authenticator,
      Routes.authenticatorAdd,
      Routes.document('d1'),
      Routes.files,
      Routes.dataExport,
      Routes.subscription,
    ]) {
      expect(proRedirect(Uri.parse(free), expired), isNull, reason: free);
    }
  });
}
