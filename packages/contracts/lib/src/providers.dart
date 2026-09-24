import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Never _missing(String port) => throw UnimplementedError(
  '$port is not wired. Override it in the app bootstrap.',
);

// ── Ports: overridden by apps/*/lib/bootstrap.dart ─────────────────────────

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => _missing('DocumentRepository'),
);
final draftStoreProvider = Provider<DraftStore>(
  (ref) => _missing('DraftStore'),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => _missing('SettingsStore'),
);
final fileStoreProvider = Provider<FileStore>((ref) => _missing('FileStore'));
final imageProcessorProvider = Provider<ImageProcessor>(
  (ref) => _missing('ImageProcessor'),
);
final pdfEngineProvider = Provider<PdfEngine>((ref) => _missing('PdfEngine'));
final textRecognizerProvider = Provider<TextRecognizer>(
  (ref) => _missing('TextRecognizer'),
);
final documentScannerProvider = Provider<DocumentScanner>(
  (ref) => _missing('DocumentScanner'),
);
final mediaPickerProvider = Provider<MediaPicker>(
  (ref) => _missing('MediaPicker'),
);
final shareServiceProvider = Provider<ShareService>(
  (ref) => _missing('ShareService'),
);
final conversionEngineProvider = Provider<ConversionEngine>(
  (ref) => _missing('ConversionEngine'),
);

// ── Use cases ───────────────────────────────────────────────────────────────

final commitOutputProvider = Provider<CommitOutput>(
  (ref) => CommitOutput(
    files: ref.watch(fileStoreProvider),
    repository: ref.watch(documentRepositoryProvider),
    pdf: ref.watch(pdfEngineProvider),
    images: ref.watch(imageProcessorProvider),
  ),
);

final saveScanAsPdfProvider = Provider<SaveScanAsPdf>(
  (ref) => SaveScanAsPdf(
    files: ref.watch(fileStoreProvider),
    images: ref.watch(imageProcessorProvider),
    pdf: ref.watch(pdfEngineProvider),
    commit: ref.watch(commitOutputProvider),
    ocr: ref.watch(textRecognizerProvider),
  ),
);

// ── Shared queries ──────────────────────────────────────────────────────────

/// Live library listing for a query. Used by Home (recents) and Files.
final documentsProvider = StreamProvider.family<List<Document>, DocumentQuery>(
  (ref, query) => ref.watch(documentRepositoryProvider).watch(query),
);

final documentByIdProvider = FutureProvider.family<Document?, String>(
  (ref, id) => ref.watch(documentRepositoryProvider).byId(id),
);

final foldersProvider = StreamProvider<List<Folder>>(
  (ref) => ref.watch(documentRepositoryProvider).watchFolders(),
);

/// Face detection for automatic passport/ID photo framing.
final faceLocatorProvider = Provider<FaceLocator>(
  (ref) => _missing('FaceLocator'),
);
