import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements DocumentRepository {}

class MockFiles extends Mock implements FileStore {}

class MockImages extends Mock implements ImageProcessor {}

class MockPdf extends Mock implements PdfEngine {}

class MockConversion extends Mock implements ConversionEngine {}

class MockCommit extends Mock implements CommitOutput {}

class MockShare extends Mock implements ShareService {}

class MockPicker extends Mock implements MediaPicker {}

void registerFallbacks() {
  registerFallbackValue(
    OutputFile(
      bytes: Uint8List(0),
      format: DocumentFormat.pdf,
      suggestedName: 'x',
    ),
  );
  registerFallbackValue(const ImageCompressionOptions());
  registerFallbackValue(const DocumentQuery());
  registerFallbackValue(NRect.full);
  registerFallbackValue(Uint8List(0));
  registerFallbackValue(const PdfBuildOptions());
  registerFallbackValue(const PageEdits());
  registerFallbackValue(const ConversionRequest(specId: 'x', inputs: []));
}

Document doc(
  String id, {
  DocumentFormat format = DocumentFormat.pdf,
  String name = 'Report',
  int size = 1000,
}) => Document(
  id: id,
  name: name,
  format: format,
  relativePath: 'documents/$id.${format.extension}',
  sizeBytes: size,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const pdfToDocx = ConversionSpec(
  id: 'pdf-docx',
  title: 'PDF to Word',
  inputs: {DocumentFormat.pdf},
  output: DocumentFormat.docx,
  fidelity: FidelityClass.content,
  category: ConversionCategory.fromPdf,
  limitations: ['Tables become plain paragraphs.'],
);

const txtToPdf = ConversionSpec(
  id: 'txt-pdf',
  title: 'Text to PDF',
  inputs: {DocumentFormat.txt},
  output: DocumentFormat.pdf,
  fidelity: FidelityClass.content,
  category: ConversionCategory.toPdf,
);

/// Wires every port with a mock; tests stub only what they need.
class Harness {
  Harness() {
    when(
      () => files.absolute(any()),
    ).thenAnswer((i) => '/app/${i.positionalArguments.first}');
    when(() => files.read(any())).thenAnswer((_) async => Uint8List(8));
    when(() => files.size(any())).thenAnswer((_) async => 4096);
    when(() => repo.byId(any())).thenAnswer((_) async => null);
    when(
      () => repo.watch(any()),
    ).thenAnswer((_) => Stream.value(const <Document>[]));
    when(
      () =>
          pdf.renderPage(any(), any(), targetWidth: any(named: 'targetWidth')),
    ).thenAnswer((_) async => const Err(AppFailure(FailureCode.corruptFile)));
    when(() => conversion.specs).thenReturn(const [pdfToDocx, txtToPdf]);
  }

  final repo = MockRepo();
  final files = MockFiles();
  final images = MockImages();
  final pdf = MockPdf();
  final conversion = MockConversion();
  final commit = MockCommit();
  final share = MockShare();
  final picker = MockPicker();

  List<Override> get overrides => [
    documentRepositoryProvider.overrideWithValue(repo),
    fileStoreProvider.overrideWithValue(files),
    imageProcessorProvider.overrideWithValue(images),
    pdfEngineProvider.overrideWithValue(pdf),
    conversionEngineProvider.overrideWithValue(conversion),
    commitOutputProvider.overrideWithValue(commit),
    shareServiceProvider.overrideWithValue(share),
    mediaPickerProvider.overrideWithValue(picker),
    currentSettingsProvider.overrideWithValue(const AppSettings()),
  ];

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: AppTheme.light(), home: child),
      ),
    );
    await tester.pumpAndSettle();
  }
}
