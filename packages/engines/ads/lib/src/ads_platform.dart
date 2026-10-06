import 'package:flutter/widgets.dart';

/// What the consent platform (Google UMP) knows about this user.
enum PlatformConsentStatus { unknown, notRequired, obtained, required }

/// A loaded full-screen ad.
abstract interface class PlatformInterstitial {
  /// Shows the ad. Completes with true once it was shown and closed,
  /// false if it couldn't be shown. Never throws.
  Future<bool> show();

  void dispose();
}

/// A loaded native ad.
abstract interface class PlatformNative {
  /// The ad view. May be put in the tree once.
  Widget get view;

  void dispose();
}

/// The two native layouts.
enum NativeLayout { small, medium }

/// Colours for a native ad (ARGB values).
@immutable
class NativeColors {
  const NativeColors({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.buttonBackground,
    required this.buttonText,
  });

  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color buttonBackground;
  final Color buttonText;

  @override
  bool operator ==(Object other) =>
      other is NativeColors &&
      other.background == background &&
      other.primaryText == primaryText &&
      other.secondaryText == secondaryText &&
      other.buttonBackground == buttonBackground &&
      other.buttonText == buttonText;

  @override
  int get hashCode => Object.hash(
    background,
    primaryText,
    secondaryText,
    buttonBackground,
    buttonText,
  );
}

/// The ads SDK, reduced to what IDSnap uses. `GoogleAdsPlatform` is the
/// real one; tests use a fake, so no test needs the plugin.
///
/// No method may throw: an ads failure must never reach the user.
abstract interface class AdsPlatform {
  /// Asks the consent platform for the current requirement (network).
  /// False when it couldn't be reached.
  Future<bool> requestConsentInfoUpdate();

  /// Loads and shows the consent form when one is required; returns when
  /// it is closed (immediately when none is required).
  Future<void> showConsentFormIfRequired();

  Future<PlatformConsentStatus> consentStatus();

  /// Whether consent was gathered or isn't needed, so ads may be requested.
  Future<bool> canRequestAds();

  /// Whether the app must offer a way to reopen the privacy options form.
  Future<bool> privacyOptionsRequired();

  /// Reopens the privacy options form; returns when it is closed.
  Future<void> showPrivacyOptionsForm();

  /// False when the user's choices don't allow personalised ads; requests
  /// must then ask for non-personalised ads.
  Future<bool> personalizedAdsAllowed();

  /// Starts the ads SDK. Called only after [canRequestAds] is true.
  Future<void> initializeSdk({required List<String> testDeviceIds});

  /// Height in logical pixels of the anchored adaptive banner for
  /// [width], or null if this device can't show one.
  Future<double?> bannerHeight(int width);

  /// A banner that loads itself, reports the outcome once and disposes its
  /// native view with the widget.
  Widget banner({
    required String unitId,
    required int width,
    required bool nonPersonalized,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  });

  /// Null when no ad could be loaded.
  Future<PlatformInterstitial?> loadInterstitial({
    required String unitId,
    required bool nonPersonalized,
  });

  /// Null when no ad could be loaded.
  Future<PlatformNative?> loadNative({
    required String unitId,
    required NativeLayout layout,
    required NativeColors colors,
    required bool nonPersonalized,
  });
}
