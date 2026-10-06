// Settings, Privacy and About in the free build with ads (ADR-0013) and in
// the paid modes. Settings never shows an ad.
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Store extends Mock implements SettingsStore {}

class _Files extends Mock implements FileStore {}

class _Ocr extends Mock implements TextRecognizer {}

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text, skipOffstage: false))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  setUpAll(() => registerFallbackValue(OcrScript.latin));

  late FakeAdsService ads;

  Future<void> pump(
    WidgetTester tester, {
    MonetizationMode mode = MonetizationMode.ads,
    String location = Routes.settings,
  }) async {
    tester.view
      ..physicalSize = const Size(500, 12000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store();
    final files = _Files();
    final ocr = _Ocr();
    when(store.load).thenAnswer((_) async => const AppSettings());
    when(files.usage).thenAnswer(
      (_) async => const StorageUsage(documents: 0, originals: 0, temp: 0),
    );
    when(() => ocr.capability(any())).thenAnswer(
      (_) async => const EngineCapability(available: true, worksOffline: true),
    );
    final key = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: key,
      initialLocation: location,
      routes: [
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => const SettingsScreen(),
          routes: settingsRoutes(key),
        ),
        GoRoute(
          path: Routes.subscription,
          builder: (_, _) => const Scaffold(body: Text('Subscription page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monetizationModeProvider.overrideWithValue(mode),
          adsServiceProvider.overrideWithValue(ads),
          settingsStoreProvider.overrideWithValue(store),
          fileStoreProvider.overrideWithValue(files),
          textRecognizerProvider.overrideWithValue(ocr),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => ads = FakeAdsService());

  group('free build', () {
    testWidgets('Settings says IDSnap is free and explains the ads; there is '
        'no Subscription entry and nothing about Pro', (tester) async {
      await pump(tester);
      expect(find.text('Free with ads'), findsOneWidget);
      expect(find.text('IDSnap is free'), findsOneWidget);
      expect(find.textContaining('nothing to buy'), findsOneWidget);
      expect(find.textContaining('never ads in your ID Vault'), findsOneWidget);
      expect(find.text('Subscription'), findsNothing);
      final text = _allText(tester);
      expect(text, isNot(contains('IDSnap Pro')));
      expect(text, isNot(contains('licence')));
      expect(text, isNot(contains('Free day')));
    });

    testWidgets('Settings shows no ad of any kind and runs no ad code', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(AdBannerSlot), findsNothing);
      expect(find.byType(AdNativeSlot), findsNothing);
      expect(find.byKey(FakeAdsService.bannerKey), findsNothing);
      expect(find.byKey(FakeAdsService.nativeKey), findsNothing);
      expect(ads.adActivity, 0);
      expect(ads.initializeCalls, 0);
      for (final page in [
        Routes.privacy,
        Routes.about,
        Routes.security,
        Routes.dataExport,
      ]) {
        await pump(tester, location: page);
        expect(find.byType(AdBannerSlot), findsNothing, reason: page);
        expect(find.byType(AdNativeSlot), findsNothing, reason: page);
        expect(ads.adActivity, 0, reason: page);
      }
    });

    testWidgets('"Ad privacy choices" appears only when the consent platform '
        'requires it, and reopens the form', (tester) async {
      await pump(tester);
      expect(find.text('Ad privacy choices'), findsNothing);

      ads
        ..optionsRequired = true
        ..becomeReady();
      await tester.pumpAndSettle();
      expect(find.text('Ad privacy choices'), findsOneWidget);
      await tester.tap(find.text('Ad privacy choices'));
      await tester.pumpAndSettle();
      expect(ads.privacyOptionsOpened, 1);
    });

    testWidgets('Erase everything does not mention a purchase', (tester) async {
      await pump(tester);
      expect(find.textContaining('purchase is kept'), findsNothing);
    });

    testWidgets('Privacy tells the truth about ads', (tester) async {
      await pump(tester, location: Routes.privacy);
      final text = _allText(tester);
      // The owner's sentence, word for word.
      expect(
        text,
        contains(
          'Your documents, IDs and codes never leave this phone. IDSnap is '
          'free and shows ads on',
        ),
      );
      expect(text, contains('the ads are provided by Google'));
      expect(text, contains('advertising ID'));
      expect(text, contains('approximate location'));
      expect(text, contains('diagnostic'));
      // What is never given to the ads software.
      expect(text, contains('authenticator secret'));
      // Where ads never appear, and how to choose.
      expect(text, contains('Where ads never appear'));
      expect(text, contains('Ad privacy choices'));
      expect(text, contains('non-personalised'));
      // Still true, still said.
      expect(text, contains('No account'));
      expect(text, contains('No uploads'));
      expect(text, contains('Not a certified copy'));
      // No longer true in this build: not said.
      for (final gone in [
        'licence',
        '180 Pay',
        'IDSnap Pro',
        'built to work offline',
        'no ads',
        'No ads',
        'only to check',
      ]) {
        expect(text, isNot(contains(gone)), reason: gone);
      }
    });

    testWidgets('About uses the same sentence', (tester) async {
      await pump(tester, location: Routes.about);
      expect(find.textContaining(adsPrivacyLine), findsOneWidget);
      expect(find.textContaining('licence and for'), findsNothing);
    });
  });

  group('paid builds keep their wording, and have no ads', () {
    testWidgets('Settings: the Subscription entry, no "free with ads"', (
      tester,
    ) async {
      await pump(tester, mode: MonetizationMode.licence);
      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('IDSnap Pro'), findsOneWidget);
      expect(find.text('Free with ads'), findsNothing);
      expect(find.text('Ad privacy choices'), findsNothing);
      expect(find.textContaining('purchase is kept'), findsOneWidget);
      expect(ads.adActivity, 0);
    });

    testWidgets('Privacy: licence and payments only; says there are no ads', (
      tester,
    ) async {
      await pump(
        tester,
        mode: MonetizationMode.licence,
        location: Routes.privacy,
      );
      final text = _allText(tester);
      expect(text, contains('Internet: licence and payments only'));
      expect(text, contains('180 Pay'));
      expect(text, contains('There are no ads.'));
      expect(text, isNot(contains('advertising ID')));
    });

    testWidgets('About: the licence sentence', (tester) async {
      await pump(tester, mode: MonetizationMode.store, location: Routes.about);
      expect(find.textContaining(paidPrivacyLine), findsOneWidget);
    });
  });
}
