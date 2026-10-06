import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fakes.dart';

/// A valid 1×1 PNG so Image.memory can decode it in widget tests.
final kPng1x1 = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0x89,
  0x99,
  0x3D,
  0x1D,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Renders succeed; rendered images report [renderWidth] × [renderHeight].
class CardImages extends FakeImages {
  int renderWidth = 1586;
  int renderHeight = 1000;
  final renders = <PageEdits>[];

  @override
  Future<Result<Uint8List>> renderPage(
    Uint8List original,
    PageEdits edits, {
    QualityPreset preset = QualityPreset.balanced,
  }) async {
    renders.add(edits);
    return Ok(kPng1x1);
  }

  @override
  Future<Result<ImageDetails>> inspect(Uint8List imageBytes) async =>
      Ok(ImageDetails(width: renderWidth, height: renderHeight, sizeBytes: 10));
}

class FakeSheetBuilder implements SheetPdfBuilder {
  Result<Uint8List> next = Ok(Uint8List.fromList('%PDF-1.7'.codeUnits));
  final calls = <(List<PlacedImage>, double, double, String?)>[];

  @override
  Future<Result<Uint8List>> build(
    List<PlacedImage> images, {
    required double pageWidthPt,
    required double pageHeightPt,
    String? watermark,
  }) async {
    calls.add((images, pageWidthPt, pageHeightPt, watermark));
    return next;
  }
}

class _NoPdf implements PdfEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [CommitOutput] whose result is controlled by the test. [gate] lets a test
/// observe the "saving" state before the commit completes.
class FakeCommit extends CommitOutput {
  FakeCommit()
    : super(
        files: FakeFileStore(),
        repository: FakeRepository(),
        pdf: _NoPdf(),
        images: FakeImages(),
      );

  final outputs = <OutputFile>[];
  final folderIds = <String?>[];
  Completer<void>? gate;
  AppFailure? failWith;

  @override
  Future<Result<Document>> call(OutputFile output, {String? folderId}) async {
    outputs.add(output);
    folderIds.add(folderId);
    await gate?.future;
    final f = failWith;
    if (f != null) return Err(f);
    return Ok(
      Document(
        id: 'doc1',
        name: output.suggestedName,
        format: output.format,
        relativePath: 'documents/doc1.pdf',
        sizeBytes: output.bytes.length,
        pageCount: 1,
        folderId: folderId,
        createdAt: DateTime(2026, 9, 25),
        updatedAt: DateTime(2026, 9, 25),
      ),
    );
  }
}

/// Folders for "Save to folder" tests.
class FakeFolders implements FolderRepository {
  FakeFolders(this.folders);

  final List<Folder> folders;

  @override
  Future<List<Folder>> allFolders() async => folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(folders);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Folder testFolder(
  String id,
  String name, {
  String? parentId,
  FolderLockMode lockMode = FolderLockMode.none,
}) => Folder(
  id: id,
  name: name,
  parentId: parentId,
  lockMode: lockMode,
  createdAt: DateTime(2026),
);

class RecordingRepository extends FakeRepository {
  final updates = <Document>[];

  @override
  Future<Result<void>> update(Document document) async {
    updates.add(document);
    return const Ok(null);
  }
}

class IdCardFakes extends Fakes {
  IdCardFakes() : super();

  final cardImages = CardImages();
  final sheet = FakeSheetBuilder();
  final commit = FakeCommit();
  final recordingRepo = RecordingRepository();

  @override
  List<Override> get overrides => [
    draftStoreProvider.overrideWithValue(drafts),
    settingsStoreProvider.overrideWithValue(settingsStore),
    fileStoreProvider.overrideWithValue(files),
    documentScannerProvider.overrideWithValue(scanner),
    mediaPickerProvider.overrideWithValue(picker),
    imageProcessorProvider.overrideWithValue(cardImages),
    documentRepositoryProvider.overrideWithValue(recordingRepo),
    sheetPdfBuilderProvider.overrideWithValue(sheet),
    commitOutputProvider.overrideWithValue(commit),
  ];
}
