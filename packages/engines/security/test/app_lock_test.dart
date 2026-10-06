import 'dart:async';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeAuth implements DeviceAuthenticator {
  _FakeAuth({this.supported = true, this.error});

  bool supported;
  bool result = true;
  Exception? error;
  String? lastReason;
  Completer<bool>? gate;
  int calls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    lastReason = reason;
    calls++;
    if (error != null) throw error!;
    if (gate != null) return await gate!.future;
    return result;
  }
}

void main() {
  LocalAuthAppLock lock(_FakeAuth a) =>
      LocalAuthAppLock(authenticator: a, isSupportedPlatform: true);

  test('success and cancel', () async {
    final a = _FakeAuth();
    expect((await lock(a).authenticate('Unlock DocScan')).valueOrNull, isTrue);
    expect(a.lastReason, 'Unlock DocScan');
    a.result = false;
    expect((await lock(a).authenticate('x')).valueOrNull, isFalse);
  });

  test('user/system cancel map to Ok(false), not an error', () async {
    for (final code in [
      LocalAuthExceptionCode.userCanceled,
      LocalAuthExceptionCode.systemCanceled,
      LocalAuthExceptionCode.timeout,
    ]) {
      final r = await lock(
        _FakeAuth(error: LocalAuthException(code: code)),
      ).authenticate('x');
      expect(r.valueOrNull, isFalse, reason: code.name);
    }
  });

  test('no screen lock → actionable permissionDenied', () async {
    final r = await lock(
      _FakeAuth(
        error: const LocalAuthException(
          code: LocalAuthExceptionCode.noCredentialsSet,
        ),
      ),
    ).authenticate('x');
    expect(r.failureOrNull?.code, FailureCode.permissionDenied);
    expect(r.failureOrNull?.detail, LocalAuthAppLock.setUpScreenLock);
  });

  test('lockout has its own message', () async {
    final r = await lock(
      _FakeAuth(
        error: const LocalAuthException(
          code: LocalAuthExceptionCode.biometricLockout,
        ),
      ),
    ).authenticate('x');
    expect(r.failureOrNull?.detail, LocalAuthAppLock.lockedOut);
  });

  test('capability reflects device support and platform', () async {
    expect((await lock(_FakeAuth()).capability()).available, isTrue);
    final unsupported = await lock(_FakeAuth(supported: false)).capability();
    expect(unsupported.available, isFalse);
    expect(unsupported.note, LocalAuthAppLock.setUpScreenLock);
    final desktop = LocalAuthAppLock(
      authenticator: _FakeAuth(),
      isSupportedPlatform: false,
    );
    expect((await desktop.capability()).available, isFalse);
    expect((await desktop.authenticate('x')).isOk, isFalse);
  });

  test('every exception code is mapped', () {
    for (final code in LocalAuthExceptionCode.values) {
      expect(() => mapAuthException(code), returnsNormally);
    }
  });

  test('each error code maps to the right user-facing message', () {
    String? detail(LocalAuthExceptionCode c) =>
        mapAuthException(c).fold((ok) => null, (f) => f.detail);
    expect(
      detail(LocalAuthExceptionCode.noCredentialsSet),
      LocalAuthAppLock.setUpScreenLock,
    );
    expect(
      detail(LocalAuthExceptionCode.noBiometricsEnrolled),
      LocalAuthAppLock.biometricsNotSetUp,
    );
    expect(
      detail(LocalAuthExceptionCode.noBiometricHardware),
      LocalAuthAppLock.biometricsNotSetUp,
    );
    expect(
      detail(LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable),
      LocalAuthAppLock.biometricsUnavailable,
    );
    expect(
      detail(LocalAuthExceptionCode.temporaryLockout),
      LocalAuthAppLock.temporarilyLockedOut,
    );
    expect(
      detail(LocalAuthExceptionCode.biometricLockout),
      LocalAuthAppLock.lockedOut,
    );
    expect(
      detail(LocalAuthExceptionCode.uiUnavailable),
      LocalAuthAppLock.promptUnavailable,
    );
    expect(
      detail(LocalAuthExceptionCode.deviceError),
      LocalAuthAppLock.couldNotVerify,
    );
    expect(
      detail(LocalAuthExceptionCode.unknownError),
      LocalAuthAppLock.couldNotVerify,
    );
    // Cancels are never errors (stay locked, show "Unlock").
    for (final c in [
      LocalAuthExceptionCode.userCanceled,
      LocalAuthExceptionCode.systemCanceled,
      LocalAuthExceptionCode.timeout,
      LocalAuthExceptionCode.userRequestedFallback,
      LocalAuthExceptionCode.authInProgress,
    ]) {
      expect(mapAuthException(c).valueOrNull, isFalse, reason: c.name);
    }
    // Every failure has a message.
    for (final c in LocalAuthExceptionCode.values) {
      mapAuthException(c).fold((_) {}, (f) => expect(f.detail, isNotNull));
    }
  });

  test('unexpected platform errors get a retry message', () async {
    final r = await lock(
      _FakeAuth(error: PlatformException(code: 'boom')),
    ).authenticate('x');
    expect(r.failureOrNull?.detail, LocalAuthAppLock.couldNotVerify);
  });

  test('concurrent calls share one system prompt', () async {
    final a = _FakeAuth()..gate = Completer<bool>();
    final l = lock(a);
    final first = l.authenticate('App Lock');
    final second = l.authenticate('Show codes');
    expect(l.isAuthenticating, isTrue);
    a.gate!.complete(true);
    expect((await first).valueOrNull, isTrue);
    expect((await second).valueOrNull, isTrue);
    expect(a.calls, 1);
    expect(l.isAuthenticating, isFalse);
    // A later call prompts again.
    a.gate = null;
    await l.authenticate('again');
    expect(a.calls, 2);
  });

  test(
    'recentlyAuthenticated uses the larger of monotonic and wall time',
    () async {
      var mono = Duration.zero;
      var wall = DateTime(2026, 9, 28, 12);
      final a = _FakeAuth();
      final l = LocalAuthAppLock(
        authenticator: a,
        isSupportedPlatform: true,
        monotonicClock: () => mono,
        wallClock: () => wall,
      );
      expect(l.recentlyAuthenticated(), isFalse);
      // Through the AppLock-typed extension too.
      final AppLock asPort = l;
      expect(asPort.recentlyAuthenticated(), isFalse);

      await l.authenticate('x');
      expect(asPort.recentlyAuthenticated(), isTrue);
      mono += const Duration(seconds: 3);
      wall = wall.add(const Duration(seconds: 3));
      expect(l.recentlyAuthenticated(), isTrue);
      expect(
        l.recentlyAuthenticated(within: const Duration(seconds: 2)),
        isFalse,
      );

      // Phone slept: monotonic barely moved, wall clock says an hour.
      wall = wall.add(const Duration(hours: 1));
      expect(l.recentlyAuthenticated(), isFalse);

      // Cancelled prompts don't count as an unlock.
      await l.authenticate('x');
      a.result = false;
      mono += const Duration(minutes: 10);
      wall = wall.add(const Duration(minutes: 10));
      await l.authenticate('x');
      expect(l.recentlyAuthenticated(), isFalse);

      // Wall clock moved backwards: not trusted.
      a.result = true;
      await l.authenticate('x');
      wall = wall.subtract(const Duration(minutes: 1));
      expect(l.recentlyAuthenticated(), isFalse);
    },
  );

  test('plain AppLock fakes answer "no" through the extension', () {
    final AppLock fake = _PlainLock();
    expect(fake.recentlyAuthenticated(), isFalse);
    expect(fake.isAuthenticating, isFalse);
  });
}

class _PlainLock implements AppLock {
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async => const Ok(true);
}
