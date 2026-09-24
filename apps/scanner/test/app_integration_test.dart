import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/app.dart';
import 'package:drift/native.dart';
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
    for (final tab in ['Files', 'Tools', 'Settings', 'Home']) {
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
      Routes.privacy,
      Routes.about,
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
    await tester.tap(find.text('Files').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
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
