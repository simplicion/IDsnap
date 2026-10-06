import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hides app content from the app switcher and screenshots. Implemented by
/// the host app on channel [channelName]:
///
/// - Android (`MainActivity`): `setSecure` toggles `FLAG_SECURE` (blocks
///   screenshots / screen recording, blanks the recent-apps thumbnail).
///   `consumeExternalLaunch` reports whether IDSnap itself just opened
///   another activity (file picker, camera, share sheet, document scanner)
///   so the lock gate doesn't treat that as leaving the app.
/// - iOS (`AppDelegate`): `setSecure` enables a cover view that is placed
///   over the window when the app resigns active, so the app-switcher
///   snapshot shows no content.
///
/// A no-op elsewhere.
class SecureWindow {
  const SecureWindow([MethodChannel? channel, bool? isSupportedPlatform])
    : _channel = channel ?? const MethodChannel(channelName),
      _supported = isSupportedPlatform;

  /// Must match `MainActivity.kt` and `AppDelegate.swift`.
  static const channelName = 'docscan/secure_window';

  final MethodChannel _channel;
  final bool? _supported;

  bool get _platformOk =>
      _supported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  bool get _isAndroid => _supported ?? (!kIsWeb && Platform.isAndroid);

  Future<void> setSecure({required bool enabled}) async {
    if (!_platformOk) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      // Host doesn't implement the channel (e.g. tests).
    } on PlatformException {
      // Best effort: the lock screen still protects the UI.
    }
  }

  /// True (once) when the app was sent to the background by an activity
  /// IDSnap started itself. Android only; false elsewhere or on error.
  Future<bool> consumeExternalLaunch() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('consumeExternalLaunch') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
