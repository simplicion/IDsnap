import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Everything in this file is about the PAID modes, so every container
// runs in licence mode. The free build is covered by
// monetization_test.dart.
final _licenceMode = monetizationModeProvider.overrideWithValue(
  MonetizationMode.licence,
);

const _expired = ExpiredEntitlement(reason: LapseReason.trialEnded);
final _trial = TrialEntitlement(endsAt: DateTime.utc(2099));

class _MutableService extends StaticEntitlementService {
  _MutableService(this.value);

  EntitlementState value;
  final controller = StreamController<EntitlementState>.broadcast();

  @override
  EntitlementState get current => value;

  @override
  Stream<EntitlementState> get changes => controller.stream;
}

void main() {
  group('policy map', () {
    test('covers every feature', () {
      expect(featurePolicy.keys.toSet(), ProFeature.values.toSet());
    });

    test('authenticator and data export are never gated', () {
      for (final f in [
        ProFeature.authenticator,
        ProFeature.exportAllData,
        ProFeature.viewDocuments,
        ProFeature.shareExport,
        ProFeature.browseFolders,
        ProFeature.appLockUnlock,
        ProFeature.readSecureNotes,
      ]) {
        expect(requiresPro(f), isFalse, reason: f.name);
        expect(canUse(f, _expired), isTrue, reason: f.name);
      }
    });

    test('creating and processing documents is Pro after the free day', () {
      for (final f in [
        ProFeature.scan,
        ProFeature.idCard,
        ProFeature.passportPhoto,
        ProFeature.kits,
        ProFeature.ocr,
        ProFeature.pdfTools,
        ProFeature.signature,
        ProFeature.convert,
        ProFeature.protectFile,
        ProFeature.qrTools,
        ProFeature.secureNotes,
      ]) {
        expect(canUse(f, _expired), isFalse, reason: f.name);
        expect(canUse(f, _trial), isTrue);
        expect(canUse(f, const MonthlyEntitlement()), isTrue);
        expect(
          canUse(f, DayPassEntitlement(expiresAt: DateTime.utc(2099))),
          isTrue,
        );
        expect(
          canUse(f, const ExpiredEntitlement(reason: LapseReason.notActivated)),
          isFalse,
        );
      }
    });
  });

  group('router backstop', () {
    test('maps locations to features', () {
      ProFeature? f(String l) => proFeatureForLocation(Uri.parse(l));
      expect(f(Routes.scan()), ProFeature.scan);
      expect(f(Routes.scan(source: ScanSource.resume)), isNull);
      expect(f(Routes.scanReview), isNull);
      expect(f(Routes.scanSave), isNull);
      expect(f(Routes.idCard()), ProFeature.idCard);
      expect(f(Routes.passportPhotoCamera), ProFeature.passportPhoto);
      expect(f(Routes.kit('us-visa')), ProFeature.kits);
      expect(f(Routes.tool(ToolId.ocr, docId: 'x')), ProFeature.ocr);
      expect(f(Routes.tool(ToolId.merge)), ProFeature.pdfTools);
      expect(f(Routes.tool(ToolId.photoCrop)), ProFeature.imageTools);
      expect(f(Routes.tool(ToolId.signPdf)), ProFeature.signature);
      expect(f(Routes.tool(ToolId.protectFile)), ProFeature.protectFile);
      // Unlocking the user's own PDF is never paywalled.
      expect(f(Routes.tool(ToolId.removePdfPassword)), isNull);
      // QR: scanning and history are free, the generator is Pro.
      expect(f(Routes.qrScanner), isNull);
      expect(f(Routes.qrHistory), isNull);
      expect(f(Routes.qrGenerate), ProFeature.qrTools);
      expect(f(Routes.convert('pdf-to-docx')), ProFeature.convert);
      for (final free in [
        Routes.home,
        Routes.files,
        Routes.document('d'),
        Routes.tools,
        Routes.authenticator,
        Routes.authenticatorAdd,
        Routes.settings,
        Routes.dataExport,
        Routes.security,
        Routes.subscription,
        Routes.paywall(),
      ]) {
        expect(f(free), isNull, reason: free);
      }
    });

    test('redirects locked locations to the paywall with a return path', () {
      final uri = Uri.parse(Routes.tool(ToolId.merge));
      expect(proRedirect(uri, _trial), isNull);
      final target = Uri.parse(proRedirect(uri, _expired)!);
      expect(target.path, '/paywall');
      expect(target.queryParameters['feature'], 'pdfTools');
      expect(target.queryParameters['from'], '/tools/merge');
    });
  });

  group('providers', () {
    test('unwired billing unlocks everything', () {
      final c = ProviderContainer(overrides: [_licenceMode]);
      addTearDown(c.dispose);
      expect(c.read(canUseProvider(ProFeature.scan)), isTrue);
    });

    test('follows service changes', () async {
      final service = _MutableService(_trial);
      final c = ProviderContainer(
        overrides: [
          _licenceMode,
          entitlementServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(canUseProvider(ProFeature.ocr)), isTrue);
      service.controller.add(_expired);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(canUseProvider(ProFeature.ocr)), isFalse);
      expect(c.read(canUseProvider(ProFeature.authenticator)), isTrue);
    });

    test('debug simulation overrides the service (not in release)', () {
      final c = ProviderContainer(overrides: [_licenceMode]);
      addTearDown(c.dispose);
      c
          .read(entitlementSimulationProvider.notifier)
          .select(EntitlementSimulation.expired);
      expect(c.read(entitlementProvider), isA<ExpiredEntitlement>());
      c.read(entitlementSimulationProvider.notifier).select(null);
      expect(c.read(entitlementProvider), isA<MonthlyEntitlement>());
    });
  });

  group('ensurePro', () {
    Future<(ProviderContainer, List<String>)> pump(
      WidgetTester tester,
      EntitlementState state, {
      bool buyOnPaywall = false,
    }) async {
      final service = _MutableService(state);
      final opened = <String>[];
      final container = ProviderContainer(
        overrides: [
          _licenceMode,
          entitlementServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        if (await ensurePro(context, ref, ProFeature.ocr)) {
                          opened.add('ocr');
                        }
                      },
                      child: const Text('Locked tool'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await ensurePro(
                          context,
                          ref,
                          ProFeature.authenticator,
                        )) {
                          opened.add('authenticator');
                        }
                      },
                      child: const Text('Free action'),
                    ),
                    const ProBadge(ProFeature.ocr),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/paywall',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () {
                  if (buyOnPaywall) {
                    service.value = const MonthlyEntitlement();
                    service.controller.add(service.value);
                  }
                  context.pop(buyOnPaywall);
                },
                child: Text('Paywall ${state.uri.queryParameters['feature']}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      return (container, opened);
    }

    testWidgets('a locked tool opens the paywall; closing keeps it locked', (
      tester,
    ) async {
      final (_, opened) = await pump(tester, _expired);
      expect(find.text('PRO'), findsOneWidget);
      await tester.tap(find.text('Locked tool'));
      await tester.pumpAndSettle();
      expect(find.text('Paywall ocr'), findsOneWidget);
      await tester.tap(find.text('Paywall ocr'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('buying on the paywall continues to the tool', (tester) async {
      final (_, opened) = await pump(tester, _expired, buyOnPaywall: true);
      await tester.tap(find.text('Locked tool'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paywall ocr'));
      await tester.pumpAndSettle();
      expect(opened, ['ocr']);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('a free action never opens the paywall', (tester) async {
      final (_, opened) = await pump(tester, _expired);
      await tester.tap(find.text('Free action'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Paywall'), findsNothing);
      expect(opened, ['authenticator']);
    });

    testWidgets('during the free day nothing is locked', (tester) async {
      final (_, opened) = await pump(tester, _trial);
      expect(find.text('PRO'), findsNothing);
      await tester.tap(find.text('Locked tool'));
      await tester.pumpAndSettle();
      expect(opened, ['ocr']);
    });
  });

  group('pricing and copy helpers', () {
    test('day-pass totals and the monthly nudge', () {
      const p = fallbackPricing;
      expect(p.format(p.dayPassCents(7)), r'$0.70');
      expect(p.format(p.monthPriceCents), r'$2.50');
      expect(p.monthlyIsCheaper(24), isFalse);
      expect(p.monthlyIsCheaper(25), isTrue);
      expect(
        const ProPricing(
          dayPriceCents: 10,
          monthPriceCents: 250,
          currency: 'CHF',
          minDays: 1,
          maxDays: 24,
          fromServer: true,
        ).format(250),
        '2.50 CHF',
      );
    });

    test('time left', () {
      final now = DateTime.utc(2026, 10, 6, 12);
      String left(Duration d) => formatTimeLeft(now.add(d), now);
      expect(left(const Duration(hours: 5)), '5 h');
      expect(left(const Duration(hours: 4, minutes: 1)), '5 h');
      expect(left(const Duration(minutes: 45)), '45 min');
      expect(left(const Duration(days: 3, hours: 2)), '3 days 2 h');
      expect(left(const Duration(days: 3)), '3 days');
      expect(left(-const Duration(minutes: 1)), '0 min');
    });

    test('every simulation state is well formed', () {
      expect(
        EntitlementSimulation.offlineNeverRegistered.state,
        isA<ExpiredEntitlement>().having(
          (e) => e.reason,
          'reason',
          LapseReason.notActivated,
        ),
      );
      expect(EntitlementSimulation.dayPass.state.isEntitled, isTrue);
      expect(EntitlementSimulation.expired.state.isEntitled, isFalse);
    });
  });
}
