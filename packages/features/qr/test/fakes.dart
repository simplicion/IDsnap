import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Scanner whose preview hands its callbacks to the test.
class FakeCodeScanner implements CodeScanner {
  FakeCodeScanner({this.available = true, this.imageCodes = const []});

  final bool available;
  List<ScannedCode> imageCodes;
  ValueChanged<List<ScannedCode>>? onDetect;
  CodeScannerController? controller;
  final decodedPaths = <String>[];

  void detect(ScannedCode code) => onDetect!([code]);

  @override
  Future<EngineCapability> capability() async =>
      EngineCapability(available: available, worksOffline: true);

  @override
  Widget buildPreview(
    BuildContext context, {
    required CodeScannerController controller,
    required ValueChanged<List<ScannedCode>> onDetect,
    required ValueChanged<AppFailure> onError,
  }) {
    this.onDetect = onDetect;
    this.controller = controller;
    return const ColoredBox(key: ValueKey('fake-preview'), color: Colors.black);
  }

  @override
  Future<Result<List<ScannedCode>>> decodeImage(String path) async {
    decodedPaths.add(path);
    return Ok(imageCodes);
  }
}

/// Records every outside action instead of performing it.
class FakeQrActions implements QrActions {
  final copied = <String>[];
  final sharedText = <String>[];
  final sharedFiles = <({Uint8List bytes, String extension})>[];
  final saved = <String>[];
  final vault = <({Uint8List bytes, DocumentFormat format, String name})>[];
  final opened = <Uri>[];
  bool openResult = true;

  @override
  Future<Result<void>> copy(String text) async {
    copied.add(text);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareText(String text) async {
    sharedText.add(text);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFile(
    Uint8List bytes, {
    required String extension,
    String? subject,
  }) async {
    sharedFiles.add((bytes: bytes, extension: extension));
    return const Ok(null);
  }

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) async {
    saved.add(fileName);
    return const Ok(true);
  }

  @override
  Future<Result<Document>> saveToVault(
    Uint8List bytes, {
    required DocumentFormat format,
    required String name,
    String? folderId,
  }) async {
    vault.add((bytes: bytes, format: format, name: name));
    final now = DateTime(2026);
    return Ok(
      Document(
        id: 'd${vault.length}',
        name: name,
        format: format,
        relativePath: 'documents/x',
        sizeBytes: bytes.length,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return openResult;
  }
}

class FakePicker implements MediaPicker {
  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      const Ok([PickedFile(path: '/tmp/codes.png', name: 'codes.png')]);

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async => const Ok([PickedFile(path: '/tmp/file.jpg', name: 'file.jpg')]);
}

/// Only [add] is used by the QR tool.
class FakeAuthenticatorRepository implements AuthenticatorRepository {
  final added = <NewOtpAccount>[];

  @override
  Future<Result<OtpAccount>> add(NewOtpAccount account) async {
    added.add(account);
    return Ok(
      OtpAccount(
        id: 'a1',
        label: account.label,
        issuer: account.issuer,
        secretKeyId: 'k1',
        createdAt: DateTime(2026),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  Harness({
    FakeCodeScanner? scanner,
    QrHistoryState history = const QrHistoryState(),
  }) : scanner = scanner ?? FakeCodeScanner(),
       store = MemoryQrHistoryStore(history);

  final FakeCodeScanner scanner;
  final MemoryQrHistoryStore store;
  final actions = FakeQrActions();
  final authenticator = FakeAuthenticatorRepository();

  List<Override> get overrides => [
    codeScannerProvider.overrideWithValue(scanner),
    qrActionsProvider.overrideWithValue(actions),
    qrHistoryStoreProvider.overrideWithValue(store),
    mediaPickerProvider.overrideWithValue(FakePicker()),
    otpCodecProvider.overrideWithValue(const OtpCodecImpl()),
    authenticatorRepositoryProvider.overrideWithValue(authenticator),
    useAppleMapsProvider.overrideWithValue(false),
  ];

  /// Pumps the tool at [location] inside a router like the app's.
  Future<GoRouter> pump(
    WidgetTester tester, {
    String location = Routes.qrScanner,
    GoRouterRedirect? redirect,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: location,
      routes: [
        GoRoute(
          path: Routes.tools,
          builder: (context, state) => const Scaffold(body: Text('Tools')),
          routes: qrRoutes(rootKey, redirect: redirect),
        ),
        GoRoute(
          path: Routes.authenticator,
          builder: (context, state) =>
              const Scaffold(body: Text('Authenticator home')),
        ),
        GoRoute(
          path: '/paywall',
          builder: (context, state) => const Scaffold(body: Text('Paywall')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const wifiCode = ScannedCode(
  raw: 'WIFI:S:HomeNet;T:WPA;P:hunter22;;',
  symbology: CodeSymbology.qr,
);
const textCode = ScannedCode(raw: 'Hello there', symbology: CodeSymbology.qr);
const otpCode = ScannedCode(
  raw:
      'otpauth://totp/GitHub:me@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
  symbology: CodeSymbology.qr,
);
