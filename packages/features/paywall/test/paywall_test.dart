import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_paywall/feature_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const serverPricing = ProPricing(
  dayPriceCents: 10,
  monthPriceCents: 250,
  currency: 'USD',
  minDays: 1,
  maxDays: 24,
  fromServer: true,
);

class FakeService implements EntitlementService {
  FakeService(this.state);

  EntitlementState state;
  ProPricing prices = serverPricing;
  PurchaseOutcome nextOutcome = const PurchaseOutcome(
    PurchaseOutcomeKind.purchased,
  );
  LicenceRefreshOutcome nextRefresh = const LicenceRefreshOutcome(
    ok: false,
    message: "You're offline. Connect to the internet and try again.",
  );
  final purchased = <ProPurchase>[];
  int manageCalls = 0;
  int refreshCalls = 0;
  bool manageOpens = true;
  final _changes = StreamController<EntitlementState>.broadcast();

  @override
  EntitlementState get current => state;

  @override
  Stream<EntitlementState> get changes => _changes.stream;

  @override
  Future<ProPricing> pricing() async => prices;

  @override
  Future<PurchaseOutcome> purchase(ProPurchase request) async {
    purchased.add(request);
    if (nextOutcome.kind == PurchaseOutcomeKind.purchased) {
      final end = DateTime.now().add(Duration(days: request.days));
      state = request.plan == ProPlan.monthly
          ? const MonthlyEntitlement()
          : DayPassEntitlement(expiresAt: end);
      _changes.add(state);
    }
    return nextOutcome;
  }

  @override
  Future<LicenceRefreshOutcome> refreshLicence() async {
    refreshCalls++;
    return nextRefresh;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<bool> openManageSubscription() async {
    manageCalls++;
    return manageOpens;
  }
}

const _expired = ExpiredEntitlement(reason: LapseReason.trialEnded);

void main() {
  late FakeService service;
  late List<Object?> popped;

  Future<void> pump(
    WidgetTester tester, {
    String start = '/open',
    // These screens exist only in the paid modes; the default build is
    // free with ads (ADR-0013).
    MonetizationMode mode = MonetizationMode.licence,
  }) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    popped = [];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () async => popped.add(
                await context.push<bool>(
                  Routes.paywall(feature: ProFeature.kits),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: Routes.privacy,
          builder: (_, _) => const Scaffold(body: Text('Privacy page')),
        ),
        GoRoute(
          path: '/tools/kits',
          builder: (_, _) => const Scaffold(body: Text('Kits page')),
        ),
        ...paywallRoutes(),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monetizationModeProvider.overrideWithValue(mode),
          entitlementServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (start == '/open') {
      await tester.tap(find.text('open'));
    } else {
      router.go(start);
    }
    await tester.pumpAndSettle();
  }

  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('day-pass-total'))).data!;

  group('free build with ads: the paywall routes are closed', () {
    testWidgets('a pushed paywall pops straight back, reporting "allowed"', (
      tester,
    ) async {
      service = FakeService(_expired);
      await pump(tester, mode: MonetizationMode.ads);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.textContaining('IDSnap Pro'), findsNothing);
      expect(popped, [true]);
      expect(service.purchased, isEmpty);
    });

    for (final location in [
      '/paywall',
      Routes.paywall(feature: ProFeature.scan, from: '/tools/kits'),
      Routes.subscription,
      Routes.subscriptionTerms,
    ]) {
      testWidgets('opened directly, $location goes Home and shows nothing '
          'to buy', (tester) async {
        service = FakeService(_expired);
        await pump(tester, start: location, mode: MonetizationMode.ads);
        expect(find.text('open'), findsOneWidget);
        expect(find.byType(PaywallScreen), findsNothing);
        expect(find.byType(SubscriptionScreen), findsNothing);
        expect(find.byType(SubscriptionTermsScreen), findsNothing);
        expect(find.textContaining('month'), findsNothing);
        expect(service.refreshCalls, 0);
      });
    }

    test('the free state has an honest sentence too', () {
      final (title, detail) = describeSubscription(
        const FreeEntitlement(),
        DateTime(2026, 10, 7),
      );
      expect(title, 'IDSnap is free');
      expect(detail, contains('Every feature is unlocked'));
      expect(detail, contains('ads'));
    });
  });

  group('paywall', () {
    testWidgets('two plans, server prices, monthly recommended, no lifetime', (
      tester,
    ) async {
      service = FakeService(_expired);
      await pump(tester);
      expect(find.text('Application kits is part of IDSnap Pro'), findsOne);
      expect(find.text('Your free day has ended.'), findsOneWidget);
      expect(find.text(r'$2.50/month'), findsOneWidget);
      expect(find.text(r'$0.10/day'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.textContaining('Lifetime'), findsNothing);
      expect(find.textContaining('approximate'), findsNothing);
      expect(find.text(r'Subscribe for $2.50/month'), findsOneWidget);
      expect(find.text('Refresh licence'), findsOneWidget);
    });

    testWidgets('fallback prices are labelled approximate', (tester) async {
      service = FakeService(_expired)..prices = fallbackPricing;
      await pump(tester);
      expect(find.textContaining('Prices are approximate'), findsOneWidget);
    });

    testWidgets('day stepper and presets update the total', (tester) async {
      service = FakeService(_expired);
      await pump(tester);
      await tester.tap(find.text('Day pass'));
      await tester.pumpAndSettle();
      expect(total(tester), r'1 day · $0.10');
      await tester.tap(find.text('7 days'));
      await tester.pump();
      expect(total(tester), r'7 days · $0.70');
      await tester.tap(find.byTooltip('One day more'));
      await tester.pump();
      await tester.pump();
      expect(total(tester), r'8 days · $0.80');
      await tester.tap(find.byTooltip('One day less'));
      await tester.pump();
      await tester.tap(find.byTooltip('One day less'));
      await tester.pump();
      await tester.pump();
      expect(total(tester), r'6 days · $0.60');
      expect(find.text(r'Pay $0.60 for 6 days'), findsOneWidget);
    });

    testWidgets('stepper stops at the server limits', (tester) async {
      service = FakeService(_expired);
      await pump(tester);
      await tester.tap(find.text('Day pass'));
      await tester.pumpAndSettle();
      final less = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_rounded),
      );
      expect(less.onPressed, isNull, reason: 'at MIN_DAYS');
      for (var i = 0; i < 30; i++) {
        await tester.tap(find.byTooltip('One day more'));
        await tester.pump();
      }
      await tester.pump();
      expect(total(tester), r'24 days · $2.40');
    });

    testWidgets('nudges to monthly once days cost as much', (tester) async {
      service = FakeService(_expired)
        ..prices = const ProPricing(
          dayPriceCents: 10,
          monthPriceCents: 250,
          currency: 'USD',
          minDays: 1,
          maxDays: 30,
          fromServer: true,
        );
      await pump(tester);
      await tester.tap(find.text('Day pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 days'));
      await tester.pump();
      for (var i = 0; i < 17; i++) {
        await tester.tap(find.byTooltip('One day more'));
        await tester.pump();
      }
      await tester.pump();
      expect(total(tester), r'24 days · $2.40');
      expect(find.text('Switch to monthly'), findsNothing);
      await tester.tap(find.byTooltip('One day more'));
      await tester.pump();
      await tester.pump();
      expect(total(tester), r'25 days · $2.50');
      expect(find.textContaining('The monthly plan is'), findsOneWidget);
      await tester.tap(find.text('Switch to monthly'));
      await tester.pumpAndSettle();
      expect(find.text(r'Subscribe for $2.50/month'), findsOneWidget);
    });

    testWidgets('buying a day pass sends the days and pops true', (
      tester,
    ) async {
      service = FakeService(_expired);
      await pump(tester);
      await tester.tap(find.text('Day pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 days'));
      await tester.pump();
      await tester.tap(find.text(r'Pay $0.30 for 3 days'));
      await tester.pumpAndSettle();
      expect(service.purchased.single.plan, ProPlan.dayPass);
      expect(service.purchased.single.days, 3);
      expect(popped, [true]);
    });

    testWidgets('pending payment explains and stays open', (tester) async {
      service = FakeService(_expired)
        ..nextOutcome = const PurchaseOutcome(PurchaseOutcomeKind.pending);
      await pump(tester);
      await tester.tap(find.text(r'Subscribe for $2.50/month'));
      await tester.pumpAndSettle();
      expect(find.textContaining('payment confirmation'), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('offline purchase: clear message, nothing charged', (
      tester,
    ) async {
      service = FakeService(_expired)
        ..nextOutcome = const PurchaseOutcome(
          PurchaseOutcomeKind.unavailable,
          message: 'Connect to the internet to pay. You were not charged.',
        );
      await pump(tester);
      await tester.tap(find.text(r'Subscribe for $2.50/month'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You were not charged'), findsOneWidget);
    });

    testWidgets('never activated: connect-once card with retry', (
      tester,
    ) async {
      service = FakeService(
        const ExpiredEntitlement(reason: LapseReason.notActivated),
      );
      await pump(tester);
      expect(
        find.textContaining('Connect to the internet once to start your free'),
        findsWidgets,
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(service.refreshCalls, 1);
      expect(find.textContaining("You're offline"), findsOneWidget);
    });

    testWidgets('closing returns false', (tester) async {
      service = FakeService(_expired);
      await pump(tester);
      await tester.tap(find.byTooltip('Not now'));
      await tester.pumpAndSettle();
      expect(popped, [false]);
    });

    testWidgets('router backstop: after paying, continues to the tool', (
      tester,
    ) async {
      service = FakeService(_expired);
      await pump(
        tester,
        start: Routes.paywall(feature: ProFeature.kits, from: '/tools/kits'),
      );
      await tester.tap(find.text(r'Subscribe for $2.50/month'));
      await tester.pumpAndSettle();
      expect(find.text('Kits page'), findsOneWidget);
    });

    testWidgets('terms are local and describe the licence model', (
      tester,
    ) async {
      service = FakeService(_expired);
      await pump(tester);
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription terms'), findsOneWidget);
      expect(find.text('Free day'), findsOneWidget);
      expect(find.textContaining('180 Pay'), findsWidgets);
      expect(find.textContaining('Google Play'), findsNothing);
      expect(find.textContaining('no servers'), findsNothing);
    });

    testWidgets('clock set back: honest message', (tester) async {
      service = FakeService(
        const ExpiredEntitlement(reason: LapseReason.clockTampered),
      );
      await pump(tester);
      expect(find.textContaining('Set the correct date and time'), findsOne);
    });
  });

  group('subscription screen', () {
    testWidgets('free day: hours left and plans', (tester) async {
      service = FakeService(
        TrialEntitlement(
          endsAt: DateTime.now().add(const Duration(hours: 4, minutes: 30)),
        ),
      );
      await pump(tester, start: Routes.subscription);
      expect(find.text('Free day — ends in 5 h'), findsOneWidget);
      expect(find.text('See IDSnap Pro plans'), findsOneWidget);
      expect(find.text('Manage or cancel monthly plan'), findsNothing);
    });

    testWidgets('day pass: expiry, add days', (tester) async {
      service = FakeService(
        DayPassEntitlement(
          expiresAt: DateTime.now().add(const Duration(hours: 30)),
        ),
      );
      await pump(tester, start: Routes.subscription);
      expect(find.text('Day pass — ends in 30 h'), findsOneWidget);
      expect(find.text('Add days or go monthly'), findsOneWidget);
    });

    testWidgets('monthly: renewal date, manage opens the portal', (
      tester,
    ) async {
      service = FakeService(
        MonthlyEntitlement(renewsAt: DateTime(2026, 11, 1, 12)),
      );
      await pump(tester, start: Routes.subscription);
      expect(find.text('Monthly plan'), findsOneWidget);
      expect(find.text('Renews on 1 Nov 2026.'), findsOneWidget);
      expect(find.text('See IDSnap Pro plans'), findsNothing);
      await tester.tap(find.text('Manage or cancel monthly plan'));
      await tester.pumpAndSettle();
      expect(service.manageCalls, 1);
    });

    testWidgets('portal unavailable: explains how to cancel', (tester) async {
      service = FakeService(
        MonthlyEntitlement(renewsAt: DateTime(2026, 11, 1, 12)),
      )..manageOpens = false;
      await pump(tester, start: Routes.subscription);
      await tester.tap(find.text('Manage or cancel monthly plan'));
      await tester.pump();
      expect(find.textContaining("Couldn't open the 180 Pay"), findsOneWidget);
    });

    testWidgets('cancelled monthly says when access ends', (tester) async {
      service = FakeService(
        MonthlyEntitlement(
          renewsAt: DateTime(2026, 11, 1, 12),
          willRenew: false,
        ),
      );
      await pump(tester, start: Routes.subscription);
      expect(
        find.text('Cancelled — everything stays unlocked until 1 Nov 2026.'),
        findsOneWidget,
      );
    });

    testWidgets('refresh licence reports the result', (tester) async {
      service = FakeService(_expired)
        ..nextRefresh = const LicenceRefreshOutcome(ok: true);
      await pump(tester, start: Routes.subscription);
      await tester.tap(find.text('Refresh licence'));
      await tester.pump();
      expect(service.refreshCalls, 1);
      expect(find.text('Licence refreshed.'), findsOneWidget);
    });

    testWidgets('debug simulation switches the plan', (tester) async {
      service = FakeService(const MonthlyEntitlement());
      await pump(tester, start: Routes.subscription);
      await tester.scrollUntilVisible(find.text('offlineNeverRegistered'), 200);
      await tester.tap(find.text('offlineNeverRegistered'));
      await tester.pumpAndSettle();
      expect(find.text('Not activated yet'), findsOneWidget);
    });

    test('describe covers every state', () {
      final now = DateTime(2026, 10, 6, 12);
      for (final s in [
        TrialEntitlement(endsAt: now.add(const Duration(hours: 5))),
        DayPassEntitlement(expiresAt: now.add(const Duration(days: 2))),
        const MonthlyEntitlement(inGracePeriod: true),
        const MonthlyEntitlement(),
        for (final r in LapseReason.values) ExpiredEntitlement(reason: r),
      ]) {
        final (title, detail) = describeSubscription(s, now);
        expect(title, isNotEmpty);
        expect(detail, isNotEmpty);
      }
    });
  });
}
