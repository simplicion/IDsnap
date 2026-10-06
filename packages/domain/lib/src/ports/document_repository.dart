import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/entities/folder.dart';
import 'package:docscan_domain/src/entities/scan.dart';
import 'package:docscan_domain/src/entities/settings.dart';

/// Library metadata. Implemented by the data layer (Drift/SQLite).
abstract interface class DocumentRepository {
  Stream<List<Document>> watch(DocumentQuery query);
  Future<Document?> byId(String id);
  Future<Result<void>> add(Document document);
  Future<Result<void>> update(Document document);

  /// Removes the row only; callers delete the file through [FileStore].
  Future<Result<void>> remove(String id);

  /// Folders whose names may be shown anywhere: every folder except those
  /// inside a locked folder. Nested structure lives in `FolderRepository`.
  Stream<List<Folder>> watchFolders();

  /// Creates a top-level folder.
  Future<Result<Folder>> addFolder(String name);
  Future<Result<void>> renameFolder(String id, String name);

  /// Subfolders and documents in the folder move up to its parent.
  Future<Result<void>> removeFolder(String id);
}

/// Persists the in-progress scan so it survives backgrounding/process death.
abstract interface class DraftStore {
  Future<ScanDraft?> load();
  Future<void> save(ScanDraft draft);

  /// Deletes the draft and, when [deleteImages] is true, its captured images.
  Future<void> clear({bool deleteImages = true});
}

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
