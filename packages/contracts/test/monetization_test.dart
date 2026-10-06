// The mode switch (ADR-0013): free with ads by default; the paid modes
// behave as before and show no ads.
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _expired = ExpiredEntitlement(reason: LapseReason.trialEnded);

ProviderContainer _container(
  MonetizationMode mode, {
  EntitlementService service = const StaticEntitlementService(_expired),
}) {
  final c = ProviderContainer(
    overrides: [
      monetizationModeProvider.overrideWithValue(mode),
      entitlementServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('the build setting', () {
    test('ads is the default', () {
      expect(monetizationDefine, 'ads');
      expect(resolveMonetizationMode(), MonetizationMode.ads);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(monetizationModeProvider), MonetizationMode.ads);
    });

    test('ads | licence | store, and nothing else', () {
      expect(MonetizationMode.parse('ads'), MonetizationMode.ads);
      expect(MonetizationMode.parse(' Licence '), MonetizationMode.licence);
      expect(MonetizationMode.parse('license'), MonetizationMode.licence);
      expect(MonetizationMode.parse('store'), MonetizationMode.store);
      expect(MonetizationMode.parse(''), isNull);
      expect(MonetizationMode.parse('free'), isNull);
      expect(
        () => resolveMonetizationMode('paid'),
        throwsA(
          isA<MonetizationConfigError>().having(
            (e) => e.message,
            'message',
            contains('ads, licence or store'),
          ),
        ),
      );
    });

    test('only the ads mode is free and only it shows ads', () {
      expect(MonetizationMode.ads.isFree, isTrue);
      expect(MonetizationMode.ads.showsAds, isTrue);
      for (final paid in [MonetizationMode.licence, MonetizationMode.store]) {
        expect(paid.isFree, isFalse, reason: paid.name);
        expect(paid.showsAds, isFalse, reason: paid.name);
      }
    });

    test('each mode has its own true privacy sentence', () {
      expect(
        privacyLineFor(MonetizationMode.ads),
        'Your documents, IDs and codes never leave this phone. IDSnap is '
        'free and shows ads on a few screens; the ads are provided by '
        "Google, which may use your device's advertising ID.",
      );
      for (final paid in [MonetizationMode.licence, MonetizationMode.store]) {
        expect(privacyLineFor(paid), isNot(contains('ads')));
        expect(privacyLineFor(paid), contains('licence'));
      }
    });
  });

  group('ads mode: everything is unlocked for everyone', () {
    test('the state is FreeEntitlement whatever the service says', () {
      final c = _container(MonetizationMode.ads);
      final state = c.read(entitlementProvider);
      expect(state, isA<FreeEntitlement>());
      expect(state.isEntitled, isTrue);
      expect(state.accessEndsAt, isNull);
      expect(state.purchasePending, isFalse);
    });

    test('every ProFeature is usable', () {
      final c = _container(MonetizationMode.ads);
      for (final feature in ProFeature.values) {
        expect(c.read(canUseProvider(feature)), isTrue, reason: feature.name);
        expect(canUse(feature, const FreeEntitlement()), isTrue);
      }
    });

    test('a recheck or a debug simulation cannot lock anything', () {
      final c = _container(MonetizationMode.ads);
      c.read(entitlementProvider.notifier).recheck();
      c
          .read(entitlementSimulationProvider.notifier)
          .select(EntitlementSimulation.expired);
      c.read(entitlementProvider.notifier).recheck();
      expect(c.read(entitlementProvider), isA<FreeEntitlement>());
      expect(c.read(canUseProvider(ProFeature.scan)), isTrue);
    });

    test(
      'FreeEntitlementService: unlocked, nothing to buy, no server',
      () async {
        const service = FreeEntitlementService();
        expect(service.current, isA<FreeEntitlement>());
        expect(await service.changes.isEmpty, isTrue);
        expect(
          (await service.purchase(const ProPurchase.dayPass(3))).kind,
          PurchaseOutcomeKind.unavailable,
        );
        expect((await service.refreshLicence()).ok, isTrue);
        expect(await service.openManageSubscription(), isFalse);
        await service.refresh();
      },
    );

    test('the router backstop never redirects', () {
      for (final t in ToolId.values) {
        expect(
          proRedirect(Uri.parse(Routes.tool(t)), const FreeEntitlement()),
          isNull,
        );
      }
    });

    testWidgets('ensurePro returns true for every feature and never opens '
        'the paywall; no PRO badge is drawn', (tester) async {
      final opened = <String>[];
      final results = <ProFeature, bool>{};
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: ListView(
                  children: [
                    for (final f in ProFeature.values)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () async =>
                                results[f] = await ensurePro(context, ref, f),
                            child: Text(f.name),
                          ),
                          ProBadge(f),
                          Text(proBadgeLabel(ref, f) ?? 'no-badge-${f.name}'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/paywall',
            builder: (_, state) {
              opened.add(state.uri.toString());
              return const Scaffold(body: Text('PAYWALL'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monetizationModeProvider.overrideWithValue(MonetizationMode.ads),
            // Even a service that says "expired" locks nothing.
            entitlementServiceProvider.overrideWithValue(
              const StaticEntitlementService(_expired),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRO'), findsNothing);
      expect(find.text('Pro'), findsNothing);
      for (final f in ProFeature.values) {
        expect(find.text('no-badge-${f.name}'), findsOneWidget);
        await tester.tap(find.text(f.name));
        await tester.pumpAndSettle();
      }
      expect(results.keys.toSet(), ProFeature.values.toSet());
      expect(results.values.every((allowed) => allowed), isTrue);
      expect(opened, isEmpty);
      expect(find.text('PAYWALL'), findsNothing);
    });
  });

  group('licence and store modes work as before', () {
    for (final mode in [MonetizationMode.licence, MonetizationMode.store]) {
      test('${mode.name}: the service decides; Pro features lock', () {
        final c = _container(mode);
        expect(c.read(entitlementProvider), isA<ExpiredEntitlement>());
        expect(c.read(canUseProvider(ProFeature.scan)), isFalse);
        expect(c.read(canUseProvider(ProFeature.viewDocuments)), isTrue);
        expect(
          proRedirect(
            Uri.parse(Routes.tool(ToolId.ocr)),
            c.read(entitlementProvider),
          ),
          startsWith('/paywall'),
        );
      });

      test('${mode.name}: a paying user is unlocked', () {
        final c = _container(mode, service: const StaticEntitlementService());
        expect(c.read(entitlementProvider), isA<MonthlyEntitlement>());
        expect(c.read(canUseProvider(ProFeature.scan)), isTrue);
      });
    }
  });

  test('the no-op ads service does nothing at all', () async {
    const ads = NoopAdsService();
    await ads.initialize();
    expect(ads.canShowAds, isFalse);
    expect(ads.privacyOptionsRequired, isFalse);
    expect(ads.consentStatus, AdConsentStatus.unknown);
    expect(await ads.resolveBannerHeight(360), isNull);
    expect(
      ads.takeNative(
        AdNativeSize.small,
        const AdNativeStyle(
          background: Color(0xFFFFFFFF),
          primaryText: Color(0xFF000000),
          secondaryText: Color(0xFF000000),
          buttonBackground: Color(0xFF000000),
          buttonText: Color(0xFFFFFFFF),
        ),
      ),
      isNull,
    );
    expect(await ads.maybeShowInterstitial(), isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(adsServiceProvider), isA<NoopAdsService>());
  });
}
