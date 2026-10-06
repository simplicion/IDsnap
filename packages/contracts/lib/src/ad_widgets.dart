import 'dart:async';

import 'package:docscan_contracts/src/ad_placement.dart';
import 'package:docscan_contracts/src/ads.dart';
import 'package:docscan_contracts/src/monetization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The location on top of [router], including routes opened with `push`
/// (which `currentConfiguration.uri` alone does not report).
Uri currentRouterLocation(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  final leaf = config.lastOrNull;
  return leaf is ImperativeRouteMatch ? leaf.matches.uri : config.uri;
}

/// The location of the route [context] is built in, or null outside a
/// GoRouter (then no ad is ever shown).
Uri? routeLocationOf(BuildContext context) {
  try {
    return GoRouterState.of(context).uri;
  } on Object {
    return null;
  }
}

String _pathOf(Uri uri) {
  final p = uri.path;
  if (p.isEmpty) return '/';
  return p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
}

/// What every ad slot watches: the build's mode, the ads service, the
/// router, and whether its own screen is the one in front.
mixin _AdSlotState<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  GoRouter? _router;
  AdsService? _ads;
  Uri? _own;

  /// Rebuild; called when the route, the service or the keyboard changes.
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_changed);
      _router = router?..routerDelegate.addListener(_changed);
    }
    _own ??= routeLocationOf(context);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_changed);
    _ads?.removeListener(_changed);
    super.dispose();
  }

  /// The ads service, listened to.
  AdsService _watchAds() {
    final ads = ref.watch(adsServiceProvider);
    if (!identical(ads, _ads)) {
      _ads?.removeListener(_changed);
      _ads = ads..addListener(_changed);
    }
    return ads;
  }

  /// This slot's screen is the one the user is looking at: the build
  /// shows ads, the screen is the router's top location (not covered by a
  /// pushed screen, not another tab), the policy accepts that location
  /// ([allows]) and the app isn't locked (the lock gate and inactive tabs
  /// switch tickers off).
  bool _inFront(bool Function(Uri location) allows) {
    final router = _router;
    final own = _own;
    if (router == null || own == null) return false;
    if (!ref.watch(monetizationModeProvider).showsAds) return false;
    if (!allows(own)) return false;
    if (_pathOf(currentRouterLocation(router)) != _pathOf(own)) return false;
    return TickerMode.valuesOf(context).enabled;
  }
}

/// The anchored ad banner. Put it at the bottom of a screen
/// (`Scaffold.bottomNavigationBar`): it takes its own space, so it never
/// covers content.
///
/// It is empty (zero height, no ad requested) unless ALL of these hold:
/// - the build shows ads (`IDSNAP_MONETIZATION=ads`);
/// - the placement policy allows a banner on this screen and the screen
///   is the one in front;
/// - the app isn't locked;
/// - the keyboard is closed;
/// - consent is resolved and the ads SDK is running.
///
/// The height is decided once per visit and then kept, whether or not the
/// ad loads, so the layout never jumps under the user's finger.
///
/// [gapAbove] adds empty space above the banner while it is open; use
/// [AdPlacementPolicy.bannerButtonGap] when a button sits right above.
class AdBannerSlot extends ConsumerStatefulWidget {
  const AdBannerSlot({super.key, this.gapAbove = 0});

  final double gapAbove;

  /// On the reserved banner area while the slot is open (for tests).
  static const openKey = Key('idsnap.adBanner.open');

  /// What screen readers announce for an ad area.
  static const semanticLabel = 'Advertisement';

  @override
  ConsumerState<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends ConsumerState<AdBannerSlot>
    with WidgetsBindingObserver, _AdSlotState<AdBannerSlot> {
  /// The width the slot is open (or opening) for; null while it must
  /// stay empty.
  int? _visitWidth;
  double? _height;
  int _visit = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Keyboard opening or closing.
  @override
  void didChangeMetrics() => _changed();

  bool get _keyboardOpen =>
      MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;

  /// Starts or ends a visit so that it matches what [build] just saw.
  void _sync({required bool allowed, required int width}) {
    final wanted = allowed && width > 0 ? width : null;
    final ads = _ads;
    if (wanted == null || ads == null) {
      if (_visitWidth == null && _height == null) return;
      _visit++;
      setState(() {
        _visitWidth = null;
        _height = null;
      });
      return;
    }
    if (wanted == _visitWidth && _height != null) return;
    final visit = ++_visit;
    _visitWidth = wanted;
    unawaited(_open(ads, wanted, visit));
  }

  Future<void> _open(AdsService ads, int width, int visit) async {
    // Consent first; a no-op once done. The slot opens when the service
    // reports that it can show ads.
    unawaited(ads.initialize());
    final height = await ads.resolveBannerHeight(width);
    if (!mounted || visit != _visit) return;
    if (height == null || height <= 0) return;
    setState(() => _height = height);
  }

  @override
  Widget build(BuildContext context) {
    final ads = _watchAds();
    final allowed = _inFront(AdPlacementPolicy.allowsBanner) && !_keyboardOpen;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.truncate()
            : 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(allowed: allowed, width: width);
        });
        // Consent withdrawn mid-visit closes the slot at once.
        final open = allowed && ads.canShowAds && _visitWidth == width;
        final height = _height;
        if (!open || height == null) return const SizedBox.shrink();
        return Semantics(
          container: true,
          label: AdBannerSlot.semanticLabel,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(top: widget.gapAbove),
                child: SizedBox(
                  key: AdBannerSlot.openKey,
                  width: double.infinity,
                  height: height,
                  child: Center(
                    child: KeyedSubtree(
                      key: ValueKey(_visit),
                      child: ads.buildBanner(width: width),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One native ad card inside scrolling content: a tinted, outlined card
/// headed "Ad · Advertisement", visibly different from tool tiles and
/// document rows, with [AdPlacementPolicy.nativeCardGap] of empty space
/// above and below so taps meant for the app can't land on it.
///
/// It has ZERO height (no placeholder, no gap) unless the build shows
/// ads, the placement policy allows [placement] on this screen, the screen
/// is the one in front, and a native ad was ALREADY loaded when the visit
/// began. It never waits for an ad and never changes size during a visit.
/// Use at most one per screen.
class AdNativeSlot extends ConsumerStatefulWidget {
  const AdNativeSlot({
    required this.placement,
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final AdNativePlacement placement;

  /// Horizontal inset matching the content around the card.
  final EdgeInsetsGeometry padding;

  /// On the card while an ad is shown (for tests).
  static const openKey = Key('idsnap.adNative.open');

  @override
  ConsumerState<AdNativeSlot> createState() => _AdNativeSlotState();
}

class _AdNativeSlotState extends ConsumerState<AdNativeSlot>
    with _AdSlotState<AdNativeSlot> {
  /// A visit has begun and its one decision (ad or nothing) was made.
  bool _visiting = false;
  AdNativeHandle? _handle;

  @override
  void dispose() {
    _handle?.dispose();
    _handle = null;
    super.dispose();
  }

  void _sync({required bool inFront, required AdNativeStyle style}) {
    final ads = _ads;
    if (!inFront || ads == null) {
      if (!_visiting) return;
      final old = _handle;
      setState(() {
        _visiting = false;
        _handle = null;
      });
      old?.dispose();
      return;
    }
    if (_visiting) return;
    // Consent first; a no-op once done.
    unawaited(ads.initialize());
    if (!ads.canShowAds) return;
    final handle = ads.takeNative(widget.placement.size, style);
    setState(() {
      _visiting = true;
      _handle = handle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ads = _watchAds();
    final scheme = Theme.of(context).colorScheme;
    final style = AdNativeStyle(
      background: scheme.surfaceContainerHighest,
      primaryText: scheme.onSurface,
      secondaryText: scheme.onSurfaceVariant,
      buttonBackground: scheme.primary,
      buttonText: scheme.onPrimary,
    );
    final inFront = _inFront(
      (location) => AdPlacementPolicy.allowsNative(widget.placement, location),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(inFront: inFront, style: style);
    });
    final handle = _handle;
    if (!inFront || !ads.canShowAds || handle == null) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AdPlacementPolicy.nativeCardGap,
      ).add(widget.padding),
      child: Semantics(
        container: true,
        child: Material(
          key: AdNativeSlot.openKey,
          color: style.background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Ad',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        AdBannerSlot.semanticLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: widget.placement.size.height,
                child: handle.view,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Call when the user LEAVES the saved-file panel of a finished job (Done
/// or back), with the [location] of that screen. Shows an interstitial
/// only if the placement policy allows one there and the frequency caps
/// agree; otherwise does nothing. Never blocks: an ad that isn't loaded is
/// skipped.
///
/// Don't call it for any other navigation, from a dialog or sheet, or
/// before or during work.
void maybeShowResultInterstitial(WidgetRef ref, Uri? location) {
  if (location == null) return;
  if (!ref.read(monetizationModeProvider).showsAds) return;
  if (!AdPlacementPolicy.allowsInterstitial(location)) return;
  unawaited(ref.read(adsServiceProvider).maybeShowInterstitial());
}
