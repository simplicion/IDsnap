// The route allowlist, per ad format (ADR-0013). If this test fails after
// a routing change, decide deliberately: ads never appear on a new screen
// by default.
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every forbidden area, by location. No ad of any kind, ever.
final _forbidden = <String>[
  // ID Vault, folders, document viewer.
  Routes.files,
  Routes.folder('f1'),
  Routes.document('d1'),
  // Authenticator.
  Routes.authenticator,
  Routes.authenticatorAdd,
  Routes.authenticatorScan,
  Routes.authenticatorAccount('a1'),
  // Secure notes.
  Routes.notes,
  Routes.note('n1'),
  // Camera, scanner, ID card, passport photo: capture and review.
  Routes.scan(),
  Routes.scan(source: ScanSource.gallery),
  Routes.scan(source: ScanSource.resume),
  Routes.idCard(),
  Routes.idCard(folderId: 'f1'),
  Routes.passportPhotoCamera,
  Routes.passportPhoto(folderId: 'f1'),
  Routes.scanReview,
  Routes.scanCrop('p1'),
  Routes.scanSave,
  // Signature pad and Sign PDF, password forms, passport/ID photo crop.
  Routes.tool(ToolId.signPdf),
  Routes.tool(ToolId.mySignature),
  Routes.tool(ToolId.protectFile),
  Routes.tool(ToolId.removePdfPassword),
  Routes.tool(ToolId.photoCrop),
  // QR camera.
  Routes.qrScanner,
  // Settings and everything under it (backup password, app lock).
  Routes.settings,
  Routes.privacy,
  Routes.about,
  Routes.security,
  Routes.dataExport,
  // Paywall screens (paid builds).
  Routes.paywall(),
  Routes.paywall(feature: ProFeature.scan, from: '/tools/merge'),
  Routes.subscription,
  Routes.subscriptionTerms,
  // A kit in progress may open the camera and the signature pad: no banner
  // (its saved-file panel is covered separately below).
  // Tools opened for a vault document belong to that document.
  Routes.tool(ToolId.merge, docId: 'd1'),
  Routes.tool(ToolId.ocr, docId: 'd1'),
  Routes.convert('pdf-to-docx', docId: 'd1'),
  '/tools/convert?doc=d1',
  // Unknown locations.
  '/nowhere',
  '/tools/unknown-tool',
  '/tools/merge/extra',
];

const _bannerTools = [
  ToolId.merge,
  ToolId.split,
  ToolId.organize,
  ToolId.compressPdf,
  ToolId.compressImage,
  ToolId.resizeImage,
  ToolId.imagesToPdf,
  ToolId.pdfToImages,
  ToolId.ocr,
];

void main() {
  group('forbidden areas', () {
    for (final location in _forbidden) {
      test('no ad of any kind at $location', () {
        final uri = Uri.parse(location);
        expect(AdPlacementPolicy.allowsBanner(uri), isFalse);
        expect(AdPlacementPolicy.allowsInterstitial(uri), isFalse);
        for (final p in AdNativePlacement.values) {
          expect(AdPlacementPolicy.allowsNative(p, uri), isFalse, reason: '$p');
        }
        expect(AdPlacementPolicy.forbidsAds(uri), isTrue);
      });
    }

    test('every tool is either on the ad allowlist or forbidden; none is '
        'allowed by accident', () {
      const sensitive = {
        ToolId.signPdf,
        ToolId.mySignature,
        ToolId.protectFile,
        ToolId.removePdfPassword,
        ToolId.photoCrop,
      };
      const hubs = {ToolId.kits, ToolId.convert};
      expect(
        {...AdPlacementPolicy.adTools, ...sensitive, ...hubs},
        ToolId.values.toSet(),
        reason: 'a new ToolId must be placed on purpose',
      );
      expect(AdPlacementPolicy.adTools.intersection(sensitive), isEmpty);
      for (final t in sensitive) {
        expect(AdPlacementPolicy.forbidsAds(Uri.parse(Routes.tool(t))), isTrue);
      }
    });
  });

  group('banner', () {
    test('allowed on exactly: Home, Tools, kits hub, conversion list and '
        'forms, QR generator, and the listed tool forms', () {
      final allowed = [
        Routes.home,
        Routes.tools,
        Routes.kits,
        Routes.tool(ToolId.convert),
        Routes.convert('pdf-to-docx'),
        Routes.qrGenerate,
        for (final t in _bannerTools) Routes.tool(t),
      ];
      for (final location in allowed) {
        expect(
          AdPlacementPolicy.allowsBanner(Uri.parse(location)),
          isTrue,
          reason: location,
        );
      }
      expect(AdPlacementPolicy.adTools, _bannerTools.toSet());
    });

    test('not on a kit in progress, the QR history or the QR camera', () {
      for (final location in [
        Routes.kit('exam-portal'),
        Routes.qrHistory,
        Routes.qrScanner,
      ]) {
        expect(
          AdPlacementPolicy.allowsBanner(Uri.parse(location)),
          isFalse,
          reason: location,
        );
      }
    });

    test('a trailing slash is the same screen', () {
      expect(AdPlacementPolicy.allowsBanner(Uri.parse('/tools/')), isTrue);
    });
  });

  group('interstitial', () {
    test('only after leaving the saved-file panel of a tool, kit or '
        'conversion', () {
      for (final t in _bannerTools) {
        expect(
          AdPlacementPolicy.interstitialAt(Uri.parse(Routes.tool(t))),
          AdInterstitialTrigger.toolResultClosed,
          reason: t.name,
        );
      }
      expect(
        AdPlacementPolicy.interstitialAt(Uri.parse(Routes.kit('exam-portal'))),
        AdInterstitialTrigger.kitCompleted,
      );
      expect(
        AdPlacementPolicy.interstitialAt(
          Uri.parse(Routes.convert('pdf-to-docx')),
        ),
        AdInterstitialTrigger.exportFinished,
      );
    });

    test('never on a tab, a list or a hub (no job finishes there)', () {
      for (final location in [
        Routes.home,
        Routes.tools,
        Routes.kits,
        Routes.tool(ToolId.convert),
        Routes.qrGenerate,
        Routes.qrHistory,
      ]) {
        expect(
          AdPlacementPolicy.allowsInterstitial(Uri.parse(location)),
          isFalse,
          reason: location,
        );
      }
    });
  });

  group('native', () {
    test('each card belongs to exactly its own screens', () {
      final expected = <AdNativePlacement, List<String>>{
        AdNativePlacement.toolsList: [Routes.tools],
        AdNativePlacement.home: [Routes.home],
        AdNativePlacement.qrHistory: [Routes.qrHistory],
        AdNativePlacement.toolResult: [
          for (final t in _bannerTools) Routes.tool(t),
          Routes.kit('exam-portal'),
          Routes.convert('pdf-to-docx'),
        ],
      };
      final everywhere = {
        for (final list in expected.values) ...list,
        ..._forbidden,
        Routes.kits,
        Routes.qrGenerate,
      };
      for (final MapEntry(key: placement, value: allowed) in expected.entries) {
        for (final location in everywhere) {
          expect(
            AdPlacementPolicy.allowsNative(placement, Uri.parse(location)),
            allowed.contains(location),
            reason: '$placement at $location',
          );
        }
      }
    });

    test('the result card is the bigger layout; list cards are small', () {
      expect(AdNativePlacement.toolResult.size, AdNativeSize.medium);
      for (final p in [
        AdNativePlacement.toolsList,
        AdNativePlacement.home,
        AdNativePlacement.qrHistory,
      ]) {
        expect(p.size, AdNativeSize.small);
      }
    });
  });

  test("the owner's numbers, all in the policy file", () {
    expect(AdPlacementPolicy.interstitialMinGap, const Duration(minutes: 3));
    expect(AdPlacementPolicy.interstitialMaxPerDay, 6);
    expect(
      AdPlacementPolicy.interstitialSessionWarmUp,
      const Duration(seconds: 60),
    );
    expect(AdPlacementPolicy.interstitialFreeTasks, 1);
    expect(AdPlacementPolicy.toolsNativeAfterGroup, 2);
    expect(AdPlacementPolicy.qrHistoryNativeAfterItem, 5);
    expect(AdPlacementPolicy.homeNativeMinRecents, greaterThanOrEqualTo(1));
    // Space that keeps taps meant for the app off the ads.
    expect(AdPlacementPolicy.nativeCardGap, greaterThanOrEqualTo(16));
    expect(AdPlacementPolicy.bannerButtonGap, greaterThanOrEqualTo(16));
    // Google's templates need at least these heights.
    expect(AdNativeSize.small.height, greaterThanOrEqualTo(90));
    expect(AdNativeSize.medium.height, greaterThanOrEqualTo(320));
    // Native ads expire after an hour.
    expect(AdPlacementPolicy.nativeMaxAge, lessThan(const Duration(hours: 1)));
  });
}
