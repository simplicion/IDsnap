import 'dart:async';

import 'package:clock/clock.dart';
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The clipboard helpers moved to the design system so secure notes can reuse
// them; re-exported so existing imports keep working.
export 'package:docscan_design_system/docscan_design_system.dart'
    show ClipboardAccess, SecureClipboard, SystemClipboardAccess;

// Feature-local seams. The app overrides the platform ones in its bootstrap;
// tests override them with fakes.

/// Wall clock for code generation and the countdown rings.
final authenticatorClockProvider = Provider<Clock>((ref) => const Clock());

/// Toggles Android `FLAG_SECURE` (the app passes `SecureWindow().setSecure`).
typedef SecureFlagSetter = Future<void> Function({required bool enabled});

Future<void> _noopSecure({required bool enabled}) async {}

final secureFlagSetterProvider = Provider<SecureFlagSetter>(
  (ref) => _noopSecure,
);

/// Reference-counted FLAG_SECURE: on while at least one authenticator
/// surface is visible; when the last one goes away the flag returns to what
/// App Lock wants (on when App Lock is enabled, off otherwise).
class SecureFlagController {
  SecureFlagController(this._set, this._baseline);

  final SecureFlagSetter _set;
  final bool Function() _baseline;
  int _holders = 0;

  bool get isSecure => _holders > 0;

  void acquire() {
    if (_holders++ == 0) unawaited(_set(enabled: true));
  }

  void release() {
    if (_holders == 0) return;
    if (--_holders == 0) unawaited(_set(enabled: _baseline()));
  }
}

final secureFlagControllerProvider = Provider<SecureFlagController>(
  (ref) => SecureFlagController(
    ref.watch(secureFlagSetterProvider),
    () => ref.read(currentSettingsProvider).appLock,
  ),
);

final clipboardAccessProvider = Provider<ClipboardAccess>(
  (ref) => const SystemClipboardAccess(),
);

/// App-lifetime so the 60 s clear still happens after leaving the screen.
final secureClipboardProvider = Provider<SecureClipboard>((ref) {
  final c = SecureClipboard(ref.watch(clipboardAccessProvider));
  ref.onDispose(c.dispose);
  return c;
});

/// Camera + image QR decoding, implemented in the app (bundled, offline
/// barcode model). The default reports "unavailable" so the manual path is
/// always offered.
abstract interface class QrScanner {
  Future<EngineCapability> capability();

  /// A live camera preview that calls [onDetect] with each QR payload and
  /// [onError] when the camera can't start.
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onDetect,
    required ValueChanged<AppFailure> onError,
  });

  /// Decodes the first QR code in the image at [path]; `Ok(null)` when the
  /// picture has none.
  Future<Result<String?>> decodeImage(String path);
}

class UnavailableQrScanner implements QrScanner {
  const UnavailableQrScanner();

  @override
  Future<EngineCapability> capability() async => const EngineCapability(
    available: false,
    worksOffline: true,
    note: 'QR scanning is not available on this device.',
  );

  @override
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onDetect,
    required ValueChanged<AppFailure> onError,
  }) => const SizedBox.expand();

  @override
  Future<Result<String?>> decodeImage(String path) async =>
      const Err(AppFailure(FailureCode.cameraUnavailable));
}

final qrScannerProvider = Provider<QrScanner>(
  (ref) => const UnavailableQrScanner(),
);

// ── Data ────────────────────────────────────────────────────────────────────

final otpAccountsProvider = StreamProvider<List<OtpAccount>>(
  (ref) => ref.watch(authenticatorRepositoryProvider).watchAccounts(),
);

/// Decoded secret per account, held in memory only while a screen needs it.
final otpSecretProvider = FutureProvider.autoDispose
    .family<Result<Uint8List>, OtpAccount>(
      (ref, account) =>
          ref.watch(authenticatorRepositoryProvider).readSecret(account),
    );

/// Whether biometric / device-credential auth is possible on this device.
final authCapabilityProvider = FutureProvider<EngineCapability>(
  (ref) => ref.watch(appLockProvider).capability(),
);

/// Session-level "codes revealed" flag. Reset when the user leaves the
/// authenticator or the app goes to the background.
class RevealController extends Notifier<bool> {
  @override
  bool build() => false;

  void reveal() => state = true;
  void hide() => state = false;
}

final revealProvider = NotifierProvider<RevealController, bool>(
  RevealController.new,
);

/// Formats a code for display: "123 456", "1234 5678".
String groupCode(String code) {
  if (code.length < 6) return code;
  final half = code.length ~/ 2;
  return '${code.substring(0, half)} ${code.substring(half)}';
}
