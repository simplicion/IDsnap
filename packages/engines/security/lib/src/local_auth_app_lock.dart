import 'dart:async';
import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin seam over `local_auth` so the mapping logic is testable.
abstract interface class DeviceAuthenticator {
  Future<bool> isDeviceSupported();

  /// Throws [LocalAuthException] on failure, returns false when not
  /// authenticated.
  Future<bool> authenticate(String reason);
}

class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  // True when the phone has a screen lock (PIN / pattern / password) or
  // enrolled biometrics — i.e. there is something to authenticate with.
  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  // biometricOnly: false → the system prompt offers PIN / pattern / password
  // as a fallback, so users without biometrics can still use App Lock.
  // persistAcrossBackgrounding: the plugin re-shows the prompt when the app
  // returns instead of failing, so leaving mid-prompt isn't a cancel.
  @override
  Future<bool> authenticate(String reason) => _auth.authenticate(
    localizedReason: reason,
    persistAcrossBackgrounding: true,
  );
}

final Stopwatch _uptime = Stopwatch()..start();
Duration _monotonicNow() => _uptime.elapsed;

/// [AppLock] backed by Android BiometricPrompt / iOS LocalAuthentication.
///
/// This is an access gate, not encryption. Cancellation is `Ok(false)`, never
/// an error; configuration problems are typed failures with an actionable
/// detail message.
///
/// Only one system prompt is ever shown: a call made while a prompt is on
/// screen joins it and receives the same result. It also remembers the last
/// successful unlock ([recentlyAuthenticated]) so nested gates don't prompt
/// twice in a row.
class LocalAuthAppLock implements AppLock, AppLockSession {
  LocalAuthAppLock({
    DeviceAuthenticator? authenticator,
    @visibleForTesting bool? isSupportedPlatform,
    RedactedLogger? logger,
    @visibleForTesting Duration Function()? monotonicClock,
    @visibleForTesting DateTime Function()? wallClock,
  }) : _auth = authenticator ?? LocalAuthDeviceAuthenticator(),
       _platformOk =
           isSupportedPlatform ??
           (!kIsWeb && (Platform.isAndroid || Platform.isIOS)),
       _log = logger ?? RedactedLogger('app_lock'),
       _mono = monotonicClock ?? _monotonicNow,
       _wall = wallClock ?? DateTime.now;

  static const setUpScreenLock =
      'Set a screen lock (PIN, pattern, password or biometrics) in your '
      "phone's settings first.";

  /// Biometrics locked until another authentication succeeds.
  static const lockedOut =
      'Too many attempts. Fingerprint and face unlock are paused. Try again '
      "and use your phone's PIN, pattern or password instead.";

  /// Short (about 30 s) lockout after repeated failed attempts.
  static const temporarilyLockedOut =
      'Too many attempts. Wait 30 seconds, then try again.';

  static const biometricsNotSetUp =
      "Fingerprint or face unlock isn't set up on this phone, or was changed. "
      "Try again and use your phone's PIN, pattern or password instead.";

  static const biometricsUnavailable =
      "Fingerprint or face unlock isn't available right now. Try again and "
      "use your phone's PIN, pattern or password instead.";

  static const promptUnavailable =
      "The unlock prompt couldn't be shown. Try again.";

  static const couldNotVerify = "Couldn't verify it's you. Try again.";

  /// Title for verification failures that aren't the user's choice.
  static const notVerified = 'Not verified';

  static const unsupportedPlatform =
      'App Lock is available on Android and iOS.';

  final DeviceAuthenticator _auth;
  final bool _platformOk;
  final RedactedLogger _log;
  final Duration Function() _mono;
  final DateTime Function() _wall;

  Future<Result<bool>>? _inFlight;
  Duration? _lastOkMono;
  DateTime? _lastOkWall;

  @override
  bool get isAuthenticating => _inFlight != null;

  @override
  bool recentlyAuthenticated({
    Duration within = AppLockSession.defaultRecentWindow,
  }) {
    final mono = _lastOkMono;
    final wall = _lastOkWall;
    if (mono == null || wall == null) return false;
    final monoAgo = _mono() - mono;
    final wallAgo = _wall().difference(wall);
    // Clock moved backwards: don't trust it.
    if (wallAgo.isNegative) return false;
    // The monotonic clock may stop while the phone sleeps; the wall clock
    // doesn't. The larger of the two is the safe answer.
    final ago = monoAgo > wallAgo ? monoAgo : wallAgo;
    return ago < within;
  }

  @override
  Future<EngineCapability> capability() async {
    if (!_platformOk) {
      return const EngineCapability(
        available: false,
        worksOffline: true,
        note: unsupportedPlatform,
      );
    }
    try {
      final supported = await _auth.isDeviceSupported();
      return EngineCapability(
        available: supported,
        worksOffline: true,
        note: supported ? null : setUpScreenLock,
      );
    } on Object {
      return const EngineCapability(
        available: false,
        worksOffline: true,
        note: setUpScreenLock,
      );
    }
  }

  @override
  Future<Result<bool>> authenticate(String reason) {
    // Re-entrancy guard: join the prompt that's already on screen.
    final pending = _inFlight;
    if (pending != null) return pending;
    final attempt = _authenticate(reason);
    _inFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_inFlight, attempt)) _inFlight = null;
    });
  }

  Future<Result<bool>> _authenticate(String reason) async {
    if (!_platformOk) {
      return const Err(
        AppFailure(
          FailureCode.offlineDependencyUnavailable,
          detail: unsupportedPlatform,
        ),
      );
    }
    try {
      final ok = await _auth.authenticate(reason);
      _log.info('authenticate', {'ok': ok});
      if (ok) {
        _lastOkMono = _mono();
        _lastOkWall = _wall();
      }
      return Ok(ok);
    } on LocalAuthException catch (e, st) {
      _log.warn('auth_error', {'code': e.code});
      return mapAuthException(e.code, e, st);
    } on PlatformException catch (e, st) {
      _log.warn('auth_platform_error', {'code': e.code});
      return Err(
        AppFailure(
          FailureCode.unknown,
          detail: couldNotVerify,
          cause: e,
          stackTrace: st,
          heading: notVerified,
          message: couldNotVerify,
        ),
      );
    } on Object catch (e, st) {
      return Err(
        AppFailure(
          FailureCode.unknown,
          detail: couldNotVerify,
          cause: e,
          stackTrace: st,
          heading: notVerified,
          message: couldNotVerify,
        ),
      );
    }
  }
}

/// Maps `local_auth` error codes to domain results. Every failure carries a
/// user-facing [AppFailure.detail].
@visibleForTesting
Result<bool> mapAuthException(
  LocalAuthExceptionCode code, [
  Object? cause,
  StackTrace? st,
]) {
  Result<bool> fail(FailureCode c, String detail) => Err(
    AppFailure(
      c,
      detail: detail,
      cause: cause,
      stackTrace: st,
      // Not "Something went wrong": say what failed (audit M-04).
      heading: c == FailureCode.unknown ? LocalAuthAppLock.notVerified : null,
      message: c == FailureCode.unknown ? detail : null,
    ),
  );
  return switch (code) {
    // Dismissed, backgrounded or "use fallback": not an error, stay locked.
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.userRequestedFallback ||
    LocalAuthExceptionCode.authInProgress => const Ok(false),
    LocalAuthExceptionCode.noCredentialsSet => fail(
      FailureCode.permissionDenied,
      LocalAuthAppLock.setUpScreenLock,
    ),
    LocalAuthExceptionCode.noBiometricsEnrolled ||
    LocalAuthExceptionCode.noBiometricHardware => fail(
      FailureCode.permissionDenied,
      LocalAuthAppLock.biometricsNotSetUp,
    ),
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable => fail(
      FailureCode.unknown,
      LocalAuthAppLock.biometricsUnavailable,
    ),
    LocalAuthExceptionCode.temporaryLockout => fail(
      FailureCode.permissionDenied,
      LocalAuthAppLock.temporarilyLockedOut,
    ),
    LocalAuthExceptionCode.biometricLockout => fail(
      FailureCode.permissionDenied,
      LocalAuthAppLock.lockedOut,
    ),
    LocalAuthExceptionCode.uiUnavailable => fail(
      FailureCode.unknown,
      LocalAuthAppLock.promptUnavailable,
    ),
    LocalAuthExceptionCode.deviceError || LocalAuthExceptionCode.unknownError =>
      fail(FailureCode.unknown, LocalAuthAppLock.couldNotVerify),
  };
}
