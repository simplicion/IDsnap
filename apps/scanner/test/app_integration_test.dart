import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/app.dart';
import 'package:drift/native.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps a bounded number of frames, letting real async work (file IO,
/// Drift) progress between them. Unlike pumpAndSettle it tolerates
/// indeterminate spinners.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Boots the real app (router, every feature, real data layer, real imaging
/// and conversion engines). Only platform plugins are faked.
void main() {
  late Directory root;
  late DataLayer data;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('docscan_it');
    data = await openDataLayer(
      rootOverride: root.path,
      executor: NativeDatabase.memory(),
    );
  });

  tearDown(() async {
    await data.close();
    await root.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    const images = ImagingEngine();
    final pdf = _FakePdf();
    final conversion = ConversionEngineImpl(
      files: data.files,
      pdf: pdf,
      images: images,
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(data.documents),
          draftStoreProvider.overrideWithValue(data.drafts),
          settingsStoreProvider.overrideWithValue(data.settings),
          fileStoreProvider.overrideWithValue(data.files),
          imageProcessorProvider.overrideWithValue(images),
          pdfEngineProvider.overrideWithValue(pdf),
          textRecognizerProvider.overrideWithValue(_FakeOcr()),
          documentScannerProvider.overrideWithValue(_FakeScanner()),
          mediaPickerProvider.overrideWithValue(_FakePicker()),
          shareServiceProvider.overrideWithValue(_FakeShare()),
          conversionEngineProvider.overrideWithValue(conversion),
          faceLocatorProvider.overrideWithValue(_FakeFace()),
          appLockProvider.overrideWithValue(_FakeLock()),
          otpCodecProvider.overrideWithValue(const OtpCodecImpl()),
          authenticatorRepositoryProvider.overrideWithValue(
            DriftAuthenticatorRepository(
              data.database,
              secrets: _MemorySecrets(),
              codec: const OtpCodecImpl(),
            ),
          ),
        ],
        child: const DocScanApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
  }

  /// Drift closes stream queries on a zero-length timer; unmount and flush
  /// it so the test binding doesn't report a pending timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('all four tabs render', (tester) async {
    await pumpApp(tester);
    expect(find.text('Scan a document'), findsOneWidget);
    // Settings is no longer a tab.
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
      findsNothing,
    );
    for (final tab in ['Authenticator', 'ID Vault', 'Tools', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$tab tab threw');
    }
    await unmount(tester);
  });

  testWidgets('every tool screen opens without errors', (tester) async {
    await pumpApp(tester);
    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    final locations = [
      for (final t in ToolId.values) Routes.tool(t),
      Routes.convert('pdf-to-docx'),
      Routes.convert('txt-to-pdf'),
      Routes.settings,
      Routes.privacy,
      Routes.about,
      Routes.authenticator,
      Routes.authenticatorAdd,
      Routes.authenticatorScan,
      Routes.qrScanner,
      Routes.qrGenerate,
      Routes.qrHistory,
    ];
    for (final location in locations) {
      router.go(location);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$location threw');
      expect(find.byType(Scaffold), findsWidgets, reason: location);
    }
    await unmount(tester);
  });

  testWidgets('Home gear pushes Settings full-screen over the shell', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Authenticator tab shows a stored account and its code', (
    tester,
  ) async {
    await pumpApp(tester);
    final repo = DriftAuthenticatorRepository(
      data.database,
      secrets: _MemorySecrets(),
      codec: const OtpCodecImpl(),
    );
    await tester.runAsync(
      () => repo.add(
        const NewOtpAccount(
          label: 'me@example.com',
          issuer: 'GitHub',
          secret: 'JBSWY3DPEHPK3PXP',
        ),
      ),
    );
    await tester.tap(find.text('Authenticator').last);
    await settle(tester);
    expect(find.text('GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a committed document appears in Files and opens', (
    tester,
  ) async {
    final commit = CommitOutput(
      files: data.files,
      repository: data.documents,
      pdf: _FakePdf(),
      images: const ImagingEngine(),
    );
    final doc = await tester.runAsync(
      () => commit(
        OutputFile(
          bytes: Uint8List.fromList('Hello offline world'.codeUnits),
          format: DocumentFormat.txt,
          suggestedName: 'Meeting notes',
        ),
      ),
    );
    expect(doc!.isOk, isTrue);

    await pumpApp(tester);
    await tester.tap(find.text('ID Vault').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    // The vault categories sit above the list; scroll down to the document.
    await tester.scrollUntilVisible(
      find.text('Meeting notes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(find.text('Meeting notes'), findsWidgets);

    await tester.tap(find.text('Meeting notes').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.textContaining('Hello offline world'), findsOneWidget);
    await unmount(tester);
  });
}

class _FakePdf implements PdfEngine {
  @override
  Future<Result<int>> pageCount(String path) async => const Ok(1);

  @override
  Future<Result<List<String>>> extractText(String path) async =>
      const Ok(['text']);

  @override
  Future<Result<Uint8List>> renderPage(
    String path,
    int index, {
    int targetWidth = 1200,
  }) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<Uint8List>> fromImages(
    List<Uint8List> jpegPages,
    PdfBuildOptions options, {
    List<OcrResult?>? textLayers,
  }) async => Ok(Uint8List.fromList('%PDF-1.7'.codeUnits));

  @override
  Future<Result<Uint8List>> fromText(String text, TextPdfOptions options) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> merge(List<String> paths) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> selectPages(String path, List<int> pageIndices) =>
      fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> rotatePages(
    String path,
    Map<int, int> quarterTurns,
  ) => fromImages(const [], const PdfBuildOptions());

  @override
  Future<Result<Uint8List>> compress(
    String path,
    PdfCompressionLevel level, {
    void Function(double progress)? onProgress,
  }) => fromImages(const [], const PdfBuildOptions());
}

class _FakeOcr implements TextRecognizer {
  @override
  Future<EngineCapability> capability(OcrScript script) async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<OcrResult>> recognize(
    String imagePath,
    OcrScript script,
  ) async => const Ok(OcrResult.empty);
}

class _FakeScanner implements DocumentScanner {
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<List<String>>> scan({int maxPages = 50}) async =>
      const Err(AppFailure(FailureCode.captureCancelled));
}

class _FakePicker implements MediaPicker {
  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      const Ok([]);

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async => const Ok([]);
}

class _FakeShare implements ShareService {
  @override
  Future<Result<void>> share(
    List<String> absolutePaths, {
    String? subject,
  }) async => const Ok(null);

  @override
  Future<Result<void>> shareText(String text) async => const Ok(null);

  @override
  Future<Result<bool>> saveToDevice(Uint8List bytes, String fileName) async =>
      const Ok(true);

  @override
  Future<Result<void>> copyText(String text) async => const Ok(null);
}

class _FakeFace implements FaceLocator {
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<NRect?>> locateLargestFace(String imagePath) async =>
      const Ok(null);
}

class _FakeLock implements AppLock {
  // No screen lock in tests: authenticator codes show with a hint.
  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: false, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async => const Ok(true);
}

class _MemorySecrets implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Set<String>> keys() async => _values.keys.toSet();
}
