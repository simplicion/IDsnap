// Ads in the QR tool (ADR-0013), with the fake ads service: a banner on
// the generator, one native card in a long scan history, and nothing at
// all on the camera scanner or a code's result.
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fakes.dart';

final _banner = find.byKey(AdBannerSlot.openKey);
final _native = find.byKey(AdNativeSlot.openKey);

QrHistoryState _history(int n) => QrHistoryState(
  entries: [
    for (var i = 1; i <= n; i++)
      QrHistoryEntry(
        id: '$i',
        raw: 'note $i',
        symbology: CodeSymbology.qr,
        kind: CodeKind.text,
        summary: 'note $i',
        scannedAt: DateTime(2026),
      ),
  ],
);

void main() {
  late FakeAdsService ads;

  Future<void> pump(
    WidgetTester tester, {
    required String location,
    int entries = 0,
    MonetizationMode mode = MonetizationMode.ads,
    double textScale = 1,
    Size size = const Size(400, 2400),
  }) async {
    final h = Harness(history: _history(entries));
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: location,
      routes: [
        GoRoute(
          path: Routes.tools,
          builder: (context, state) => const Scaffold(body: Text('Tools')),
          routes: qrRoutes(rootKey),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          monetizationModeProvider.overrideWithValue(mode),
          adsServiceProvider.overrideWithValue(ads),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  setUp(() => ads = FakeAdsService());

  group('scan history', () {
    testWidgets('one native card, after the 5th entry', (tester) async {
      await pump(tester, location: Routes.qrHistory, entries: 8);
      expect(_native, findsOneWidget);
      expect(find.byType(AdNativeSlot), findsOneWidget);
      expect(ads.nativeSizes, [AdNativeSize.small]);
      final card = tester.getRect(_native);
      expect(
        card.top - tester.getRect(find.text('note 5')).bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
      expect(card.top, greaterThan(tester.getRect(find.text('note 5')).top));
      expect(card.bottom, lessThan(tester.getRect(find.text('note 6')).top));
      // No banner on this screen: never two ad areas competing here.
      expect(_banner, findsNothing);
    });

    for (final n in [0, 1, 5]) {
      testWidgets('a list of $n entries has no ad', (tester) async {
        await pump(tester, location: Routes.qrHistory, entries: n);
        expect(find.byType(AdNativeSlot), findsNothing);
        expect(_native, findsNothing);
        expect(ads.adActivity, 0);
      });
    }

    testWidgets('no native ad loaded: nothing shown, no gap', (tester) async {
      ads.nativeLoaded = false;
      await pump(tester, location: Routes.qrHistory, entries: 8);
      expect(_native, findsNothing);
      expect(tester.getSize(find.byType(AdNativeSlot)).height, 0);
    });

    testWidgets('no overflow at 2x text size with the native card', (
      tester,
    ) async {
      await pump(
        tester,
        location: Routes.qrHistory,
        entries: 8,
        textScale: 2,
        size: const Size(320, 3200),
      );
      expect(_native, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('paid builds: no ad', (tester) async {
      await pump(
        tester,
        location: Routes.qrHistory,
        entries: 8,
        mode: MonetizationMode.licence,
      );
      expect(_native, findsNothing);
      expect(ads.adActivity, 0);
    });
  });

  testWidgets('QR generator: a banner at the bottom, hidden while typing', (
    tester,
  ) async {
    await pump(tester, location: Routes.qrGenerate, size: const Size(400, 900));
    expect(_banner, findsOneWidget);
    expect(tester.getRect(_banner).bottom, 900);
    expect(_native, findsNothing);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    expect(_banner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the camera scanner has no ad of any kind', (tester) async {
    await pump(tester, location: Routes.qrScanner);
    expect(find.text('Scan QR / barcode'), findsOneWidget);
    expect(find.byType(AdBannerSlot), findsNothing);
    expect(find.byType(AdNativeSlot), findsNothing);
    expect(ads.adActivity, 0);
    expect(ads.initializeCalls, 0);
  });
}
