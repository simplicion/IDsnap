// THE ad placement policy (ADR-0013). The product owner's goal: earn as
// much as reasonably possible from ads while keeping the experience very
// good and the annoyance low.
//
// This file is an ALLOWLIST and holds EVERY number about ads. A screen
// that isn't named here can never show an ad: `AdBannerSlot`,
// `AdNativeSlot` and `maybeShowResultInterstitial` ask this policy with
// the router's location and do nothing when it says no. To change where
// or how often ads appear, edit this file (and only this file), then
// update packages/contracts/test/ad_placement_test.dart and
// apps/scanner/test/ads_placement_test.dart.
//
// ALLOWED
//   Banner        One anchored adaptive banner at the bottom of: the Home
//                 tab, the Tools tab, the kits hub, the conversion list,
//                 the QR generator, and the option forms of the tools in
//                 [bannerTools] (only while the user is choosing options,
//                 never while a job runs). Hidden while the keyboard is
//                 open.
//   Native        One clearly labelled "Ad" card per screen, inside the
//                 scrolling content: the Tools list (after the 2nd group),
//                 Home (above "Recent files", only when the user has
//                 files), the saved-file panel of a finished job (below
//                 the result and its buttons), and the QR history (after
//                 the 5th entry). Only an ad that is already loaded is
//                 shown; otherwise the slot has zero height.
//   Interstitial  Only when the user leaves the saved-file panel of a
//                 finished tool job, kit or conversion; capped below.
//
// FORBIDDEN (everything else), in particular: the ID Vault and every
// folder and document viewer, the Authenticator, Secure notes, the app
// lock and folder lock screens, the scanner / camera / passport-photo /
// ID-card capture and review flows, the photo-crop tool, the signature pad
// and Sign PDF, the password forms (Protect file, Remove PDF password,
// backup password), the QR camera and code result screens, Settings, the
// paywall screens, the startup and recovery screens, and every dialog and
// bottom sheet. No app-open ads and no rewarded ads.
//
// AdMob policy points this file is built around: native ads are labelled
// and look different from app content; no ad sits where a tap meant for
// the app is likely to land on it (see [bannerButtonGap],
// [nativeCardGap]); no screen is only an ad plus an exit; no interstitial
// on app load, on exit or on plain back navigation; nothing asks the user
// to tap an ad.
import 'package:docscan_contracts/src/routes.dart';

/// The moments an interstitial may appear. In each, the job has finished
/// and its result is already saved and on screen.
enum AdInterstitialTrigger {
  /// Leaving the saved-file panel of a PDF, image or OCR tool.
  toolResultClosed,

  /// Leaving the saved-file panel of an application kit.
  kitCompleted,

  /// Leaving the saved-file panel of a file conversion (export).
  exportFinished,
}

/// The native ad cards. At most one per screen.
enum AdNativePlacement {
  /// Tools tab, between tool groups.
  toolsList(AdNativeSize.small),

  /// Home tab, above "Recent files".
  home(AdNativeSize.small),

  /// Saved-file panel of a finished job, below the result and its buttons.
  toolResult(AdNativeSize.medium),

  /// QR scan history, between entries.
  qrHistory(AdNativeSize.small);

  const AdNativePlacement(this.size);

  final AdNativeSize size;
}

/// The two native layouts (Google's native templates).
enum AdNativeSize {
  /// One row: icon, headline, button.
  small(height: AdPlacementPolicy.nativeSmallHeight),

  /// With a picture or video above the text.
  medium(height: AdPlacementPolicy.nativeMediumHeight);

  const AdNativeSize({required this.height});

  /// Fixed height of the ad view in logical pixels.
  final double height;
}

abstract final class AdPlacementPolicy {
  // ── Interstitial frequency caps ───────────────────────────────────────

  /// Shortest time between two interstitials.
  static const interstitialMinGap = Duration(minutes: 3);

  /// Most interstitials per calendar day (the phone's local date).
  static const interstitialMaxPerDay = 6;

  /// No interstitial this soon after the app started.
  static const interstitialSessionWarmUp = Duration(seconds: 60);

  /// How many finished jobs the user completes, ever, before the first
  /// interstitial: the first completed task never gets one.
  static const interstitialFreeTasks = 1;

  // ── Native cards ──────────────────────────────────────────────────────

  /// Tools tab: the card goes after this many tool groups (never above
  /// the first group or the search field), and only when at least this
  /// many groups are listed and nothing is being searched.
  static const toolsNativeAfterGroup = 2;

  /// Home: the card is skipped unless the user has at least this many
  /// recent files (a nearly empty Home is not padded out with an ad).
  static const homeNativeMinRecents = 1;

  /// QR history: the card goes after this many entries (never if the
  /// list is shorter).
  static const qrHistoryNativeAfterItem = 5;

  /// Heights of the two native layouts.
  static const double nativeSmallHeight = 100;
  static const double nativeMediumHeight = 340;

  /// Empty space above and below a native card, keeping it away from
  /// tappable rows and buttons.
  static const double nativeCardGap = 20;

  /// A loaded native ad older than this is thrown away, not shown.
  static const nativeMaxAge = Duration(minutes: 50);

  // ── Banner ────────────────────────────────────────────────────────────

  /// Empty space between a screen's own bottom button and the banner
  /// below it, so a tap on the button can't land on the ad.
  static const double bannerButtonGap = 20;

  /// After a banner failed to load (offline, no ad available) banner
  /// slots stay closed this long instead of showing an empty strip.
  static const bannerRetryAfter = Duration(minutes: 5);

  // ── Where ─────────────────────────────────────────────────────────────

  /// Tab and list screens that may show the anchored banner (exact
  /// locations).
  static const bannerPaths = <String>{
    Routes.home,
    Routes.tools,
    Routes.kits,
    '/tools/convert',
    Routes.qrGenerate,
  };

  /// Tools whose option form may show the anchored banner, whose
  /// saved-file panel may show a native card and may be followed by an
  /// interstitial. Deliberately absent: [ToolId.signPdf] and
  /// [ToolId.mySignature] (signature pad), [ToolId.protectFile] and
  /// [ToolId.removePdfPassword] (password forms), [ToolId.photoCrop]
  /// (passport and ID photos).
  static const adTools = <ToolId>{
    ToolId.ocr,
    ToolId.imagesToPdf,
    ToolId.merge,
    ToolId.split,
    ToolId.organize,
    ToolId.compressPdf,
    ToolId.pdfToImages,
    ToolId.compressImage,
    ToolId.resizeImage,
  };

  /// Whether the anchored banner may show at [location] (default: no).
  ///
  /// A tool opened for a vault document (`?doc=<id>`) belongs to that
  /// document, so it never shows ads of any kind.
  static bool allowsBanner(Uri location) {
    if (_forVaultDocument(location)) return false;
    final path = _path(location);
    if (bannerPaths.contains(path)) return true;
    final s = _segments(location);
    if (s.length < 2 || s.first != 'tools') return false;
    // One conversion's option form.
    if (s[1] == ToolId.convert.path) return s.length == 3;
    return s.length == 2 && adTools.any((t) => t.path == s[1]);
  }

  /// The interstitial moment that leaving the saved-file panel at
  /// [location] is, or null when no interstitial may follow it (the
  /// default). The same locations may show the [AdNativePlacement
  /// .toolResult] card.
  static AdInterstitialTrigger? interstitialAt(Uri location) {
    if (_forVaultDocument(location)) return null;
    final s = _segments(location);
    if (s.length < 2 || s.first != 'tools') return null;
    if (s[1] == ToolId.kits.path) {
      return s.length == 3 ? AdInterstitialTrigger.kitCompleted : null;
    }
    if (s[1] == ToolId.convert.path) {
      return s.length == 3 ? AdInterstitialTrigger.exportFinished : null;
    }
    if (s.length != 2) return null;
    return adTools.any((t) => t.path == s[1])
        ? AdInterstitialTrigger.toolResultClosed
        : null;
  }

  static bool allowsInterstitial(Uri location) =>
      interstitialAt(location) != null;

  /// Whether the native card [placement] may show at [location]
  /// (default: no).
  static bool allowsNative(AdNativePlacement placement, Uri location) {
    if (_forVaultDocument(location)) return false;
    final path = _path(location);
    return switch (placement) {
      AdNativePlacement.toolsList => path == Routes.tools,
      AdNativePlacement.home => path == Routes.home,
      AdNativePlacement.qrHistory => path == Routes.qrHistory,
      AdNativePlacement.toolResult => allowsInterstitial(location),
    };
  }

  /// True when no ad of any kind may appear at [location].
  static bool forbidsAds(Uri location) =>
      !allowsBanner(location) &&
      !allowsInterstitial(location) &&
      !AdNativePlacement.values.any((p) => allowsNative(p, location));

  static bool _forVaultDocument(Uri location) =>
      location.queryParameters.containsKey('doc');

  static List<String> _segments(Uri location) =>
      location.pathSegments.where((p) => p.isNotEmpty).toList();

  static String _path(Uri location) {
    final path = location.path;
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path.isEmpty ? '/' : path;
  }
}
