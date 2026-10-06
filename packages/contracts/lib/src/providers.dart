import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
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

/// Shreds a plaintext source (picker copy, scanner output) once it has been
/// imported into the encrypted vault. Only app-owned scratch files are ever
/// removed; a file picked from the user's own storage is left alone.
/// Overridden in apps/scanner/lib/bootstrap.dart; a no-op elsewhere.
final importedSourceDisposerProvider =
    Provider<Future<void> Function(String path)>((ref) => (_) async {});
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

/// Image preprocessing for OCR (EXIF orientation, rotation/scale/contrast
/// retries). `null` means recognize files as is; the app bootstrap wires the
/// imaging-backed preparer.
final ocrImagePreparerProvider = Provider<OcrImagePreparer?>((ref) => null);

/// OCR of one image with Auto script, rotation and scale retries.
final recognizeTextProvider = Provider<RecognizeText>(
  (ref) => RecognizeText(
    recognizer: ref.watch(textRecognizerProvider),
    preparer: ref.watch(ocrImagePreparerProvider),
  ),
);

/// Page-by-page OCR of photos and PDFs with progress, cancellation and
/// per-page failures.
final recognizeDocumentProvider = Provider<RecognizeDocument>(
  (ref) => RecognizeDocument(
    recognize: ref.watch(recognizeTextProvider),
    pdf: ref.watch(pdfEngineProvider),
    files: ref.watch(fileStoreProvider),
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

/// Nested folders (ID Vault). Defaults to the wired [DocumentRepository]
/// when it also implements [FolderRepository] (the Drift one does), so apps
/// need no extra wiring.
final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  final repo = ref.watch(documentRepositoryProvider);
  if (repo is FolderRepository) return repo as FolderRepository;
  return _missing('FolderRepository');
});

/// Face detection for automatic passport/ID photo framing.
final faceLocatorProvider = Provider<FaceLocator>(
  (ref) => _missing('FaceLocator'),
);

// ── Roadmap ports (docs/product/roadmap-vault-id-card.md) ───────────────────

final sheetPdfBuilderProvider = Provider<SheetPdfBuilder>(
  (ref) => _missing('SheetPdfBuilder'),
);
final appLockProvider = Provider<AppLock>((ref) => _missing('AppLock'));
final libraryArchiverProvider = Provider<LibraryArchiver>(
  (ref) => _missing('LibraryArchiver'),
);
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => _missing('ReminderScheduler'),
);
final signatureProcessorProvider = Provider<SignatureProcessor>(
  (ref) => _missing('SignatureProcessor'),
);

/// PDF stamping (PRD 3.3). Defaults to the wired [PdfEngine] when it also
/// implements [PdfStamper] (the PDFium engine does), so apps need no extra
/// wiring.
final pdfStamperProvider = Provider<PdfStamper>((ref) {
  final pdf = ref.watch(pdfEngineProvider);
  if (pdf is PdfStamper) return pdf as PdfStamper;
  return _missing('PdfStamper');
});

/// PDF password protection/removal. Defaults to the wired [PdfEngine] when
/// it also implements [PdfProtector] (the PDFium engine does).
final pdfProtectorProvider = Provider<PdfProtector>((ref) {
  final pdf = ref.watch(pdfEngineProvider);
  if (pdf is PdfProtector) return pdf as PdfProtector;
  return _missing('PdfProtector');
});

/// AES-256 ZIP (WinZip AE-2). Defaults to the wired [PdfEngine] when it also
/// implements [ProtectedZipWriter] (the engine_pdf one does).
final protectedZipWriterProvider = Provider<ProtectedZipWriter>((ref) {
  final pdf = ref.watch(pdfEngineProvider);
  if (pdf is ProtectedZipWriter) return pdf as ProtectedZipWriter;
  return _missing('ProtectedZipWriter');
});

// ── Authenticator (PRD Module 2) ─────────────────────────────────────────────

final authenticatorRepositoryProvider = Provider<AuthenticatorRepository>(
  (ref) => _missing('AuthenticatorRepository'),
);
final otpCodecProvider = Provider<OtpCodec>((ref) => _missing('OtpCodec'));

// ── Encryption at rest (ADR-0010) ───────────────────────────────────────────

/// Plaintext copies of encrypted vault files for path-based APIs (PDF
/// viewer, PDFium tools, ML Kit). Defaults to the wired [FileStore] when it
/// also implements [PlainFileAccess] (the encrypted store does); otherwise
/// paths are used as they are (tests, previews).
final plainFileAccessProvider = Provider<PlainFileAccess>((ref) {
  final files = ref.watch(fileStoreProvider);
  if (files is PlainFileAccess) return files as PlainFileAccess;
  return const PassThroughFileAccess();
});

/// Decrypted bytes of a vault image (thumbnails), keyed by library-relative
/// or absolute path. `null` when the file is missing or unreadable.
final vaultImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, path) async {
      final files = ref.watch(fileStoreProvider);
      try {
        if (!await files.exists(path)) return null;
        return await files.read(files.absolute(path));
      } on Object {
        return null;
      }
    }, retry: (_, _) => null);

/// The vault file cipher for stores outside the [FileStore] (saved
/// signatures). `null` = no encryption (tests, previews).
final fileCipherProvider = Provider<FileCipher?>((ref) => null);

// ── Secure notes (feature_notes) ────────────────────────────────────────────

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => _missing('NotesRepository'),
);

// ── Full backup and erase (audit H-04, H-05, H-06) ──────────────────────────

/// Everything besides documents, folders and notes that the full backup
/// carries and "Erase everything" removes (authenticator accounts, saved
/// signatures, QR history, settings). The app wires the real ones.
final backupSectionsProvider = Provider<List<BackupSection>>((ref) => const []);

/// "Delete all documents" / "Erase everything".
final vaultEraserProvider = Provider<VaultEraser>(
  (ref) => _missing('VaultEraser'),
);

/// Saves a file on disk to a user-chosen place. Defaults to the wired
/// [ShareService] when it also implements [FileSaver]; otherwise the file is
/// read into memory and passed to `saveToDevice` (tests, previews).
final fileSaverProvider = Provider<FileSaver>((ref) {
  final share = ref.watch(shareServiceProvider);
  if (share is FileSaver) return share as FileSaver;
  return _BytesFileSaver(share, ref.watch(fileStoreProvider));
});

class _BytesFileSaver implements FileSaver {
  const _BytesFileSaver(this._share, this._files);

  final ShareService _share;
  final FileStore _files;

  @override
  Future<Result<bool>> saveFileToDevice(String path, String fileName) async {
    final Uint8List bytes;
    try {
      bytes = await _files.read(path);
    } on Object catch (e, st) {
      return Err(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
    return await _share.saveToDevice(bytes, fileName);
  }
}

/// Rebuilds every provider from scratch (after "Erase everything"). `null`
/// when the app shell doesn't support it; callers then ask the user to
/// reopen the app. The app shell provides it.
final appRestartProvider = Provider<void Function()?>((ref) => null);
