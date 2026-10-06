import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A screen that tries to show every kind of ad. Whether any appears is up
/// to the placement policy for the route it is on.
class _Page extends ConsumerWidget {
  const _Page(this.name, {this.native});

  final String name;
  final AdNativePlacement? native;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(name)),
    bottomNavigationBar: const AdBannerSlot(),
    body: ListView(
      children: [
        const TextField(),
        Text('content of $name'),
        if (native != null) AdNativeSlot(placement: native!),
        const Text('more content'),
        TextButton(
          onPressed: () =>
              maybeShowResultInterstitial(ref, routeLocationOf(context)),
          child: const Text('leave result'),
        ),
      ],
    ),
  );
}

GoRouter _router({String initial = '/'}) => GoRouter(
  initialLocation: initial,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: shell.goBranch,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.badge), label: 'Vault'),
            NavigationDestination(icon: Icon(Icons.build), label: 'Tools'),
          ],
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, _) =>
                  const _Page('home', native: AdNativePlacement.home),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.files,
              builder: (_, _) =>
                  const _Page('vault', native: AdNativePlacement.home),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.tools,
              builder: (_, _) =>
                  const _Page('tools', native: AdNativePlacement.toolsList),
            ),
          ],
        ),
      ],
    ),
    for (final (path, native) in [
      (Routes.tool(ToolId.merge), AdNativePlacement.toolResult),
      (Routes.tool(ToolId.protectFile), AdNativePlacement.toolResult),
      (Routes.tool(ToolId.signPdf), AdNativePlacement.toolResult),
      (Routes.settings, AdNativePlacement.toolsList),
      (Routes.notes, AdNativePlacement.home),
      (Routes.authenticatorAdd, AdNativePlacement.home),
      (Routes.document('d1'), AdNativePlacement.toolResult),
      (Routes.scanReview, AdNativePlacement.toolResult),
      (Routes.qrHistory, AdNativePlacement.qrHistory),
    ])
      GoRoute(
        path: path,
        builder: (_, _) => _Page(path, native: native),
      ),
  ],
);

final _banner = find.byKey(AdBannerSlot.openKey);
final _native = find.byKey(AdNativeSlot.openKey);

void main() {
  late FakeAdsService ads;
  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester, {
    MonetizationMode mode = MonetizationMode.ads,
    String initial = '/',
    double textScale = 1,
    bool tallView = true,
    Widget Function(Widget child)? wrap,
  }) async {
    router = _router(initial: initial);
    addTearDown(router.dispose);
    if (!tallView) {
      tester.view.physicalSize = const Size(320, 568);
    } else {
      tester.view.physicalSize = const Size(400, 1400);
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: wrap?.call(child!) ?? child!,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monetizationModeProvider.overrideWithValue(mode),
          adsServiceProvider.overrideWithValue(ads),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => ads = FakeAdsService());

  group('banner slot', () {
    testWidgets('opens on Home, above the navigation bar, labelled for '
        'screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(_banner, findsOneWidget);
      expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
      expect(tester.getSize(_banner).height, 60);
      expect(
        find.ancestor(
          of: _banner,
          matching: find.bySemanticsLabel('Advertisement'),
        ),
        findsOneWidget,
      );
      // Above the navigation bar, covering nothing.
      expect(
        tester.getRect(_banner).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );
      expect(ads.initializeCalls, greaterThan(0));
      handle.dispose();
    });

    testWidgets('only the tab in front has a banner; a tab without '
        'permission has none', (tester) async {
      await pumpApp(tester);
      expect(_banner, findsOneWidget);

      await tester.tap(find.text('Vault'));
      await tester.pumpAndSettle();
      expect(find.text('content of vault'), findsOneWidget);
      expect(_banner, findsNothing);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(Scaffold, 'content of tools'),
          matching: _banner,
        ),
        findsOneWidget,
      );
    });

    testWidgets("a screen pushed over a tab closes the tab's banner", (
      tester,
    ) async {
      await pumpApp(tester);
      expect(_banner, findsOneWidget);
      router.push(Routes.settings).ignore();
      await tester.pumpAndSettle();
      expect(find.text('content of /settings'), findsOneWidget);
      expect(_banner, findsNothing);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
    });

    for (final location in [
      Routes.settings,
      Routes.notes,
      Routes.authenticatorAdd,
      Routes.document('d1'),
      Routes.scanReview,
      Routes.tool(ToolId.protectFile),
      Routes.tool(ToolId.signPdf),
      Routes.qrHistory,
    ]) {
      testWidgets('an AdBannerSlot placed on $location shows nothing and '
          'requests nothing', (tester) async {
        await pumpApp(tester, initial: location);
        expect(find.text('content of $location'), findsOneWidget);
        expect(find.byType(AdBannerSlot), findsOneWidget);
        expect(_banner, findsNothing);
        expect(ads.bannersBuilt, 0);
      });
    }

    testWidgets('allowed on a tool form, with a gap when asked', (
      tester,
    ) async {
      await pumpApp(tester, initial: Routes.tool(ToolId.merge));
      expect(_banner, findsOneWidget);
    });

    testWidgets('hidden while the keyboard is open, back when it closes', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(_banner, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
    });

    testWidgets('no banner until consent is resolved; then it opens', (
      tester,
    ) async {
      ads.ready = false;
      await pumpApp(tester);
      expect(_banner, findsNothing);
      expect(ads.bannersBuilt, 0);
      expect(ads.initializeCalls, greaterThan(0));
      ads.becomeReady();
      await tester.pumpAndSettle();
      expect(_banner, findsOneWidget);
    });

    testWidgets('no banner available (offline): zero height, no gap', (
      tester,
    ) async {
      ads.bannerHeight = null;
      await pumpApp(tester);
      expect(_banner, findsNothing);
      expect(tester.getSize(find.byType(AdBannerSlot).first).height, 0);
    });

    testWidgets('never while the app is locked (tickers off underneath)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        wrap: (child) => TickerMode(enabled: false, child: child),
      );
      expect(_banner, findsNothing);
      expect(ads.adActivity, 0);
      expect(ads.initializeCalls, 0);
    });

    testWidgets('paid builds: no banner, no ad code at all', (tester) async {
      for (final mode in [MonetizationMode.licence, MonetizationMode.store]) {
        ads = FakeAdsService();
        await pumpApp(tester, mode: mode);
        expect(_banner, findsNothing, reason: mode.name);
        expect(_native, findsNothing, reason: mode.name);
        await tester.tap(find.text('leave result'));
        await tester.pumpAndSettle();
        expect(ads.adActivity, 0, reason: mode.name);
        expect(ads.initializeCalls, 0, reason: mode.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('outside a router nothing is ever shown', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monetizationModeProvider.overrideWithValue(MonetizationMode.ads),
            adsServiceProvider.overrideWithValue(ads),
          ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: AdBannerSlot(),
              body: AdNativeSlot(placement: AdNativePlacement.home),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_banner, findsNothing);
      expect(_native, findsNothing);
      expect(ads.adActivity, 0);
    });
  });

  group('native slot', () {
    testWidgets('shows a loaded ad in a labelled card, set apart from the '
        'content around it', (tester) async {
      await pumpApp(tester);
      expect(_native, findsOneWidget);
      expect(find.byKey(FakeAdsService.nativeKey), findsOneWidget);
      expect(ads.nativeSizes, [AdNativeSize.small]);
      // Labelled: an "Ad" badge and the word Advertisement.
      expect(
        find.descendant(of: _native, matching: find.text('Ad')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _native, matching: find.text('Advertisement')),
        findsOneWidget,
      );
      // A different surface colour from the page, with an outline.
      final card = tester.widget<Material>(_native);
      final scheme = Theme.of(tester.element(_native)).colorScheme;
      expect(card.color, isNot(scheme.surface));
      expect(
        (card.shape! as RoundedRectangleBorder).side.width,
        greaterThan(0),
      );
      // Space above and below: no tappable row touches the card.
      final rect = tester.getRect(_native);
      expect(
        rect.top - tester.getRect(find.text('content of home')).bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
      expect(
        tester.getRect(find.text('more content')).top - rect.bottom,
        greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
      );
    });

    testWidgets('no ad loaded: collapses to zero height, no placeholder '
        'and no gap, and stays that way for the visit', (tester) async {
      ads.nativeLoaded = false;
      await pumpApp(tester);
      expect(_native, findsNothing);
      expect(tester.getSize(find.byType(AdNativeSlot)).height, 0);
      expect(
        tester.getRect(find.text('more content')).top,
        tester.getRect(find.text('content of home')).bottom,
      );
      // An ad arriving later doesn't push content around mid-visit.
      final asked = ads.nativeRequests;
      ads
        ..nativeLoaded = true
        ..becomeReady();
      await tester.pumpAndSettle();
      expect(_native, findsNothing);
      expect(ads.nativeRequests, asked);
    });

    testWidgets('never waits for consent: empty until ads are ready', (
      tester,
    ) async {
      ads.ready = false;
      await pumpApp(tester);
      expect(_native, findsNothing);
      expect(ads.nativesTaken, 0);
    });

    testWidgets('a placement on the wrong screen shows nothing', (
      tester,
    ) async {
      // The vault page asks for the Home card; the policy says no.
      await pumpApp(tester, initial: Routes.files);
      expect(find.text('content of vault'), findsOneWidget);
      expect(_native, findsNothing);
      expect(ads.nativeRequests, 0);
    });

    for (final location in [
      Routes.settings,
      Routes.notes,
      Routes.authenticatorAdd,
      Routes.document('d1'),
      Routes.scanReview,
      Routes.tool(ToolId.protectFile),
      Routes.tool(ToolId.signPdf),
    ]) {
      testWidgets('an AdNativeSlot placed on $location shows nothing and '
          'requests nothing', (tester) async {
        await pumpApp(tester, initial: location);
        expect(find.byType(AdNativeSlot), findsOneWidget);
        expect(_native, findsNothing);
        expect(ads.nativeRequests, 0);
      });
    }

    testWidgets('leaving the screen frees the ad; coming back takes a new '
        'one', (tester) async {
      await pumpApp(tester);
      expect(ads.nativesTaken, 1);
      router.push(Routes.settings).ignore();
      await tester.pumpAndSettle();
      expect(_native, findsNothing);
      expect(ads.nativesDisposed, 1);
      router.pop();
      await tester.pumpAndSettle();
      expect(_native, findsOneWidget);
      expect(ads.nativesTaken, 2);
    });

    testWidgets('the result card uses the larger layout', (tester) async {
      await pumpApp(tester, initial: Routes.tool(ToolId.merge));
      expect(_native, findsOneWidget);
      expect(ads.nativeSizes, [AdNativeSize.medium]);
      expect(
        tester.getSize(find.byKey(FakeAdsService.nativeKey)).height,
        AdNativeSize.medium.height,
      );
    });

    testWidgets('QR history card', (tester) async {
      await pumpApp(tester, initial: Routes.qrHistory);
      expect(_native, findsOneWidget);
      // ...but no banner there.
      expect(_banner, findsNothing);
    });

    testWidgets('no overflow at 2x text size, on a small phone, with a '
        'native card and a banner on screen', (tester) async {
      await pumpApp(tester, textScale: 2, tallView: false);
      expect(_native, findsOneWidget);
      expect(_banner, findsOneWidget);
      expect(tester.takeException(), isNull);
      await pumpApp(
        tester,
        textScale: 2,
        tallView: false,
        initial: Routes.tool(ToolId.merge),
      );
      expect(_native, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('interstitial', () {
    testWidgets('asked for only when leaving the result of an allowed tool', (
      tester,
    ) async {
      await pumpApp(tester, initial: Routes.tool(ToolId.merge));
      await tester.tap(find.text('leave result'));
      await tester.pumpAndSettle();
      expect(ads.interstitialRequests, 1);
    });

    for (final location in [
      Routes.home,
      Routes.tools,
      Routes.settings,
      Routes.notes,
      Routes.document('d1'),
      Routes.scanReview,
      Routes.tool(ToolId.protectFile),
      Routes.tool(ToolId.signPdf),
      Routes.qrHistory,
    ]) {
      testWidgets('never when leaving $location', (tester) async {
        await pumpApp(tester, initial: location);
        await tester.tap(find.text('leave result'));
        await tester.pumpAndSettle();
        expect(ads.interstitialRequests, 0);
      });
    }

    testWidgets('a missing location means no interstitial', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monetizationModeProvider.overrideWithValue(MonetizationMode.ads),
            adsServiceProvider.overrideWithValue(ads),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      maybeShowResultInterstitial(captured, null);
      maybeShowResultInterstitial(captured, Uri.parse(Routes.settings));
      expect(ads.interstitialRequests, 0);
      maybeShowResultInterstitial(
        captured,
        Uri.parse(Routes.tool(ToolId.merge)),
      );
      expect(ads.interstitialRequests, 1);
    });
  });
}
