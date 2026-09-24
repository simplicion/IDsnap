import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

class FakeDraftStore implements DraftStore {
  FakeDraftStore([this.draft]);

  ScanDraft? draft;
  int saves = 0;
  int clears = 0;

  @override
  Future<ScanDraft?> load() async => draft;

  @override
  Future<void> save(ScanDraft d) async {
    draft = d;
    saves++;
  }

  @override
  Future<void> clear({bool deleteImages = true}) async {
    draft = null;
    clears++;
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

class FakeFileStore implements FileStore {
  final imported = <String>[];
  final deleted = <String>[];

  @override
  String absolute(String relativePath) => '/app/$relativePath';

  @override
  Future<String> importOriginal(String externalPath) async {
    final path = '/app/originals/${imported.length}.jpg';
    imported.add(externalPath);
    return path;
  }

  @override
  Future<Uint8List> read(String absolutePath) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> delete(String absoluteOrRelativePath) async =>
      deleted.add(absoluteOrRelativePath);

  @override
  Future<String> exportCopy(String relativePath, String fileName) async =>
      '/tmp/$fileName';

  @override
  Future<String> commit(String tempPath, String extension) async =>
      'documents/x.$extension';

  @override
  Future<void> clearTemp() async {}

  @override
  Future<bool> exists(String absolutePath) async => true;

  @override
  Future<String> readText(String absolutePath) async => '';

  @override
  Future<int> size(String absolutePath) async => 3;

  @override
  Future<StorageUsage> usage() async =>
      const StorageUsage(documents: 0, originals: 0, temp: 0);

  @override
  Future<String> writeTemp(Uint8List bytes, String extension) async =>
      '/tmp/t.$extension';

  @override
  Future<String> writeThumbnail(String documentId, Uint8List jpegBytes) async =>
      'thumbs/$documentId.jpg';
}

class FakeScanner implements DocumentScanner {
  Result<List<String>> next = const Ok(['/cache/a.jpg', '/cache/b.jpg']);
  EngineCapability cap = const EngineCapability(
    available: true,
    worksOffline: true,
  );

  @override
  Future<EngineCapability> capability() async => cap;

  @override
  Future<Result<List<String>>> scan({int maxPages = 50}) async => next;
}

class FakePicker implements MediaPicker {
  Result<List<PickedFile>> next = const Ok([
    PickedFile(path: '/picked/p.jpg', name: 'p.jpg'),
  ]);

  @override
  Future<Result<List<PickedFile>>> pickImages({bool multiple = true}) async =>
      next;

  @override
  Future<Result<List<PickedFile>>> pickFiles(
    Set<DocumentFormat> formats, {
    bool multiple = false,
  }) async => const Ok([]);
}

class FakeImages implements ImageProcessor {
  Result<DetectedQuad> detection = const Ok(
    DetectedQuad(
      Quad(
        NPoint(0.1, 0.1),
        NPoint(0.9, 0.1),
        NPoint(0.9, 0.9),
        NPoint(0.1, 0.9),
      ),
      0.9,
    ),
  );

  @override
  Future<Result<DetectedQuad>> detectDocument(Uint8List imageBytes) async =>
      detection;

  @override
  Future<Result<Uint8List>> renderPage(
    Uint8List original,
    PageEdits edits, {
    QualityPreset preset = QualityPreset.balanced,
  }) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<Uint8List>> thumbnail(
    Uint8List imageBytes, {
    int maxDimension = 480,
  }) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<EncodedImage>> crop(
    Uint8List imageBytes,
    NRect rect, {
    int? outputWidth,
    int? outputHeight,
    int quarterTurns = 0,
    ImageOutputFormat format = ImageOutputFormat.jpeg,
    int quality = 92,
  }) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<EncodedImage>> compress(
    Uint8List imageBytes,
    ImageCompressionOptions options,
  ) async => const Err(AppFailure(FailureCode.unknown));

  @override
  Future<Result<ImageDetails>> inspect(Uint8List imageBytes) async =>
      const Ok(ImageDetails(width: 10, height: 10, sizeBytes: 3));
}

class FakeRepository implements DocumentRepository {
  @override
  Stream<List<Folder>> watchFolders() => Stream.value(const []);

  @override
  Stream<List<Document>> watch(DocumentQuery query) => Stream.value(const []);

  @override
  Future<Document?> byId(String id) async => null;

  @override
  Future<Result<void>> add(Document document) async => const Ok(null);

  @override
  Future<Result<void>> update(Document document) async => const Ok(null);

  @override
  Future<Result<void>> remove(String id) async => const Ok(null);

  @override
  Future<Result<Folder>> addFolder(String name) async =>
      Ok(Folder(id: 'f', name: name, createdAt: DateTime(2026)));

  @override
  Future<Result<void>> renameFolder(String id, String name) async =>
      const Ok(null);

  @override
  Future<Result<void>> removeFolder(String id) async => const Ok(null);
}

class Fakes {
  Fakes({ScanDraft? draft, AppSettings settings = const AppSettings()})
    : drafts = FakeDraftStore(draft),
      settingsStore = FakeSettingsStore(settings);

  final FakeDraftStore drafts;
  final FakeSettingsStore settingsStore;
  final files = FakeFileStore();
  final scanner = FakeScanner();
  final picker = FakePicker();
  final images = FakeImages();
  final repository = FakeRepository();

  List<Override> get overrides => [
    draftStoreProvider.overrideWithValue(drafts),
    settingsStoreProvider.overrideWithValue(settingsStore),
    fileStoreProvider.overrideWithValue(files),
    documentScannerProvider.overrideWithValue(scanner),
    mediaPickerProvider.overrideWithValue(picker),
    imageProcessorProvider.overrideWithValue(images),
    documentRepositoryProvider.overrideWithValue(repository),
  ];
}

ScanDraft draftWith(int pages) => ScanDraft(
  id: 'd',
  createdAt: DateTime(2026, 9, 24),
  pages: [
    for (var i = 0; i < pages; i++)
      ScanPage(id: 'p$i', originalPath: '/app/originals/p$i.jpg'),
  ],
);
