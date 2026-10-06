// Ads on the Home tab (ADR-0013): one anchored banner, and one labelled
// native card above "Recent files" when the user has files. Uses the fake
// ads service: no plugin, no network.
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Drafts implements DraftStore {
  @override
  Future<ScanDraft?> load() async => null;
  @override
  Future<void> save(ScanDraft d) async {}
  @override
  Future<void> clear({bool deleteImages = true}) async {}
}

class _Repo extends Mock implements DocumentRepository {
  _Repo(this.docs);
  final List<Document> docs;

  @override
  Stream<List<Document>> watch(DocumentQuery query) =>
      Stream.value(docs.take(query.limit ?? docs.length).toList());
}

class _Settings implements SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings s) async {}
}

class _Files extends Mock implements FileStore {
  @override
  String absolute(String relativePath) => '/app/$relativePath';
}

Document _doc(int i) => Document(
  id: 'd$i',
  name: 'Invoice $i',
  format: DocumentFormat.pdf,
  relativePath: 'documents/d$i.pdf',
  sizeBytes: 1000 * i,
  pageCount: i,
  createdAt: DateTime(2026, 9, 2),
  updatedAt: DateTime(2026, 9, 2),
);

final _banner = find.byKey(AdBannerSlot.openKey);
final _native = find.byKey(AdNativeSlot.openKey);

void main() {
  late FakeAdsService ads;

  Future<void> pump(
    WidgetTester tester, {
    int docs = 3,
    MonetizationMode mode = MonetizationMode.ads,
    double textScale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (_, _) => HomeScreen(now: DateTime(2026, 9, 24, 9)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monetizationModeProvider.overrideWithValue(mode),
          adsServiceProvider.overrideWithValue(ads),
          settingsStoreProvider.overrideWithValue(_Settings()),
          draftStoreProvider.overrideWithValue(_Drafts()),
          documentRepositoryProvider.overrideWithValue(
            _Repo([for (var i = 1; i <= docs; i++) _doc(i)]),
          ),
          fileStoreProvider.overrideWithValue(_Files()),
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
    await tester.pumpAndSettle();
  }

  setUp(() => ads = FakeAdsService());

  testWidgets('the banner sits at the bottom of Home in its own space', (
    tester,
  ) async {
    await pump(tester);
    expect(_banner, findsOneWidget);
    expect(find.byKey(FakeAdsService.bannerKey), findsOneWidget);
    final banner = tester.getRect(_banner);
    expect(banner.height, 60);
    expect(banner.bottom, 844);
    // The scrolling content ends where the banner begins: nothing is
    // covered.
    expect(
      tester.getRect(find.byType(CustomScrollView)).bottom,
      lessThanOrEqualTo(banner.top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with files: one native card, below the quick actions and '
      'above "Recent files"', (tester) async {
    await pump(tester, size: const Size(390, 4000));
    expect(_native, findsOneWidget);
    expect(ads.nativeSizes, [AdNativeSize.small]);
    final card = tester.getRect(_native);
    expect(card.top, greaterThan(tester.getRect(find.text('Quick tools')).top));
    expect(
      card.top,
      greaterThan(tester.getRect(find.text('Application kits')).top),
    );
    final recent = tester.getRect(find.text('Recent files'));
    expect(card.bottom, lessThan(recent.top));
    // Kept apart from the tappable card above it.
    expect(
      card.top - tester.getRect(find.text('Secure notes')).bottom,
      greaterThanOrEqualTo(AdPlacementPolicy.nativeCardGap),
    );
  });

  testWidgets('no files yet (little content): the native card is skipped, '
      "so an ad never pushes the user's content away", (tester) async {
    await pump(tester, docs: 0, size: const Size(390, 4000));
    expect(find.byType(AdNativeSlot), findsNothing);
    expect(_native, findsNothing);
    expect(ads.nativeRequests, 0);
    // The banner is still there.
    expect(_banner, findsOneWidget);
  });

  testWidgets('no native ad loaded: no card, no gap, nothing moves', (
    tester,
  ) async {
    ads.nativeLoaded = false;
    await pump(tester, size: const Size(390, 4000));
    expect(_native, findsNothing);
    expect(
      tester.getSize(find.byType(AdNativeSlot, skipOffstage: false)).height,
      0,
    );
  });

  testWidgets('no overflow at 2x text size with the banner and the native '
      'card, on a small phone', (tester) async {
    await pump(tester, textScale: 2, size: const Size(320, 568));
    expect(_banner, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      _native,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_native, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recent files'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('free build: no PRO badge, no trial banner, nothing about a '
      'licence', (tester) async {
    await pump(tester, size: const Size(390, 4000));
    expect(find.byType(TrialBanner), findsNothing);
    expect(find.text('Pro'), findsNothing);
    expect(find.text('PRO'), findsNothing);
    expect(find.textContaining('licence'), findsNothing);
    expect(find.textContaining('Free day'), findsNothing);
    expect(
      find.text(
        'Private vault · Your documents, IDs and codes never leave this '
        'phone',
      ),
      findsOneWidget,
    );
  });

  testWidgets('paid builds show no ads on Home and run no ad code', (
    tester,
  ) async {
    for (final mode in [MonetizationMode.licence, MonetizationMode.store]) {
      ads = FakeAdsService();
      await pump(tester, mode: mode, size: const Size(390, 4000));
      expect(_banner, findsNothing, reason: mode.name);
      expect(_native, findsNothing, reason: mode.name);
      expect(ads.adActivity, 0, reason: mode.name);
      expect(ads.initializeCalls, 0, reason: mode.name);
      expect(
        find.text('Offline vault · Your documents never leave this phone'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
