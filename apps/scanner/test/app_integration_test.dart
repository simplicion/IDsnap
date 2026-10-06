import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_contracts/testing.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/app.dart';
import 'package:drift/native.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps a bounded number of frames, letting real async work (file IO,
/// Drift) progress between them. Unlike pumpAndSettle it tolerates
/// indeterminate spinners.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Boots the real app (router, every feature, real data layer, real imaging
/// and conversion engines). Only platform plugins are faked.
void main() {
  late Directory root;
  late DataLayer data;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('docscan_it');
    data = await openDataLayer(
      rootOverride: root.path,
      executor: NativeDatabase.memory(),
    );
  });

  tearDown(() async {
    await data.close();
    await root.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> extra = const [],
    AppLock? lock,
  }) async {
    const images = ImagingEngine();
    final pdf = _FakePdf();
    final conversion = ConversionEngineImpl(
      files: data.files,
      pdf: pdf,
      images: images,
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(data.documents),
          draftStoreProvider.overrideWithValue(data.drafts),
          settingsStoreProvider.overrideWithValue(data.settings),
          fileStoreProvider.overrideWithValue(data.files),
          imageProcessorProvider.overrideWithValue(images),
          pdfEngineProvider.overrideWithValue(pdf),
          textRecognizerProvider.overrideWithValue(_FakeOcr()),
          documentScannerProvider.overrideWithValue(_FakeScanner()),
          mediaPickerProvider.overrideWithValue(_FakePicker()),
          shareServiceProvider.overrideWithValue(_FakeShare()),
          conversionEngineProvider.overrideWithValue(conversion),
          faceLocatorProvider.overrideWithValue(_FakeFace()),
          appLockProvider.overrideWithValue(lock ?? _FakeLock()),
          otpCodecProvider.overrideWithValue(const OtpCodecImpl()),
          authenticatorRepositoryProvider.overrideWithValue(
            DriftAuthenticatorRepository(
              data.database,
              secrets: _MemorySecrets(),
              codec: const OtpCodecImpl(),
            ),
          ),
          ...extra,
        ],
        child: const DocScanApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
  }

  /// Drift closes stream queries on a zero-length timer; unmount and flush
  /// it so the test binding doesn't report a pending timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('all four tabs render', (tester) async {
    await pumpApp(tester);
    expect(find.text('Scan a document'), findsOneWidget);
    // Settings is no longer a tab.
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
      findsNothing,
    );
    for (final tab in ['Authenticator', 'ID Vault', 'Tools', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$tab tab threw');
    }
    await unmount(tester);
  });

  testWidgets('every tool screen opens without errors', (tester) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    final locations = [
      for (final t in ToolId.values) Routes.tool(t),
      Routes.convert('pdf-to-docx'),
      Routes.convert('txt-to-pdf'),
      Routes.settings,
      Routes.privacy,
      Routes.about,
      Routes.authenticator,
      Routes.authenticatorAdd,
      Routes.authenticatorScan,
      Routes.qrScanner,
      Routes.qrGenerate,
      Routes.qrHistory,
    ];
    for (final location in locations) {
      router.go(location);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$location threw');
      expect(find.byType(Scaffold), findsWidgets, reason: location);
    }
    await unmount(tester);
  });

  testWidgets('Home gear pushes Settings full-screen over the shell', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Authenticator tab shows a stored account and its code', (
    tester,
  ) async {
    await pumpApp(tester);
    final repo = DriftAuthenticatorRepository(
      data.database,
      secrets: _MemorySecrets(),
      codec: const OtpCodecImpl(),
    );
    await tester.runAsync(
      () => repo.add(
        const NewOtpAccount(
          label: 'me@example.com',
          issuer: 'GitHub',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
      ),
    );
    await tester.tap(find.text('Authenticator').last);
    await settle(tester);
    expect(find.text('GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a committed document appears in Files and opens', (
    tester,
  ) async {
    final commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: _FakePdf(),
      images: const ImagingEngine(),
    );
    final doc = await tester.runAsync(
      () => commit(
        OutputFile(
          bytes: Uint8List.fromList('Hello offline world'.codeUnits),
          format: DocumentFormat.txt,
          suggestedName: 'Meeting notes',
        ),
      ),
    );
    expect(doc!.isOk, isTrue);

    await pumpApp(tester);
    await tester.tap(find.text('ID Vault').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    // The vault categories sit above the list; scroll down to the document.
    await tester.scrollUntilVisible(
      find.text('Meeting notes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(find.text('Meeting notes'), findsWidgets);

    await tester.tap(find.text('Meeting notes').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.textContaining('Hello offline world'), findsOneWidget);
    await unmount(tester);
  });

  // ── Ads (ADR-0013): the real app, the real router, a fake ads service ──

  final bannerOpen = find.byKey(AdBannerSlot.openKey);
  final nativeOpen = find.byKey(AdNativeSlot.openKey);
  final bannerAd = find.byKey(FakeAdsService.bannerKey);
  final nativeAd = find.byKey(FakeAdsService.nativeKey);

  /// Every screen an ad must NEVER appear on, reachable by location.
  final forbidden = <String>[
    Routes.files,
    Routes.authenticator,
    Routes.authenticatorAdd,
    Routes.authenticatorScan,
    Routes.notes,
    Routes.settings,
    Routes.privacy,
    Routes.about,
    Routes.security,
    Routes.dataExport,
    Routes.idCard(),
    Routes.passportPhotoCamera,
    // (The scan review and save screens need a scan in progress; the policy
    // test in docscan_contracts covers their locations.)
    Routes.qrScanner,
    Routes.tool(ToolId.signPdf),
    Routes.tool(ToolId.mySignature),
    Routes.tool(ToolId.protectFile),
    Routes.tool(ToolId.removePdfPassword),
    Routes.tool(ToolId.photoCrop),
    Routes.tool(ToolId.merge, docId: 'd1'),
    Routes.kit('exam-portal'),
  ];

  /// Screens with the anchored banner.
  final withBanner = <String>[
    Routes.home,
    Routes.tools,
    Routes.kits,
    Routes.tool(ToolId.convert),
    Routes.convert('pdf-to-docx'),
    Routes.qrGenerate,
    for (final t in AdPlacementPolicy.adTools) Routes.tool(t),
  ];

  Future<GoRouter> pumpWithAds(
    WidgetTester tester,
    FakeAdsService ads, {
    MonetizationMode mode = MonetizationMode.ads,
  }) async {
    await pumpApp(
      tester,
      extra: [
        monetizationModeProvider.overrideWithValue(mode),
        adsServiceProvider.overrideWithValue(ads),
      ],
    );
    return GoRouter.of(tester.element(find.byType(Navigator).first));
  }

  Future<void> goTo(WidgetTester tester, GoRouter router, String to) async {
    router.go(to);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
  }

  testWidgets('ads: NO ad widget on any forbidden screen (vault, '
      'authenticator, notes, settings, scanner, signature, passwords...)', (
    tester,
  ) async {
    final ads = FakeAdsService();
    final router = await pumpWithAds(tester, ads);
    for (final location in forbidden) {
      await goTo(tester, router, location);
      expect(tester.takeException(), isNull, reason: '$location threw');
      expect(
        AdPlacementPolicy.forbidsAds(Uri.parse(location)) ||
            location == Routes.kit('exam-portal'),
        isTrue,
        reason: '$location should be forbidden by the policy',
      );
      expect(bannerOpen, findsNothing, reason: 'banner slot on $location');
      expect(bannerAd, findsNothing, reason: 'banner ad on $location');
      expect(nativeOpen, findsNothing, reason: 'native card on $location');
      expect(nativeAd, findsNothing, reason: 'native ad on $location');
    }
    expect(ads.interstitialRequests, 0);
    await unmount(tester);
  });

  testWidgets('ads: exactly one banner on the allowed screens, never two, '
      'and no layout error with it', (tester) async {
    final ads = FakeAdsService();
    final router = await pumpWithAds(tester, ads);
    for (final location in withBanner) {
      await goTo(tester, router, location);
      expect(tester.takeException(), isNull, reason: '$location threw');
      expect(
        AdPlacementPolicy.allowsBanner(Uri.parse(location)),
        isTrue,
        reason: location,
      );
      expect(bannerOpen, findsOneWidget, reason: 'banner on $location');
      expect(bannerAd, findsOneWidget, reason: 'one banner ad on $location');
      expect(
        nativeAd.evaluate().length,
        lessThanOrEqualTo(1),
        reason: 'at most one native card on $location',
      );
    }
    // Opening and closing every screen asked for no interstitial: those
    // only follow a finished job.
    expect(ads.interstitialRequests, 0);
    await unmount(tester);
  });

  testWidgets('ads: a document in the vault and its viewer show no ad', (
    tester,
  ) async {
    final ads = FakeAdsService();
    final router = await pumpWithAds(tester, ads);
    final commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: _FakePdf(),
      images: const ImagingEngine(),
    );
    final saved = await tester.runAsync(
      () => commit(
        OutputFile(
          bytes: Uint8List.fromList('Private text'.codeUnits),
          format: DocumentFormat.txt,
          suggestedName: 'Passport copy',
        ),
      ),
    );
    final id = saved!.valueOrNull!.id;
    for (final location in [Routes.files, Routes.document(id)]) {
      await goTo(tester, router, location);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);
      expect(bannerOpen, findsNothing, reason: location);
      expect(bannerAd, findsNothing, reason: location);
      expect(nativeOpen, findsNothing, reason: location);
      expect(nativeAd, findsNothing, reason: location);
    }
    // With a file in the vault, Home may now carry its native card.
    await goTo(tester, router, Routes.home);
    expect(bannerAd, findsOneWidget);
    expect(nativeAd.evaluate().length, lessThanOrEqualTo(1));
    await unmount(tester);
  });

  testWidgets('ads: nothing while the app is locked — no ad, no consent '
      'form, no ad code — and they start after unlocking', (tester) async {
    await tester.runAsync(
      () => data.settings.save(const AppSettings(appLock: true)),
    );
    final ads = FakeAdsService();
    final lock = _ManualLock();
    await pumpApp(
      tester,
      lock: lock,
      extra: [
        monetizationModeProvider.overrideWithValue(MonetizationMode.ads),
        adsServiceProvider.overrideWithValue(ads),
      ],
    );
    expect(find.text('IDSnap is locked'), findsOneWidget);
    expect(bannerOpen, findsNothing);
    expect(bannerAd, findsNothing);
    expect(nativeAd, findsNothing);
    expect(ads.initializeCalls, 0);
    expect(ads.adActivity, 0);

    lock.allow = true;
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('IDSnap is locked'), findsNothing);
    expect(bannerAd, findsOneWidget);
    expect(ads.initializeCalls, greaterThan(0));
    await unmount(tester);
  });

  testWidgets('ads: the paywall routes are unreachable in the free build', (
    tester,
  ) async {
    final router = await pumpWithAds(tester, FakeAdsService());
    for (final location in [
      Routes.paywall(),
      Routes.paywall(feature: ProFeature.scan, from: Routes.tool(ToolId.ocr)),
      Routes.subscription,
      Routes.subscriptionTerms,
    ]) {
      await goTo(tester, router, location);
      expect(find.text('Scan a document'), findsOneWidget, reason: location);
      expect(find.textContaining('IDSnap Pro'), findsNothing);
    }
    // And no tool redirects there: every tool opens.
    await goTo(tester, router, Routes.tool(ToolId.ocr));
    expect(currentRouterLocation(router).path, Routes.tool(ToolId.ocr));
    await unmount(tester);
  });

  testWidgets('paid builds: no ad anywhere, and no ad code runs', (
    tester,
  ) async {
    for (final mode in [MonetizationMode.licence, MonetizationMode.store]) {
      final ads = FakeAdsService();
      final router = await pumpWithAds(tester, ads, mode: mode);
      for (final location in [...withBanner, Routes.qrHistory]) {
        await goTo(tester, router, location);
        expect(bannerOpen, findsNothing, reason: '$mode $location');
        expect(nativeOpen, findsNothing, reason: '$mode $location');
      }
      expect(ads.adActivity, 0, reason: mode.name);
      expect(ads.initializeCalls, 0, reason: mode.name);
      await unmount(tester);
    }
  });
}

/// An app lock that fails until the test allows it.
class _ManualLock implements AppLock {
  bool allow = false;

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async => Ok(allow);
}

class _FakePdf implements PdfEngine {
  @override
  Future<Result<int>> pageCount(String path) async => const Ok(1);

  @override
  Future<Result<List<String>>> extractText(String path) async =>
      const Ok(['text']);

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<Uint8List>> fromImages(
    List<Uint8List> jpegPages,
    PdfBuildOptions options, {
    List<OcrResult?>? textLayers,
  }) async => Ok(Uint8List.fromList('%PDF-1.7'.codeUnits));

  @override
  Future<Result<Uint8List>> fromText(String text, TextPdfOptions options) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> merge(List<String> paths) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> selectPages(String path, List<int> pageIndices) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> rotatePages(
    String path,
    Map<int, int> quarterTurns,
  ) => fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> compress(
    String path,
    PdfCompressionLevel level, {
    void Function(double progress)? onProgress,
  }) => fromImages(const [], const PdfBuildOptions());
}

class _FakeOcr implements TextRecognizer {
  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<OcrResult>> recognize(
    String imagePath,
    OcrScript script,
  ) async => const Ok(OcrResult.empty);
}

class _FakeScanner implements DocumentScanner {
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<List<String>>> scan({int maxPages = 50}) async =>
      const Err(AppFailure(FailureCode.captureCancelled));
}

class _FakePicker implements MediaPicker {
  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      const Ok([]);

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async => const Ok([]);
}

class _FakeShare implements ShareService {
  @override
  Future<Result<void>> share(
    List<String> absolutePaths, {
    String? subject,
  }) async => const Ok(null);

  @override
  Future<Result<void>> shareText(String text) async => const Ok(null);

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) async =>
      const Ok(true);

  @override
  Future<Result<void>> copyText(String text) async => const Ok(null);
}

class _FakeFace implements FaceLocator {
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<NRect?>> locateLargestFace(String imagePath) async =>
      const Ok(null);
}

class _FakeLock implements AppLock {
  // No screen lock in tests: authenticator codes show with a hint.
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: false, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async => const Ok(true);
}

class _MemorySecrets implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Set<String>> keys() async => _values.keys.toSet();
}
