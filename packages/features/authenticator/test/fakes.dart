import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const secretA = 'JBSWY3DPEHPK3PXP';
const codec = OtpCodecImpl();

/// In-memory [AuthenticatorRepository] with a fake keystore.
class FakeAuthenticatorRepository implements AuthenticatorRepository {
  final accounts = <OtpAccount>[];
  final secrets = <String, String>{};
  final recovery = <String, List<RecoveryCode>>{};
  final _changes = StreamController<void>.broadcast();
  var _seq = 0;

  OtpAccount seed(NewOtpAccount a) {
    final id = 'a${_seq++}';
    final account = OtpAccount(
      id: id,
      label: a.label,
      issuer: a.issuer,
      secretKeyId: 'otp.$id',
      type: a.type,
      algorithm: a.algorithm,
      digits: a.digits,
      period: a.period,
      counter: a.counter,
      sortOrder: accounts.length,
      createdAt: DateTime(2026),
    );
    accounts.add(account);
    secrets[account.secretKeyId] = codec.normalizeSecret(a.secret).valueOrNull!;
    _changes.add(null);
    return account;
  }

  @override
  Stream<List<OtpAccount>> watchAccounts() async* {
    yield [...accounts];
    await for (final _ in _changes.stream) {
      yield [...accounts];
    }
  }

  @override
  Future<Result<OtpAccount>> add(NewOtpAccount account) async {
    final n = codec.normalizeSecret(account.secret);
    if (n case Err(:final failure)) return Err(failure);
    return Ok(seed(account));
  }

  @override
  Future<Result<void>> rename(
    String id, {
    required String label,
    String? issuer,
  }) async {
    final i = accounts.indexWhere((a) => a.id == id);
    accounts[i] = accounts[i].copyWith(
      label: label,
      issuer: issuer,
      clearIssuer: issuer == null || issuer.isEmpty,
    );
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<int>> incrementCounter(String id) async {
    final i = accounts.indexWhere((a) => a.id == id);
    accounts[i] = accounts[i].copyWith(counter: accounts[i].counter + 1);
    _changes.add(null);
    return Ok(accounts[i].counter);
  }

  @override
  Future<Result<void>> remove(String id) async {
    final a = accounts.firstWhere((a) => a.id == id);
    accounts.remove(a);
    secrets.remove(a.secretKeyId);
    recovery.remove(a.secretKeyId);
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<Uint8List>> readSecret(OtpAccount account) async {
    final s = secrets[account.secretKeyId];
    if (s == null) return const Err(AppFailure(FailureCode.secretUnavailable));
    return codec.decodeSecret(s);
  }

  @override
  Future<Result<List<RecoveryCode>>> readRecoveryCodes(
    OtpAccount account,
  ) async => Ok([...?recovery[account.secretKeyId]]);

  @override
  Future<Result<void>> saveRecoveryCodes(
    OtpAccount account,
    List<RecoveryCode> codes,
  ) async {
    recovery[account.secretKeyId] = [...codes];
    return const Ok(null);
  }
}

class FakeAppLock implements AppLock {
  FakeAppLock({this.available = true, this.results = const []});

  bool available;

  /// Results returned in order; `Ok(true)` once exhausted.
  List<Result<bool>> results;
  int calls = 0;

  @override
  Future<EngineCapability> capability() async =>
      EngineCapability(available: available, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async {
    final r = calls < results.length ? results[calls] : const Ok(true);
    calls++;
    return r;
  }
}

class FakeClipboard implements ClipboardAccess {
  String? text;
  final writes = <String>[];

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String t) async {
    writes.add(t);
    text = t;
  }
}

class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.settings = const AppSettings()]);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings s) async => settings = s;
}

class FakeQrScanner implements QrScanner {
  FakeQrScanner({this.available = true, this.imageResult = const Ok(null)});

  bool available;
  Result<String?> imageResult;
  ValueChanged<String>? onDetect;

  @override
  Future<EngineCapability> capability() async =>
      EngineCapability(available: available, worksOffline: true);

  @override
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onDetect,
    required ValueChanged<AppFailure> onError,
  }) {
    this.onDetect = onDetect;
    return const ColoredBox(color: Colors.black, child: Text('camera'));
  }

  @override
  Future<Result<String?>> decodeImage(String path) async => imageResult;
}

class FakePicker implements MediaPicker {
  List<PickedFile> images = const [
    PickedFile(path: '/p/qr.png', name: 'qr.png'),
  ];

  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      Ok(images);

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async => const Ok([]);
}

/// Records FLAG_SECURE changes.
class SecureLog {
  final calls = <bool>[];

  Future<void> set({required bool enabled}) async => calls.add(enabled);
}

/// Everything a test may want to poke at.
class Env {
  Env({FakeAppLock? lock, AppSettings settings = const AppSettings()})
    : lock = lock ?? FakeAppLock(),
      settings = FakeSettingsStore(settings);

  final repo = FakeAuthenticatorRepository();
  final FakeAppLock lock;
  final FakeSettingsStore settings;
  final clipboard = FakeClipboard();
  final qr = FakeQrScanner();
  final picker = FakePicker();
  final secure = SecureLog();

  /// 5 s into a 30 s step: 25 s left on the ring.
  static final base = DateTime.utc(2026, 1, 1, 0, 0, 5);

  List<Override> overrides(WidgetTester tester) {
    final start = tester.binding.clock.now();
    return [
      authenticatorRepositoryProvider.overrideWithValue(repo),
      otpCodecProvider.overrideWithValue(codec),
      appLockProvider.overrideWithValue(lock),
      settingsStoreProvider.overrideWithValue(settings),
      clipboardAccessProvider.overrideWithValue(clipboard),
      qrScannerProvider.overrideWithValue(qr),
      mediaPickerProvider.overrideWithValue(picker),
      secureFlagSetterProvider.overrideWithValue(secure.set),
      authenticatorClockProvider.overrideWithValue(
        Clock(() => base.add(tester.binding.clock.now().difference(start))),
      ),
    ];
  }

  /// The authenticator tab plus its sub-routes and an "other tab" route.
  Future<GoRouter> pump(
    WidgetTester tester, {
    String initial = Routes.authenticator,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: initial,
      routes: [
        // Mirrors the app: tabs in an indexed-stack shell, sub-pages pushed
        // on the root navigator.
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.authenticator,
                  builder: (context, state) => const AuthenticatorScreen(),
                  routes: authenticatorRoutes(rootKey),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/other',
                  builder: (context, state) =>
                      const Scaffold(body: Text('other tab')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(tester),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
    return router;
  }
}

/// Pumps enough frames for streams, futures and route transitions without
/// waiting for the (never-ending) countdown ticker to settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String expectedTotp(DateTime at, {String secret = secretA}) =>
    codec.totp(codec.decodeSecret(secret).valueOrNull!, at: at);
