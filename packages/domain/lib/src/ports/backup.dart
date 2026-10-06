import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/ports/archive_codec.dart';
import 'package:meta/meta.dart';

// Full backup ("Export all data"), restore and "Erase everything"
// (audit H-04, H-05, H-06). Documents, folders and notes are handled by the
// data layer's archiver; everything else the user would lose on a new phone
// plugs in as a [BackupSection].

/// Something "Erase everything" must remove.
abstract interface class Erasable {
  /// What it is, for logs and error messages ("Authenticator accounts").
  String get label;

  /// Deletes everything it holds. Must not touch licence or purchase data.
  Future<void> erase();
}

/// App data outside the documents database that belongs in a full backup:
/// authenticator accounts, saved signatures, QR history, settings…
abstract interface class BackupSection implements Erasable {
  /// Stable id: the entry `.idsnap/<key>.json` in the backup.
  String get key;

  /// A JSON-encodable snapshot, or null when there is nothing to back up.
  /// May contain secrets (the authenticator's): the export asks for a
  /// password and re-authentication.
  Future<BackupSectionData?> export();

  /// Restores [data] written by [export] with format [version] (possibly
  /// older than today's). Idempotent: items already present are skipped.
  /// Returns how many items were added.
  Future<int> restore(Object? data, {required int version});
}

/// One section's snapshot.
@immutable
class BackupSectionData {
  const BackupSectionData({
    required this.version,
    required this.data,
    required this.count,
  });

  /// Format version of [data] (bump when the shape changes).
  final int version;
  final Object? data;

  /// Items in the snapshot (shown in the summary).
  final int count;
}

/// Stage of a running backup job.
enum BackupStage {
  preparing('Preparing…'),
  documents('Documents'),
  appData('Notes, accounts and settings'),
  finishing('Finishing…');

  const BackupStage(this.label);
  final String label;
}

/// Progress of a running export or import.
@immutable
class BackupProgress {
  const BackupProgress(this.stage, this.fraction, {this.item});

  final BackupStage stage;

  /// 0..1 over the whole job.
  final double fraction;

  /// "12 of 340" style detail, when known.
  final String? item;
}

/// What an export wrote.
@immutable
class BackupResult {
  const BackupResult({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.protected,
    this.documents = 0,
    this.folders = 0,
    this.notes = 0,
    this.sections = const {},
  });

  /// The archive in the app cache. Hand it to the share sheet or "save to
  /// device", then release it (`PlainFileAccess.releaseTemp`).
  final String path;
  final String fileName;
  final int sizeBytes;

  /// True when encrypted with a password.
  final bool protected;
  final int documents;
  final int folders;
  final int notes;

  /// Section key → items exported.
  final Map<String, int> sections;
}

/// What an import restored.
@immutable
class ImportSummary {
  const ImportSummary({
    this.documents = 0,
    this.notes = 0,
    this.folders = 0,
    this.skipped = 0,
    this.sections = const {},
    this.failedSections = const {},
    this.pinLockedFolders = 0,
    this.manifestVersion = 0,
  });

  final int documents;
  final int notes;

  /// Folders created (existing same-named folders are reused).
  final int folders;

  /// Entries that were already here or couldn't be identified.
  final int skipped;

  /// Section key → items added.
  final Map<String, int> sections;

  /// Section label → why it couldn't be restored.
  final Map<String, AppFailure> failedSections;

  /// Folders that had a PIN on the old phone: PINs never leave the keystore,
  /// so they come back locked with the phone's screen lock instead.
  final int pinLockedFolders;
  final int manifestVersion;

  /// Everything added.
  int get total =>
      documents + notes + sections.values.fold<int>(0, (a, b) => a + b);
}

/// Full backup of the vault (roadmap B4, audit H-04/H-05): documents in
/// their folder tree, notes, folder settings and every [BackupSection], as
/// one ZIP, optionally AES-256 protected. Streams to and from disk.
abstract interface class LibraryArchiver {
  /// Writes a backup into the app cache and returns where. With
  /// [includeDocuments] false only notes-free [sections] are written (e.g.
  /// "Export accounts"). Nothing is left behind on failure or cancel.
  Future<Result<BackupResult>> exportBackup({
    String? password,
    List<BackupSection> sections = const [],
    bool includeDocuments = true,
    String? fileName,
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  });

  /// Restores a backup made by [exportBackup] (any manifest version up to
  /// today's) or a plain ZIP of files. Fails with `passwordProtected`
  /// before changing anything when [password] is needed, and with
  /// `wrongPassword` when it doesn't match. Idempotent.
  Future<Result<ImportSummary>> importBackup(
    String zipPath, {
    String? password,
    List<BackupSection> sections = const [],
    void Function(BackupProgress progress)? onProgress,
    JobCancelToken? cancel,
  });
}

/// "Delete all documents" and "Erase everything" (audit H-06). Locked
/// folders are included: callers re-authenticate first.
abstract interface class VaultEraser {
  /// Deletes every document (also inside locked folders) with its files and
  /// thumbnail. Folders, notes and other data stay. Returns the count.
  /// [onDeleted] runs per document (e.g. to cancel its reminders).
  Future<Result<int>> deleteAllDocuments({
    Future<void> Function(Document document)? onDeleted,
  });

  /// Removes all user data: documents, folders, notes, authenticator
  /// accounts and secrets, signatures, QR history, folder and note PINs,
  /// drafts, temporary files and settings — back to first run. Licence and
  /// purchase data are kept.
  Future<Result<void>> eraseEverything({
    Future<void> Function(Document document)? onDeleted,
  });
}

/// Saves a file that is already on disk to a user-chosen place without
/// loading it into memory (when the platform allows). Optional on a
/// `ShareService`.
abstract interface class FileSaver {
  /// Returns false when the user cancels.
  Future<Result<bool>> saveFileToDevice(String path, String fileName);
}
